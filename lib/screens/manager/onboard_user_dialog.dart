import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/company.dart';
import '../../models/staff.dart';
import '../../providers/auth_session_provider.dart';
import '../../services/manager_account_service.dart';
import '../../services/email_service.dart';
import '../../services/notification_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/country_options.dart';
import '../../utils/departments.dart';
import '../../utils/profile_photo_picker.dart';

// Fixed-brand palette for the onboard-user dialog (force-dark). Intentional
// exception: file-scoped brand constants.
const Color _ouPrimary = Color(0xFF0F766E);
const Color _ouWhite = Color(0xFFFFFFFF);
const Color _ouGreen600 = Color(0xFF43A047);
const Color _ouRed600 = Color(0xFFE53935);
const Color _ouRedAccent = Color(0xFFFF5252);
const Color _ouOrange = Color(0xFFFF9800);

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

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
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

  _OnboardTarget _target = _OnboardTarget.engineer;
  String? _selectedDepartment;

  String? _selectedManagerName;
  List<_ManagerOption> _managerOptions = const [];
  bool _loadingManagers = true;

  String? _selectedCompanyId;
  List<Company> _companies = const [];
  bool _loadingCompanies = true;

  bool get _canAssignManager =>
      widget.onboarderRole == AppUserRole.companyAdmin ||
      widget.onboarderRole == AppUserRole.superAdmin;

  static const _accent = _ouPrimary;
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
    _loadCompanies();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _employeeIdCtrl.dispose();
    _positionCtrl.dispose();
    _salaryCtrl.dispose();
    _passwordCtrl.dispose();
    _maxStaffCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadManagers() async {
    try {
      final snap = await FirebaseContextProvider.current.firestore
          .collection('managers')
          .get();
      final options = <_ManagerOption>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim();
        final email = (data['email'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        options.add(_ManagerOption(
          name: name,
          email: email,
          companyId: data['companyId'] as String?,
        ));
      }

      final hasCurrent = options.any(
          (o) => o.name.toLowerCase() == _selectedManagerName?.toLowerCase());
      if (!hasCurrent && _selectedManagerName != null) {
        options.insert(
          0,
          _ManagerOption(
            name: _selectedManagerName!,
            email: widget.currentManagerEmail,
          ),
        );
      }

      options
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (!mounted) return;
      setState(() {
        _managerOptions = options;
        _loadingManagers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingManagers = false);
    }
  }

  Future<void> _loadCompanies() async {
    try {
      final snap = await FirebaseContextProvider.current.firestore
          .collection('companies')
          .get();
      final companies = <Company>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        companies.add(Company(
          id: doc.id,
          name: name,
          isActive: data['isActive'] as bool? ?? true,
        ));
      }
      companies
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _companies = companies;
        _loadingCompanies = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCompanies = false);
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

  /// Resolves the tenant/company this user belongs to: first from the signed-in
  /// user's `users` doc, falling back to the reporting manager's company.
  Future<String?> _resolveCompanyId() async {
    try {
      final user = FirebaseContextProvider.current.auth.currentUser;
      if (user != null) {
        final doc = await FirebaseContextProvider.current.firestore
            .collection('users')
            .doc(user.uid)
            .get();
        final companyId = doc.data()?['companyId'] as String?;
        if (companyId != null && companyId.trim().isNotEmpty) {
          return companyId.trim();
        }
      }
    } catch (_) {}
    if (_target == _OnboardTarget.engineer &&
        _selectedManagerName != null &&
        _selectedManagerName!.trim().isNotEmpty) {
      try {
        final snap = await FirebaseContextProvider.current.firestore
            .collection('managers')
            .where('name', isEqualTo: _selectedManagerName!.trim())
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final companyId = snap.docs.first.data()['companyId'] as String?;
          if (companyId != null && companyId.trim().isNotEmpty) {
            return companyId.trim();
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final isEmployeeOnboard = _target != _OnboardTarget.companyAdmin;
    if (_target == _OnboardTarget.manager && !_canAssignManager) {
      _showError('Only admins can onboard a manager.');
      return;
    }
    if (_target == _OnboardTarget.companyAdmin &&
        widget.onboarderRole != AppUserRole.superAdmin) {
      _showError('Only the Super Admin can onboard a company admin.');
      return;
    }
    if (_target == _OnboardTarget.engineer &&
        (_selectedManagerName == null || _selectedManagerName!.isEmpty)) {
      _showError('Please select a reporting manager.');
      return;
    }
    if (_target == _OnboardTarget.companyAdmin &&
        (_selectedCompanyId == null || _selectedCompanyId!.isEmpty)) {
      _showError('Please select the company this admin belongs to.');
      return;
    }
    if (isEmployeeOnboard && _selectedDepartment == null) {
      _showError('Please select a designation.');
      return;
    }
    if (_isActive && _passwordCtrl.text.trim().isEmpty) {
      _showError('Enter a password to create the login account.');
      return;
    }

    if (isEmployeeOnboard) {
      // Demographic validators
      if (_selectedBloodGroup == null) {
        _showError('Please select a blood group.');
        return;
      }
      if (_selectedGender == null) {
        _showError('Please select a gender.');
        return;
      }
      if (_selectedNationality == null ||
          _selectedNationality!.trim().isEmpty) {
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
    }

    setState(() => _submitting = true);
    final email = _emailCtrl.text.trim().toLowerCase();
    final name = _nameCtrl.text.trim();
    final department = _selectedDepartment ?? '';
    final password = _passwordCtrl.text.trim();
    final phone = '$_selectedDialCode ${_phoneCtrl.text.trim()}'.trim();
    final nationality = _selectedNationality ?? '';
    final salary = _parseSalary();
    var emailSent = false;
    String? emailError;

    try {
      if (_target == _OnboardTarget.companyAdmin) {
        await _managerAccountService.createCompanyAdminAccount(
          name: name,
          email: email,
          phone: phone,
          password: password,
          companyId: _selectedCompanyId!,
        );
      } else {
        final companyId = await _resolveCompanyId();
        if (_target == _OnboardTarget.engineer) {
          final emailTaken = await _staffService.isEmailAlreadyUsed(email);
          if (emailTaken) {
            _showError('An engineer with this email already exists.');
            setState(() => _submitting = false);
            return;
          }

          final staff = Staff(
            id: '',
            name: name,
            email: email,
            phone: phone,
            department: department,
            position: _positionCtrl.text.trim(),
            employeeId: _employeeIdCtrl.text.trim(),
            joinDate: _joinDate,
            reportsTo: _selectedManagerName,
            salary: salary,
            isActive: _isActive,
            password: _isActive ? password : null,
            hasRegistered: _isActive,
            photoUrl: _photoUrl,
            bloodGroup: _selectedBloodGroup,
            gender: _selectedGender,
            nationality: nationality,
            dob: _dob,
            address: _addressCtrl.text.trim(),
            companyId: companyId,
          );

          await _staffService.addStaff(staff);
        } else {
          final managers =
              FirebaseContextProvider.current.firestore.collection('managers');
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
              position: _positionCtrl.text.trim(),
              staffCount: 0,
              maxStaff: int.tryParse(_maxStaffCtrl.text.trim()) ?? 20,
              joinDate: _joinDate,
              status: 'active',
              salary: salary,
              photoUrl: _photoUrl,
              bloodGroup: _selectedBloodGroup,
              gender: _selectedGender,
              nationality: nationality,
              dob: _dob,
              address: _addressCtrl.text.trim(),
              companyId: companyId,
            );
          } else {
            await managers.add({
              'name': name,
              'email': email,
              'phone': phone,
              'employeeId': _employeeIdCtrl.text.trim(),
              'department': department,
              'position': _positionCtrl.text.trim(),
              'joinDate': Timestamp.fromDate(_joinDate),
              'status': 'inactive',
              'salary': salary,
              'photoUrl': _photoUrl,
              'staffCount': 0,
              'maxStaff': int.tryParse(_maxStaffCtrl.text.trim()) ?? 20,
              'hasRegistered': false,
              'companyId': companyId,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'bloodGroup': _selectedBloodGroup,
              'gender': _selectedGender,
              'nationality': nationality,
              'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
              'address': _addressCtrl.text.trim(),
            });
          }
        }
      }

      if (_isActive) {
        try {
          await EmailService.sendAccountCredentials(
            recipientEmail: email,
            password: password,
            roleLabel:
                _target == _OnboardTarget.manager ? 'manager' : 'employee',
            recipientName: name,
          );
          emailSent = true;

          if (_target == _OnboardTarget.companyAdmin) {
            // Company admins get the security notice push as well.
            await NotificationService().sendNotificationToUser(
              identifier: email,
              title: 'Welcome to TRAKR!',
              body:
                  'Your login credentials: User ID: $email and Temporary Password: $password. Please log in and change your password.',
            );
          } else {
            // Send credentials push notification to the employee
            await NotificationService().sendNotificationToUser(
              identifier: email,
              title: 'Welcome to the Team!',
              body:
                  'Your login credentials: User ID: $email and Temporary Password: $password. Please log in and change your password.',
            );
          }

          // Save credentials notification in Firestore
          await FirebaseContextProvider.current.firestore
              .collection('notifications')
              .add({
            'recipient': email,
            'type': 'Email',
            'content':
                'Welcome! Your login credentials: User ID: $email, Password: $password.',
            'status': 'Sent',
            'suppressFirestorePush': true,
            'allowFirestorePush': false,
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
          await FirebaseContextProvider.current.firestore
              .collection('notifications')
              .add({
            'recipient': email,
            'type': 'Security',
            'content':
                'Important: Please change your temporary password for security purposes.',
            'status': 'Sent',
            'suppressFirestorePush': true,
            'allowFirestorePush': false,
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
          backgroundColor: emailError == null ? _ouGreen600 : _ouOrange,
          content: Text(
            !_isActive
                ? 'Onboarded $name. Login access is disabled.'
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
        backgroundColor: _ouRed600,
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
                        _target == _OnboardTarget.companyAdmin
                            ? _buildCompanyDropdown()
                            : _field(
                                controller: _employeeIdCtrl,
                                label: 'Employee ID',
                                hint: 'EMP-1024',
                                required: true,
                              ),
                      ),
                      if (_target != _OnboardTarget.companyAdmin) ...[
                        const SizedBox(height: 14),
                        _twoCol(
                          _buildDepartmentDropdown(),
                          _field(
                            controller: _positionCtrl,
                            label: 'Position',
                            hint: 'Software Engineer',
                            required: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _field(
                          controller: _salaryCtrl,
                          label: 'Salary',
                          hint: '50000',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: _salaryValidator,
                        ),
                        const SizedBox(height: 14),
                        _target == _OnboardTarget.manager
                            ? _twoCol(
                                _buildJoinDate(),
                                _field(
                                  controller: _maxStaffCtrl,
                                  label: 'Max Employees',
                                  hint: '20',
                                  required: true,
                                  keyboardType: TextInputType.number,
                                ),
                              )
                            : _twoCol(
                                _buildJoinDate(),
                                _buildManagerDropdown(),
                              ),
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
                      ],
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
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: _subtle),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
                      color: _ouWhite,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: Text(_submitting ? 'Onboarding…' : 'Onboard user'),
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

  Widget _buildRoleChooser() {
    final options = _roleOptions();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Assign role', required: true),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            final itemWidth =
                c.maxWidth < 600 ? c.maxWidth : (c.maxWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final option in options)
                  SizedBox(
                    width: itemWidth,
                    child: _RoleTile(
                      title: option.title,
                      subtitle: option.subtitle,
                      icon: option.icon,
                      selected: _target == option.target,
                      enabled: !_submitting && option.allowed,
                      onTap: () => setState(() {
                        _target = option.target;
                        if (option.target == _OnboardTarget.companyAdmin) {
                          _isActive = true;
                        }
                      }),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<_RoleOption> _roleOptions() {
    return [
      const _RoleOption(
        title: 'Engineer',
        subtitle: 'Reports to a manager. Scans QR for attendance.',
        icon: Icons.engineering_rounded,
        target: _OnboardTarget.engineer,
        allowed: true,
      ),
      _RoleOption(
        title: 'Manager',
        subtitle: _canAssignManager
            ? 'Manages a team of engineers.'
            : 'Only admins can onboard managers.',
        icon: Icons.supervisor_account_rounded,
        target: _OnboardTarget.manager,
        allowed: _canAssignManager,
      ),
      _RoleOption(
        title: 'Company Admin',
        subtitle: widget.onboarderRole == AppUserRole.superAdmin
            ? 'Manages a company and its users.'
            : 'Only the Super Admin can onboard company admins.',
        icon: Icons.apartment_rounded,
        target: _OnboardTarget.companyAdmin,
        allowed: widget.onboarderRole == AppUserRole.superAdmin,
      ),
    ];
  }

  Widget _buildCompanyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Company', required: true),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppThemeColors.darkCanvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: _loadingCompanies
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
                      Text('Loading companies…',
                          style: TextStyle(color: _subtle)),
                    ],
                  ),
                )
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: AppThemeColors.darkSurface,
                    value: _selectedCompanyId,
                    hint: const Text('Select company',
                        style: TextStyle(color: _subtle)),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _subtle),
                    items: _companies
                        .map((c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Row(
                                children: [
                                  const Icon(Icons.apartment_rounded,
                                      size: 16, color: _subtle),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      c.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _label,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _selectedCompanyId = v),
                  ),
                ),
        ),
      ],
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
                color: _ouRedAccent,
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

  double? _parseSalary() {
    final raw = _salaryCtrl.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String? _salaryValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final salary = double.tryParse(raw);
    if (salary == null) return 'Enter a valid salary';
    if (salary < 0) return 'Salary cannot be negative';
    return null;
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
              : DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    dropdownColor: AppThemeColors.darkSurface,
                    value: _selectedManagerName,
                    hint: const Text('Select reporting manager',
                        style: TextStyle(color: _subtle)),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _subtle),
                    items: _managerOptions
                        .map((m) => DropdownMenuItem<String>(
                              value: m.name,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(m.name,
                                      style: const TextStyle(
                                          color: _label,
                                          fontWeight: FontWeight.w600)),
                                  if (m.email.isNotEmpty)
                                    Text(m.email,
                                        style: const TextStyle(
                                            color: _subtle, fontSize: 11)),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _selectedManagerName = v),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildAccessToggle() {
    final isCompanyAdmin = _target == _OnboardTarget.companyAdmin;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCompanyAdmin ? 'Login access required' : 'Grant access',
                  style: const TextStyle(
                      color: _label, fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  isCompanyAdmin
                      ? 'Company admins always get a login account.'
                      : 'Turn off to onboard without enabling login yet.',
                  style: const TextStyle(color: _subtle, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _isActive,
            activeTrackColor: _accent,
            onChanged: _submitting || isCompanyAdmin
                ? null
                : (v) => setState(() => _isActive = v),
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
            child: Text('*', style: TextStyle(color: _ouRedAccent)),
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
  final String? companyId;

  const _ManagerOption({
    required this.name,
    required this.email,
    this.companyId,
  });
}

enum _OnboardTarget { engineer, manager, companyAdmin }

class _RoleOption {
  final String title;
  final String subtitle;
  final IconData icon;
  final _OnboardTarget target;
  final bool allowed;

  const _RoleOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.target,
    required this.allowed,
  });
}

class _RoleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  static const _accent = _ouPrimary;
  static const _border = AppThemeColors.darkBorder;
  static const _label = AppThemeColors.darkText;
  static const _subtle = AppThemeColors.darkMuted;

  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeBorder = selected ? _accent : _border;
    final activeBg =
        selected ? _accent.withValues(alpha: 0.16) : AppThemeColors.darkCanvas;
    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: activeBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: activeBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected ? _accent : AppThemeColors.darkCanvas,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected ? _ouWhite : _subtle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: _label,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle_rounded,
                              size: 14, color: _accent),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: _subtle, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
