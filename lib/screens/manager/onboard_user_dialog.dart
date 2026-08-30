import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/staff.dart';
import '../../models/user_role.dart';
import '../../providers/auth_session_provider.dart';
import '../../firebase/firebase_context_provider.dart';
import '../../services/access_control_service.dart';
import '../../services/email_service.dart';
import '../../services/manager_account_service.dart';
import '../../services/notification_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/country_options.dart';
import '../../utils/departments.dart';
import '../../utils/profile_photo_picker.dart';

class OnboardUserDialog extends StatefulWidget {
  final String currentManagerName;
  final String currentManagerEmail;
  final AppUserRole onboarderRole;

  const OnboardUserDialog({
    super.key,
    required this.currentManagerName,
    required this.currentManagerEmail,
    required this.onboarderRole,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String currentManagerName,
    required String currentManagerEmail,
    required AppUserRole onboarderRole,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OnboardUserDialog(
        currentManagerName: currentManagerName,
        currentManagerEmail: currentManagerEmail,
        onboarderRole: onboarderRole,
      ),
    );
  }

  @override
  State<OnboardUserDialog> createState() => _OnboardUserDialogState();
}

class _OnboardUserDialogState extends State<OnboardUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _staffService = StaffService();
  final _managerAccountService = ManagerAccountService();
  final _accessControl = AccessControlService();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _maxStaffCtrl = TextEditingController(text: '20');
  String _selectedDialCode = '+91';

  // New demographic fields
  String? _selectedBloodGroup;
  String? _selectedGender;
  String? _selectedNationality;
  DateTime? _dob;
  final _addressCtrl = TextEditingController();

  DateTime _joinDate = DateTime.now();
  bool _isActive = true;
  bool _submitting = false;
  bool _obscurePassword = true;
  bool _pickingPhoto = false;
  String? _photoUrl;

  /// The role selected from the User Roles Management catalog (`roles`
  /// collection). System/protected roles (e.g. Company Admin) are excluded
  /// from selection both in the UI and in [_submit].
  UserRole? _selectedUserRole;

  AppUserRole get _assignedRole =>
      (_selectedUserRole?.isManagerial ?? false)
          ? AppUserRole.manager
          : AppUserRole.employee;
  String? _selectedDepartment;

  String? _selectedManagerName;
  String? _selectedManagerUserId;
  List<_ManagerOption> _managerOptions = const [];
  bool _loadingManagers = true;
  String? _managerError;

  bool get _canAssignManager => widget.onboarderRole == AppUserRole.admin;

  static const _accent = Color(0xFF0F766E);
  static const _border = AppThemeColors.darkBorder;
  static const _label = AppThemeColors.darkText;
  static const _subtle = AppThemeColors.darkMuted;

  @override
  void initState() {
    super.initState();
    _selectedManagerName = widget.currentManagerName.trim().isEmpty
        ? null
        : widget.currentManagerName.trim();
    _loadManagers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _employeeIdCtrl.dispose();
    _passwordCtrl.dispose();
    _maxStaffCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// Loads the "Reports to" candidates. A user is eligible when their assigned
  /// role (`users/{uid}.roleId` → `roles/{roleId}.canBeReportingManager`) is
  /// flagged `canBeReportingManager: true`. The list is independent of the
  /// currently selected "Assign role" — every eligible manager/Company Admin
  /// (or custom role with the flag enabled) appears as a reporting option.
  Future<void> _loadManagers() async {
    _managerError = null;
    try {
      final roles = await _accessControl.getAllRoles().first;
      final eligibleRoleIds = roles
          .where((r) => r.canBeReportingManager)
          .map((r) => r.id)
          .toList();
      final roleNameById = <String, String>{
        for (final r in roles) r.id: r.name,
      };

      final options = <_ManagerOption>[];
      if (eligibleRoleIds.isNotEmpty) {
        // The `users` collection is already scoped to this tenant's Firebase
        // project, so no companyId filter is required here.
        final snap = await FirebaseContextProvider.current.firestore
            .collection('users')
            .where('roleId', whereIn: eligibleRoleIds.take(30).toList())
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          final name = (data['name'] as String? ?? '').trim();
          if (name.isEmpty) continue;
          final roleId = (data['roleId'] as String? ?? '').trim();
          options.add(_ManagerOption(
            name: name,
            email: (data['email'] as String? ?? '').trim(),
            roleName: roleNameById[roleId] ?? roleId,
            userId: doc.id,
          ));
        }
      }

      // A previously selected "Reports to" that is no longer eligible is
      // cleared so the admin must reselect.
      final selectedName = _selectedManagerName;
      if (selectedName != null &&
          !options.any((o) => o.name == selectedName)) {
        _selectedManagerName = null;
        _selectedManagerUserId = null;
      }

      options
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _managerOptions = options;
        _loadingManagers = false;
      });
    } catch (e, st) {
      debugPrint('OnboardUserDialog._loadManagers failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _managerError =
            'Could not load managers. Check your connection and try again.';
        _loadingManagers = false;
      });
    }
  }

  Future<void> _pickJoinDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joinDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _joinDate = picked);
    }
  }

  Future<void> _pickProfilePhoto() async {
    if (_submitting || _pickingPhoto) return;
    try {
      setState(() => _pickingPhoto = true);
      final photoUrl = await pickProfilePhotoDataUrl();
      if (photoUrl == null) return;
      if (!mounted) return;
      setState(() {
        _photoUrl = photoUrl;
      });
    } catch (e) {
      if (!mounted) return;
      _showError('Unable to pick profile photo: $e');
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  ImageProvider? _profileImageProvider() {
    final raw = _photoUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('data:image')) {
      final payload = raw.contains(',') ? raw.split(',').last : raw;
      try {
        return MemoryImage(base64Decode(payload));
      } catch (_) {
        return null;
      }
    }
    return NetworkImage(raw);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final selectedRole = _selectedUserRole;
    if (selectedRole == null) {
      _showError('Please select a role.');
      return;
    }
    // Domain-level guard: protected/system roles (Company Admin) can never be
    // assigned through onboarding, even if a crafted request bypasses the UI.
    if (selectedRole.isSystem ||
        selectedRole.id.trim().toLowerCase() == 'company_admin') {
      _showError(
          'The Company Admin role is system-protected and cannot be assigned '
          'during onboarding.');
      return;
    }
    if (_assignedRole == AppUserRole.manager && !_canAssignManager) {
      _showError('Only admins can onboard a manager.');
      return;
    }
    if (_assignedRole == AppUserRole.employee &&
        (_selectedManagerName == null || _selectedManagerName!.isEmpty)) {
      _showError('Please select a reporting manager.');
      return;
    }
    if (_selectedDepartment == null) {
      _showError('Please select a designation.');
      return;
    }
    if (_isActive && _passwordCtrl.text.trim().isEmpty) {
      _showError('Enter a password to create the login account.');
      return;
    }

    // Demographic validators
    if (_selectedBloodGroup == null) {
      _showError('Please select a blood group.');
      return;
    }
    if (_selectedGender == null) {
      _showError('Please select a gender.');
      return;
    }
    if (_selectedNationality == null || _selectedNationality!.trim().isEmpty) {
      _showError('Nationality is required.');
      return;
    }
    if (_dob == null) {
      _showError('Please select a date of birth.');
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      _showError('Address is required.');
      return;
    }

    setState(() => _submitting = true);
    final email = _emailCtrl.text.trim().toLowerCase();
    final name = _nameCtrl.text.trim();
    final department = _selectedDepartment!;
    final password = _passwordCtrl.text.trim();
    final phone = '$_selectedDialCode ${_phoneCtrl.text.trim()}'.trim();
    final nationality = _selectedNationality!;
    var emailSent = false;
    String? emailError;

    try {
      if (_assignedRole == AppUserRole.employee) {
        final emailTaken = await _staffService.isEmailAlreadyUsed(email);
        if (emailTaken) {
          _showError(
              'A user with this email already exists as ${selectedRole.name}.');
          setState(() => _submitting = false);
          return;
        }

        final staff = Staff(
          id: '',
          name: name,
          email: email,
          companyId: FirebaseContextProvider.current.app.name,
          phone: phone,
          department: department,
          position: '',
          employeeId: _employeeIdCtrl.text.trim(),
          joinDate: _joinDate,
          reportsTo: _selectedManagerName,
          isActive: _isActive,
          password: _isActive ? password : null,
          hasRegistered: _isActive,
          photoUrl: _photoUrl,
          bloodGroup: _selectedBloodGroup,
          gender: _selectedGender,
          nationality: nationality,
          dob: _dob,
          address: _addressCtrl.text.trim(),
          // Persist the selected role from User Roles Management.
          role: 'staff',
          roleId: selectedRole.id,
          roleName: selectedRole.name,
          roleLevel: selectedRole.level,
          reportsToUserId: _selectedManagerUserId,
        );

        await _staffService.addStaff(staff);
      } else {
        final managers = FirebaseContextProvider.current.firestore.collection('managers');
        final existing =
            await managers.where('email', isEqualTo: email).limit(1).get();
        if (existing.docs.isNotEmpty) {
          _showError('A manager with this email already exists.');
          setState(() => _submitting = false);
          return;
        }

        if (_isActive) {
          await _managerAccountService.createManagerAccount(
            name: name,
            email: email,
            password: password,
            phone: phone,
            employeeId: _employeeIdCtrl.text.trim(),
            department: department,
            staffCount: 0,
            maxStaff: int.tryParse(_maxStaffCtrl.text.trim()) ?? 20,
            joinDate: _joinDate,
            status: 'active',
            photoUrl: _photoUrl,
            bloodGroup: _selectedBloodGroup,
            gender: _selectedGender,
            nationality: nationality,
            dob: _dob,
            address: _addressCtrl.text.trim(),
            // Persist the selected managerial role from User Roles Management.
            roleId: selectedRole.id,
            roleName: selectedRole.name,
            roleLevel: selectedRole.level,
          );
        } else {
          await managers.add({
            'name': name,
            'email': email,
            'phone': phone,
            'employeeId': _employeeIdCtrl.text.trim(),
            'department': department,
            'joinDate': Timestamp.fromDate(_joinDate),
            'status': 'inactive',
            'photoUrl': _photoUrl,
            'staffCount': 0,
            'maxStaff': int.tryParse(_maxStaffCtrl.text.trim()) ?? 20,
            'hasRegistered': false,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'roleId': selectedRole.id,
            'roleName': selectedRole.name,
            'roleLevel': selectedRole.level,
            'bloodGroup': _selectedBloodGroup,
            'gender': _selectedGender,
            'nationality': nationality,
            'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
            'address': _addressCtrl.text.trim(),
          });
        }
      }

      if (_isActive) {
        try {
          await EmailService.sendAccountCredentials(
            recipientEmail: email,
            password: password,
            roleLabel: selectedRole.name.toLowerCase(),
            recipientName: name,
          );
          emailSent = true;

          // Send credentials push notification to the employee
          await NotificationService().sendNotificationToUser(
            identifier: email,
            title: 'Welcome to the Team!',
            body:
                'Your login credentials: User ID: $email and Temporary Password: $password. Please log in and change your password.',
          );

          // Save credentials notification in Firestore
          await FirebaseContextProvider.current.firestore.collection('notifications').add({
            'recipient': email,
            'type': 'Email',
            'content':
                'Welcome! Your login credentials: User ID: $email, Password: $password.',
            'status': 'Sent',
            'suppressFirestorePush': true,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // Send password change push notification reminder to the employee
          await NotificationService().sendNotificationToUser(
            identifier: email,
            title: 'Security Notice: Change Password',
            body:
                'Please change your temporary password for your security and privacy.',
          );

          // Save security notification in Firestore
          await FirebaseContextProvider.current.firestore.collection('notifications').add({
            'recipient': email,
            'type': 'Security',
            'content':
                'Important: Please change your temporary password for security purposes.',
            'status': 'Sent',
            'suppressFirestorePush': true,
            'timestamp': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          emailError = e.toString().replaceFirst('Exception: ', '');
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              emailError == null ? Colors.green.shade600 : Colors.orange,
          content: Text(
            !_isActive
                ? 'Onboarded $name as ${selectedRole.name}. Login access is disabled.'
                : emailSent
                    ? 'Created login for $email and sent the credentials by email.'
                    : 'Created login for $email, but email was not sent. $emailError',
          ),
        ),
      );
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
      setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade600,
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final dialogWidth = mediaWidth < 720 ? mediaWidth - 32 : 640.0;

    return Dialog(
      backgroundColor: AppThemeColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRoleChooser(),
                      const SizedBox(height: 14),
                      _buildPhotoPicker(),
                      const SizedBox(height: 14),
                      _twoCol(
                        _field(
                          controller: _nameCtrl,
                          label: 'Full name',
                          hint: 'Jane Doe',
                          required: true,
                        ),
                        _field(
                          controller: _emailCtrl,
                          label: 'Email',
                          hint: 'jane@company.com',
                          required: true,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) return 'Email is required';
                            if (!v.contains('@') || !v.contains('.')) {
                              return 'Enter a valid email';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      _twoCol(
                        _buildPhoneField(),
                        _field(
                          controller: _employeeIdCtrl,
                          label: 'Employee ID',
                          hint: 'EMP-1024',
                          required: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildDepartmentDropdown(),
                      const SizedBox(height: 14),
                      if (_assignedRole == AppUserRole.employee)
                        _twoCol(
                          _buildJoinDate(),
                          _buildManagerDropdown(),
                        )
                      else if (_assignedRole == AppUserRole.manager)
                        _twoCol(
                          _buildJoinDate(),
                          _field(
                            controller: _maxStaffCtrl,
                            label: 'Max Employees',
                            hint: '20',
                            required: true,
                            keyboardType: TextInputType.number,
                          ),
                        )
                      else
                        _buildJoinDate(),
                      const SizedBox(height: 14),
                      _twoCol(
                        _buildBloodGroupDropdown(),
                        _buildGenderDropdown(),
                      ),
                      const SizedBox(height: 14),
                      _twoCol(
                        _buildNationalityDropdown(),
                        _buildDOBPicker(),
                      ),
                      const SizedBox(height: 14),
                      _field(
                        controller: _addressCtrl,
                        label: 'Address',
                        hint: 'Enter home address detail',
                        required: true,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      _buildPasswordField(),
                      const SizedBox(height: 16),
                      _buildAccessToggle(),
                      const SizedBox(height: 16),
                      _buildAccessNotice(),
                    ],
                  ),
                ),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add_alt_1_rounded,
                color: _accent, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Onboard new user',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _label,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Add them to the staff directory and map them to a reporting manager.',
                  style: TextStyle(fontSize: 13, color: _subtle),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: _subtle),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(foregroundColor: _subtle),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label:
                        Text(_submitting ? 'Onboarding…' : 'Onboard user'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Designation', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppThemeColors.darkSurface,
              value: _selectedDepartment,
              hint: const Text(
                'Select designation',
                style: TextStyle(color: _subtle, fontSize: 13),
              ),
              icon:
                  const Icon(Icons.keyboard_arrow_down_rounded, color: _subtle),
              items: kAppDepartments
                  .map((d) => DropdownMenuItem<String>(
                        value: d,
                        child: Text(
                          d,
                          style: const TextStyle(
                              color: _label, fontWeight: FontWeight.w600),
                        ),
                      ))
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _selectedDepartment = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Phone', required: true),
        const SizedBox(height: 6),
        TextFormField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: _label, fontSize: 14),
          decoration: _inputDecoration('Phone number').copyWith(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 6),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedDialCode,
                  dropdownColor: AppThemeColors.darkSurface,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: _subtle, size: 18),
                  items: kPhoneDialCodeOptions
                      .map((code) => DropdownMenuItem<String>(
                            value: code,
                            child: Text(
                              code,
                              style: const TextStyle(
                                color: _label,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ))
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(
                            () => _selectedDialCode = value ?? '+91',
                          ),
                ),
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 86, minHeight: 0),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) return 'Required';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildNationalityDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Nationality', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppThemeColors.darkSurface,
              value: _selectedNationality,
              hint: const Text(
                'Select nationality',
                style: TextStyle(color: _subtle, fontSize: 13),
              ),
              icon:
                  const Icon(Icons.keyboard_arrow_down_rounded, color: _subtle),
              items: kNationalityOptions
                  .map((nationality) => DropdownMenuItem<String>(
                        value: nationality,
                        child: Text(
                          nationality,
                          style: const TextStyle(
                            color: _label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _selectedNationality = value),
            ),
          ),
        ),
      ],
    );
  }

  /// Roles assignable during onboarding: everything from the User Roles
  /// Management catalog EXCEPT protected system roles (Company Admin).
  /// Guarded by flag AND by id so a mis-flagged company_admin can never slip
  /// through, and enforced again at submit time.
  List<UserRole> _assignableRoles(List<UserRole> all) {
    return all
        .where((r) =>
            !r.isSystem &&
            r.id.trim().toLowerCase() != 'company_admin')
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Widget _buildRoleChooser() {
    return StreamBuilder<List<UserRole>>(
      stream: _accessControl.getAllRoles(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
            'Could not load roles. Please retry.',
            style: TextStyle(color: Colors.redAccent, fontSize: 12),
          );
        }
        final all = snapshot.data ?? const <UserRole>[];
        final roles = _assignableRoles(all);

        // Default the selection to the seeded employee role (or the first
        // available) exactly once, mirroring the previous default behaviour.
        if (_selectedUserRole == null && roles.isNotEmpty) {
          UserRole? initial;
          for (final r in roles) {
            if (r.id == 'employee') {
              initial = r;
              break;
            }
          }
          _selectedUserRole = initial ?? roles.first;
        }

        // Drop a stale selection if the role was deleted while the dialog is
        // open (User Roles Management is live in another tab/session).
        final selected = _selectedUserRole;
        if (selected != null && !roles.any((r) => r.id == selected.id)) {
          _selectedUserRole =
              roles.any((r) => r.id == 'employee')
                  ? roles.firstWhere((r) => r.id == 'employee')
                  : (roles.isNotEmpty ? roles.first : null);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel('Assign role', required: true),
            const SizedBox(height: 8),
            if (!snapshot.hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (roles.isEmpty)
              const Text(
                'No assignable roles configured. Create roles in '
                'User Roles Management first.',
                style: TextStyle(color: _subtle, fontSize: 12),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppThemeColors.darkCanvas,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: AppThemeColors.darkSurface,
                    value: _selectedUserRole?.id,
                    hint: const Text('Select a role',
                        style: TextStyle(color: _subtle)),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _subtle),
                    items: [
                      for (final role in roles)
                        DropdownMenuItem<String>(
                          value: role.id,
                          enabled: !_submitting &&
                              (!role.isManagerial || _canAssignManager),
                          child: Text(
                            role.name,
                            style: const TextStyle(
                                color: _label, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (id) {
                            if (id == null) return;
                            final match =
                                roles.where((r) => r.id == id).firstOrNull;
                            if (match != null) {
                              setState(() => _selectedUserRole = match);
                            }
                          },
                  ),
                ),
              ),
            if (_selectedUserRole?.isManagerial ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Manages a team of engineers.'
                  '${_canAssignManager ? '' : ' Only admins can onboard managers.'}',
                  style: const TextStyle(color: _subtle, fontSize: 11),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPhotoPicker() {
    final image = _profileImageProvider();
    final initial =
        _nameCtrl.text.trim().isNotEmpty ? _nameCtrl.text.trim()[0] : 'U';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 460;
        final avatar = CircleAvatar(
          radius: 26,
          backgroundColor: _accent.withValues(alpha: 0.16),
          backgroundImage: image,
          child: image == null
              ? Text(
                  initial.toUpperCase(),
                  style: const TextStyle(
                    color: _label,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        );
        const copy = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile photo',
              style: TextStyle(
                color: _label,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Optional photo for the directory and attendance logs.',
              style: TextStyle(color: _subtle, fontSize: 12),
            ),
          ],
        );
        final uploadButton = OutlinedButton.icon(
          onPressed: _submitting || _pickingPhoto ? null : _pickProfilePhoto,
          icon: _pickingPhoto
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_camera_rounded, size: 17),
          label: Text(_photoUrl == null ? 'Upload' : 'Change'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _accent),
          ),
        );
        final removeButton = _photoUrl == null
            ? null
            : IconButton(
                onPressed:
                    _submitting ? null : () => setState(() => _photoUrl = null),
                icon: const Icon(Icons.delete_outline_rounded),
                color: Colors.redAccent,
                tooltip: 'Remove photo',
              );

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        avatar,
                        const SizedBox(width: 14),
                        const Expanded(child: copy),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: uploadButton),
                        if (removeButton != null) ...[
                          const SizedBox(width: 8),
                          removeButton,
                        ],
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    avatar,
                    const SizedBox(width: 14),
                    const Expanded(child: copy),
                    const SizedBox(width: 10),
                    uploadButton,
                    if (removeButton != null) ...[
                      const SizedBox(width: 8),
                      removeButton,
                    ],
                  ],
                ),
        );
      },
    );
  }

  Widget _twoCol(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, c) {
        final stack = c.maxWidth < 520;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 14), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 14),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = false,
    TextInputType? keyboardType,
    bool obscureText = false,
    int? maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: maxLines,
          style: const TextStyle(color: _label, fontSize: 14),
          cursorColor: _accent,
          decoration: _inputDecoration(hint),
          validator: validator ??
              (value) {
                if (!required) return null;
                if (value == null || value.trim().isEmpty) {
                  return '$label is required';
                }
                return null;
              },
        ),
      ],
    );
  }

  Widget _buildJoinDate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Date of Join', required: true),
        const SizedBox(height: 6),
        InkWell(
          onTap: _submitting ? null : _pickJoinDate,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppThemeColors.darkCanvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 16, color: _subtle),
                const SizedBox(width: 10),
                Text(
                  DateFormat('dd MMM yyyy').format(_joinDate),
                  style: const TextStyle(
                    color: _label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildManagerDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Reports to', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: _loadingManagers
              ? const SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 10),
                      Text('Loading managers…',
                          style: TextStyle(color: _subtle)),
                    ],
                  ),
                )
              : _managerOptions.isEmpty
                  ? SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _managerError ?? 'No eligible managers found',
                          style: TextStyle(
                            color: _managerError != null
                                ? Colors.orangeAccent
                                : _subtle,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        isDense: true,
                        dropdownColor: AppThemeColors.darkSurface,
                        value: _selectedManagerName,
                        hint: const Text('Select reporting manager',
                            style: TextStyle(color: _subtle)),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: _subtle),
                        itemHeight: 60,
                        items: _managerOptions
                            .map((m) => DropdownMenuItem<String>(
                                  value: m.name,
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: m.name,
                                          style: const TextStyle(
                                              color: _label,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        if (m.roleName != null &&
                                            m.roleName!.isNotEmpty)
                                          TextSpan(
                                            text: '   ${m.roleName}',
                                            style: const TextStyle(
                                                color: _subtle, fontSize: 12),
                                          ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: _submitting
                            ? null
                            : (v) {
                                final selected = _managerOptions.firstWhere(
                                  (o) => o.name == v,
                                  orElse: () => const _ManagerOption(name: ''),
                                );
                                setState(() {
                                  _selectedManagerName = v;
                                  _selectedManagerUserId = selected.userId;
                                });
                              },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildAccessToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_open_rounded, size: 18, color: _subtle),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Grant access',
                    style: TextStyle(
                        color: _label,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                SizedBox(height: 2),
                Text(
                  'Turn off to onboard without enabling login yet.',
                  style: TextStyle(color: _subtle, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isActive,
            activeTrackColor: _accent,
            onChanged:
                _submitting ? null : (v) => setState(() => _isActive = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withValues(alpha: 0.15)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _accent, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'When access is enabled, a login account is created with this '
              'email and password. The user can change the password later '
              'using Forgot Password with the registered email.',
              style: TextStyle(color: _label, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Login password', required: _isActive),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          style: const TextStyle(color: _label, fontSize: 14),
          decoration: _inputDecoration('Temporary password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: _subtle,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) {
            if (!_isActive) return null;
            if (value == null || value.trim().isEmpty) {
              return 'Login password is required';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
                color: _label, fontWeight: FontWeight.w700, fontSize: 13)),
        if (required)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('*', style: TextStyle(color: Colors.redAccent)),
          ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _subtle, fontSize: 13),
      filled: true,
      fillColor: AppThemeColors.darkCanvas,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  Widget _buildBloodGroupDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Blood Group', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppThemeColors.darkSurface,
              value: _selectedBloodGroup,
              hint: const Text(
                'Select blood group',
                style: TextStyle(color: _subtle, fontSize: 13),
              ),
              icon:
                  const Icon(Icons.keyboard_arrow_down_rounded, color: _subtle),
              items: const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                  .map((bg) => DropdownMenuItem<String>(
                        value: bg,
                        child: Text(
                          bg,
                          style: const TextStyle(
                              color: _label, fontWeight: FontWeight.w600),
                        ),
                      ))
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _selectedBloodGroup = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGenderDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Gender', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              dropdownColor: AppThemeColors.darkSurface,
              value: _selectedGender,
              hint: const Text(
                'Select gender',
                style: TextStyle(color: _subtle, fontSize: 13),
              ),
              icon:
                  const Icon(Icons.keyboard_arrow_down_rounded, color: _subtle),
              items: const ['Male', 'Female', 'Other']
                  .map((g) => DropdownMenuItem<String>(
                        value: g,
                        child: Text(
                          g,
                          style: const TextStyle(
                              color: _label, fontWeight: FontWeight.w600),
                        ),
                      ))
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (v) => setState(() => _selectedGender = v),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDOB() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(1995),
      firstDate: DateTime(1940),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 15)),
    );
    if (picked != null) {
      setState(() => _dob = picked);
    }
  }

  Widget _buildDOBPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Date of Birth', required: true),
        const SizedBox(height: 6),
        InkWell(
          onTap: _submitting ? null : _pickDOB,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppThemeColors.darkCanvas,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 16, color: _subtle),
                const SizedBox(width: 10),
                Text(
                  _dob == null
                      ? 'Select Date of Birth'
                      : DateFormat('dd MMM yyyy').format(_dob!),
                  style: TextStyle(
                    color: _dob == null ? _subtle : _label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ManagerOption {
  final String name;
  final String email;
  final String? roleName;
  final String? userId;

  const _ManagerOption({
    required this.name,
    this.email = '',
    this.roleName,
    this.userId,
  });
}
