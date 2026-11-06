import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _scrollCtrl = ScrollController();

  /// Every validated field owns a key, declared here in the same order they
  /// appear on screen. After a failed submit we walk this list to find the
  /// first field that actually failed and scroll it into view — the dialog is
  /// taller than the viewport, so without this the user is told "fix the
  /// highlighted fields" while every highlight is off-screen.
  final _roleKey = GlobalKey<FormFieldState<Object?>>();
  final _nameKey = GlobalKey<FormFieldState<String>>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  final _phoneKey = GlobalKey<FormFieldState<String>>();
  final _employeeIdKey = GlobalKey<FormFieldState<String>>();
  final _designationKey = GlobalKey<FormFieldState<Object?>>();
  final _managerKey = GlobalKey<FormFieldState<Object?>>();
  final _maxStaffKey = GlobalKey<FormFieldState<String>>();
  final _bloodGroupKey = GlobalKey<FormFieldState<Object?>>();
  final _genderKey = GlobalKey<FormFieldState<Object?>>();
  final _nationalityKey = GlobalKey<FormFieldState<Object?>>();
  final _dobKey = GlobalKey<FormFieldState<String>>();
  final _addressKey = GlobalKey<FormFieldState<String>>();
  final _passwordKey = GlobalKey<FormFieldState<String>>();

  List<GlobalKey<FormFieldState<dynamic>>> get _fieldsInOrder => [
        _roleKey,
        _nameKey,
        _emailKey,
        _phoneKey,
        _employeeIdKey,
        _designationKey,
        _managerKey,
        _maxStaffKey,
        _bloodGroupKey,
        _genderKey,
        _nationalityKey,
        _dobKey,
        _addressKey,
        _passwordKey,
      ];

  /// Submission failure shown as a persistent in-dialog banner. A SnackBar is
  /// the wrong surface for this: it is clipped behind the dialog, auto-hides
  /// after four seconds, and these messages (duplicate email, unreachable
  /// identity service) are long and need to be read and acted on.
  String? _submitError;

  /// Server-detected clashes, rendered inline on the offending field so the
  /// admin can see which value to change rather than reading it in a toast.
  String? _emailConflict;
  String? _employeeIdConflict;

  /// Set once the user presses "Onboard user", so validation errors then
  /// update live as fields are corrected instead of only on the next submit.
  bool _submitAttempted = false;

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
  final _dobCtrl = TextEditingController();
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
  static const _errorColor = Color(0xFFEF5350);

  @override
  void initState() {
    super.initState();
    _selectedManagerName = widget.currentManagerName.trim().isEmpty
        ? null
        : widget.currentManagerName.trim();
    // Keeps the avatar placeholder initial in step with the typed name.
    _nameCtrl.addListener(_onNameChanged);
    // A clash is about the value that was submitted; as soon as the admin
    // edits that value the stale error must go.
    _emailCtrl.addListener(() {
      if (_emailConflict != null) setState(() => _emailConflict = null);
    });
    _employeeIdCtrl.addListener(() {
      if (_employeeIdConflict != null) {
        setState(() => _employeeIdConflict = null);
      }
    });
    _loadManagers();
  }

  void _onNameChanged() {
    final initial =
        _nameCtrl.text.trim().isEmpty ? '' : _nameCtrl.text.trim()[0];
    if (initial != _avatarInitial) {
      setState(() => _avatarInitial = initial);
    }
  }

  String _avatarInitial = '';

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _scrollCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _employeeIdCtrl.dispose();
    _passwordCtrl.dispose();
    _maxStaffCtrl.dispose();
    _dobCtrl.dispose();
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

  Future<String?> _resolveCompanyId() async {
    try {
      final user = FirebaseContextProvider.current.auth.currentUser;
      if (user == null) return null;
      final doc = await FirebaseContextProvider.current.firestore
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return null;
      final companyId = doc.data()?['companyId'] as String?;
      if (companyId != null &&
          companyId.trim().isNotEmpty &&
          companyId.trim() != '[DEFAULT]') {
        return companyId.trim();
      }
    } catch (_) {}
    final appName = FirebaseContextProvider.current.app.name;
    return (appName.isNotEmpty && appName != '[DEFAULT]') ? appName : null;
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

  /// Scrolls the first field that failed validation into view and focuses it.
  /// Without this the dialog can report errors that are entirely off-screen.
  void _scrollToFirstError() {
    for (final key in _fieldsInOrder) {
      final state = key.currentState;
      if (state == null || !state.hasError) continue;
      final ctx = key.currentContext;
      if (ctx == null) continue;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
      return;
    }
  }

  /// Shows a submission failure in the in-dialog banner.
  ///
  /// [revealBanner] scrolls the banner into view. Pass `false` when the error
  /// is also rendered inline on a specific field — there the field is the
  /// more useful thing to scroll to, and two competing scroll animations
  /// would fight each other.
  void _setSubmitError(String message, {bool revealBanner = true}) {
    if (!mounted) return;
    setState(() {
      _submitError = message;
      _submitting = false;
    });
    if (!revealBanner) return;
    // After the frame: inserting the banner changes the scroll extent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  /// Looks for an email or employee-ID clash across BOTH directories before
  /// anything is written.
  ///
  /// Previously a duplicate email only surfaced after Firebase Auth rejected
  /// the account creation — by which point the master login-index entry had
  /// already been written — and a duplicate employee ID was never checked at
  /// all. That second one matters: attendance is keyed by
  /// `attendance_<employeeId>_<date>`, so two people sharing an employee ID
  /// overwrite each other's check-in.
  Future<_FieldConflict?> _findConflict({
    required String email,
    required String employeeId,
  }) async {
    final db = FirebaseContextProvider.current.firestore;
    for (final collection in const ['staff', 'managers']) {
      final byEmail = await db
          .collection(collection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        final who = (byEmail.docs.first.data()['name'] as String? ?? '').trim();
        return _FieldConflict(
          isEmail: true,
          message: who.isEmpty
              ? 'This email is already registered in the directory.'
              : '$who already uses this email address.',
        );
      }
      if (employeeId.isNotEmpty) {
        final byId = await db
            .collection(collection)
            .where('employeeId', isEqualTo: employeeId)
            .limit(1)
            .get();
        if (byId.docs.isNotEmpty) {
          final who = (byId.docs.first.data()['name'] as String? ?? '').trim();
          return _FieldConflict(
            isEmail: false,
            message: who.isEmpty
                ? 'Employee ID "$employeeId" is already in use.'
                : 'Employee ID "$employeeId" already belongs to $who.',
          );
        }
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;

    setState(() {
      _submitAttempted = true;
      _submitError = null;
      _emailConflict = null;
      _employeeIdConflict = null;
    });

    // ONE validation pass. Every field renders its own error inline, so the
    // user sees everything that needs fixing at once. This replaces a chain
    // of eleven sequential checks that each popped a single red SnackBar —
    // fix one, submit, get the next — while the offending field itself was
    // never highlighted and was often scrolled out of view.
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _submitError =
          'Some required details are missing. The fields needing attention '
          'are highlighted below.');
      // After the frame: the banner has just been inserted above the form, so
      // every field below it has moved.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToFirstError());
      return;
    }

    final selectedRole = _selectedUserRole;
    if (selectedRole == null) {
      _setSubmitError('Please select a role.');
      return;
    }
    // Domain-level guard: protected/system roles (Company Admin) can never be
    // assigned through onboarding, even if a crafted request bypasses the UI.
    if (selectedRole.isSystem ||
        selectedRole.id.trim().toLowerCase() == 'company_admin') {
      _setSubmitError(
          'The Company Admin role is system-protected and cannot be assigned '
          'during onboarding.');
      return;
    }
    if (_assignedRole == AppUserRole.manager && !_canAssignManager) {
      _setSubmitError('Only admins can onboard a manager.');
      return;
    }
    _dob ??= _parseDOB(_dobCtrl.text.trim());

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
      final conflict = await _findConflict(
        email: email,
        employeeId: _employeeIdCtrl.text.trim(),
      );
      if (conflict != null) {
        if (!mounted) return;
        setState(() {
          if (conflict.isEmail) {
            _emailConflict = conflict.message;
          } else {
            _employeeIdConflict = conflict.message;
          }
        });
        _formKey.currentState?.validate();
        _setSubmitError(conflict.message, revealBanner: false);
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToFirstError());
        return;
      }

      final resolvedCompanyId = await _resolveCompanyId();

      if (_assignedRole == AppUserRole.employee) {
        final staff = Staff(
          id: '',
          name: name,
          email: email,
          companyId: resolvedCompanyId,
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
        final managers =
            FirebaseContextProvider.current.firestore.collection('managers');
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
            companyId: resolvedCompanyId,
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
            'companyId': resolvedCompanyId,
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
      // Resolve the messenger BEFORE popping: afterwards this dialog's
      // context is on its way out of the tree.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);

      final credentialsUndelivered = _isActive && !emailSent;
      messenger.showSnackBar(
        SnackBar(
          backgroundColor:
              credentialsUndelivered ? Colors.orange.shade800 : Colors.green.shade600,
          // A failed credential email needs to be read and acted on, so it
          // stays up with an explicit dismiss instead of vanishing in four
          // seconds like the success case.
          duration: credentialsUndelivered
              ? const Duration(seconds: 12)
              : const Duration(seconds: 4),
          action: credentialsUndelivered
              ? SnackBarAction(
                  label: 'Copy password',
                  textColor: Colors.white,
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: password)),
                )
              : null,
          content: Text(
            !_isActive
                ? 'Onboarded $name as ${selectedRole.name}. Login access is disabled.'
                : emailSent
                    ? '$name can now sign in as ${selectedRole.name} — credentials sent to $email.'
                    : 'Account created for $email, but the credentials email '
                        'failed to send. Share the password manually. '
                        '($emailError)',
          ),
        ),
      );
    } catch (e) {
      // Persistent, in-dialog, and scrolled into view — these messages can be
      // several lines long and tell the admin exactly what to do next.
      _setSubmitError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// True once the admin has entered anything worth losing. This form is
  /// long (fourteen required inputs); closing it by accident used to discard
  /// all of it silently.
  bool get _isDirty =>
      _nameCtrl.text.trim().isNotEmpty ||
      _emailCtrl.text.trim().isNotEmpty ||
      _phoneCtrl.text.trim().isNotEmpty ||
      _employeeIdCtrl.text.trim().isNotEmpty ||
      _passwordCtrl.text.trim().isNotEmpty ||
      _addressCtrl.text.trim().isNotEmpty ||
      _dobCtrl.text.trim().isNotEmpty ||
      _photoUrl != null ||
      _selectedDepartment != null ||
      _selectedBloodGroup != null ||
      _selectedGender != null ||
      _selectedNationality != null;

  Future<void> _handleClose() async {
    if (_submitting) return;
    if (!_isDirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: const Text(
          'Discard this draft?',
          style: TextStyle(color: _label, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'The details you have entered for this user will be lost.',
          style: TextStyle(color: _subtle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(foregroundColor: _subtle),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _errorColor),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.of(context).pop();
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

    return PopScope(
      // Esc and system-back are close affordances too — they must not bypass
      // the discard confirmation or interrupt an in-flight submission.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleClose();
      },
      child: Dialog(
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
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Form(
                  key: _formKey,
                  // Before the first submit the form stays quiet; afterwards
                  // each field re-validates as it is corrected, so errors
                  // clear the moment they are fixed instead of persisting
                  // until the next submit.
                  autovalidateMode: _submitAttempted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_submitError != null) ...[
                        _buildErrorBanner(_submitError!),
                        const SizedBox(height: 14),
                      ],
                      _buildRoleChooser(),
                      const SizedBox(height: 14),
                      _buildPhotoPicker(),
                      const SizedBox(height: 14),
                      _twoCol(
                        _field(
                          fieldKey: _nameKey,
                          controller: _nameCtrl,
                          label: 'Full name',
                          hint: 'Jane Doe',
                          required: true,
                          autofocus: true,
                        ),
                        _field(
                          fieldKey: _emailKey,
                          controller: _emailCtrl,
                          label: 'Email',
                          hint: 'jane@company.com',
                          required: true,
                          keyboardType: TextInputType.emailAddress,
                          helperText: 'Used as the login ID.',
                          validator: (value) {
                            // A clash found server-side is shown on the field
                            // that owns it, not in a toast.
                            if (_emailConflict != null) return _emailConflict;
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) return 'Email is required';
                            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(v)) {
                              return 'Enter a valid email, e.g. jane@company.com';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      _twoCol(
                        _buildPhoneField(),
                        _field(
                          fieldKey: _employeeIdKey,
                          controller: _employeeIdCtrl,
                          label: 'Employee ID',
                          hint: 'EMP-1024',
                          required: true,
                          helperText: 'Must be unique — attendance is keyed '
                              'to this ID.',
                          validator: (value) {
                            if (_employeeIdConflict != null) {
                              return _employeeIdConflict;
                            }
                            if ((value?.trim() ?? '').isEmpty) {
                              return 'Employee ID is required';
                            }
                            return null;
                          },
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
                            fieldKey: _maxStaffKey,
                            controller: _maxStaffCtrl,
                            label: 'Max Employees',
                            hint: '20',
                            required: true,
                            keyboardType: TextInputType.number,
                            validator: (value) {
                              final v = value?.trim() ?? '';
                              if (v.isEmpty) return 'Max Employees is required';
                              final n = int.tryParse(v);
                              if (n == null) return 'Enter a whole number';
                              if (n < 1) return 'Must be at least 1';
                              return null;
                            },
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
                        fieldKey: _addressKey,
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
            tooltip: 'Close',
            onPressed: _submitting ? null : _handleClose,
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
                    onPressed: _submitting ? null : _handleClose,
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
    return _dropdownFormField(
      fieldKey: _designationKey,
      label: 'Designation',
      hint: 'Select designation',
      value: _selectedDepartment,
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
      onChanged: (v) => setState(() => _selectedDepartment = v),
      validate: () =>
          _selectedDepartment == null ? 'Choose a designation' : null,
    );
  }

  Widget _buildPhoneField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Phone', required: true),
        const SizedBox(height: 6),
        TextFormField(
          key: _phoneKey,
          controller: _phoneCtrl,
          enabled: !_submitting,
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
    return _dropdownFormField(
      fieldKey: _nationalityKey,
      label: 'Nationality',
      hint: 'Select nationality',
      value: _selectedNationality,
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
      onChanged: (v) => setState(() => _selectedNationality = v),
      validate: () => (_selectedNationality == null ||
              _selectedNationality!.trim().isEmpty)
          ? 'Choose a nationality'
          : null,
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

        return FormField<Object?>(
          key: _roleKey,
          validator: (_) {
            if (_selectedUserRole == null) return 'Select a role to assign';
            if (_assignedRole == AppUserRole.manager && !_canAssignManager) {
              return 'Only admins can onboard a manager';
            }
            return null;
          },
          builder: (roleState) => Column(
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
                              roleState.didChange(id);
                              _roleKey.currentState?.validate();
                              // Switching between an employee and a
                              // managerial role swaps which fields apply, so
                              // drop stale errors from the hidden ones.
                              _managerKey.currentState?.validate();
                              _maxStaffKey.currentState?.validate();
                            }
                          },
                  ),
                ),
              ),
            if (roleState.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  roleState.errorText!,
                  style: const TextStyle(color: _errorColor, fontSize: 12),
                ),
              )
            else if (_selectedUserRole?.isManagerial ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Manages a team of engineers.'
                  '${_canAssignManager ? '' : ' Only admins can onboard managers.'}',
                  style: const TextStyle(color: _subtle, fontSize: 11),
                ),
              ),
          ],
          ),
        );
      },
    );
  }

  Widget _buildPhotoPicker() {
    final image = _profileImageProvider();
    final initial = _avatarInitial.isNotEmpty ? _avatarInitial : 'U';

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
    GlobalKey<FormFieldState<String>>? fieldKey,
    bool required = false,
    TextInputType? keyboardType,
    bool obscureText = false,
    int? maxLines = 1,
    bool autofocus = false,
    TextInputAction textInputAction = TextInputAction.next,
    String? helperText,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label, required: required),
        const SizedBox(height: 6),
        TextFormField(
          key: fieldKey,
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: maxLines,
          autofocus: autofocus,
          enabled: !_submitting,
          // Lets the admin tab/Enter straight down the form instead of
          // reaching for the mouse between every field.
          textInputAction: maxLines == 1 ? textInputAction : null,
          style: const TextStyle(color: _label, fontSize: 14),
          cursorColor: _accent,
          decoration: _inputDecoration(hint, helperText: helperText),
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
    // While the list is still loading, or when the tenant genuinely has no
    // eligible manager, the dropdown is swapped for an explanatory row — and
    // the retry affordance means a transient load failure is recoverable
    // without closing and losing the whole form.
    Widget? replacement;
    if (_loadingManagers) {
      replacement = const SizedBox(
        height: 48,
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text('Loading managers…', style: TextStyle(color: _subtle)),
          ],
        ),
      );
    } else if (_managerOptions.isEmpty) {
      replacement = SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _managerError ??
                    'No eligible managers yet — mark a role as a reporting '
                        'manager in Roles & Permissions.',
                style: TextStyle(
                  color: _managerError != null
                      ? Colors.orangeAccent
                      : _subtle,
                  fontSize: 12,
                ),
              ),
            ),
            if (_managerError != null)
              TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() => _loadingManagers = true);
                        _loadManagers();
                      },
                style: TextButton.styleFrom(foregroundColor: _accent),
                child: const Text('Retry'),
              ),
          ],
        ),
      );
    }

    return _dropdownFormField(
      fieldKey: _managerKey,
      label: 'Reports to',
      hint: 'Select reporting manager',
      value: _selectedManagerName,
      itemHeight: 60,
      replacement: replacement,
      items: _managerOptions
          .map((m) => DropdownMenuItem<String>(
                value: m.name,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: m.name,
                        style: const TextStyle(
                            color: _label, fontWeight: FontWeight.w600),
                      ),
                      if (m.roleName != null && m.roleName!.isNotEmpty)
                        TextSpan(
                          text: '   ${m.roleName}',
                          style: const TextStyle(color: _subtle, fontSize: 12),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: (v) {
        final selected = _managerOptions.firstWhere(
          (o) => o.name == v,
          orElse: () => const _ManagerOption(name: ''),
        );
        setState(() {
          _selectedManagerName = v;
          _selectedManagerUserId = selected.userId;
        });
      },
      validate: () {
        if (_assignedRole != AppUserRole.employee) return null;
        if (_loadingManagers) return 'Still loading managers — one moment.';
        if (_selectedManagerName == null || _selectedManagerName!.isEmpty) {
          return 'Choose who this person reports to';
        }
        return null;
      },
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

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
      decoration: BoxDecoration(
        color: _errorColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _errorColor.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: _errorColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              message,
              style: const TextStyle(
                color: _label,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 16, color: _subtle),
            onPressed: () => setState(() => _submitError = null),
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

  /// Builds a readable but strong temporary password. Firebase rejects
  /// anything under six characters, and the admin otherwise has to invent one
  /// on the spot — which in practice means a weak, reused password.
  String _generateTemporaryPassword() {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O — easy to misread
    const lower = 'abcdefghijkmnopqrstuvwxyz'; // no l
    const digits = '23456789'; // no 0/1
    const symbols = '@#\$%&*';
    final rng = Random.secure();
    String pick(String pool) => pool[rng.nextInt(pool.length)];
    final chars = <String>[
      pick(upper),
      pick(lower),
      pick(digits),
      pick(symbols),
      for (var i = 0; i < 6; i++) pick('$upper$lower$digits'),
    ]..shuffle(rng);
    return chars.join();
  }

  Future<void> _generateAndFillPassword() async {
    final generated = _generateTemporaryPassword();
    setState(() {
      _passwordCtrl.text = generated;
      _obscurePassword = false;
    });
    _passwordKey.currentState?.validate();
    await Clipboard.setData(ClipboardData(text: generated));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: _accent,
        content: Text('Temporary password generated and copied.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _fieldLabel('Login password', required: _isActive)),
            if (_isActive)
              TextButton.icon(
                onPressed: _submitting ? null : _generateAndFillPassword,
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 15),
                label: const Text('Generate', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: _passwordKey,
          controller: _passwordCtrl,
          obscureText: _obscurePassword,
          enabled: !_submitting,
          style: const TextStyle(color: _label, fontSize: 14),
          decoration: _inputDecoration(
            _isActive ? 'Temporary password' : 'Not needed — access is off',
            helperText: _isActive
                ? 'At least 6 characters. Shared with the user by email.'
                : null,
          ).copyWith(
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_passwordCtrl.text.trim().isNotEmpty)
                  IconButton(
                    tooltip: 'Copy password',
                    icon: const Icon(Icons.copy_rounded,
                        color: _subtle, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: _passwordCtrl.text));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Password copied.'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
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
              ],
            ),
          ),
          onChanged: (_) => setState(() {}),
          validator: (value) {
            if (!_isActive) return null;
            final v = value?.trim() ?? '';
            if (v.isEmpty) {
              return 'A password is required to create the login account';
            }
            // Caught here rather than after the round trip: Firebase rejects
            // short passwords only once the Auth call is already in flight,
            // by which point the master login-index entry has been written.
            if (v.length < 6) {
              return 'Use at least 6 characters (Firebase minimum)';
            }
            return null;
          },
        ),
      ],
    );
  }

  /// A dropdown that takes part in `Form.validate()`.
  ///
  /// The validator deliberately ignores the `FormField`'s own value and reads
  /// the parent's state variable instead — the parent stays the single source
  /// of truth (it is also reset from `_loadManagers`), so there is no second
  /// copy of the value to drift out of sync.
  Widget _dropdownFormField({
    required GlobalKey<FormFieldState<Object?>> fieldKey,
    required String label,
    required String hint,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required String? Function() validate,
    String? helperText,
    double? itemHeight,
    Widget? replacement,
  }) {
    return FormField<Object?>(
      key: fieldKey,
      validator: (_) => validate(),
      builder: (state) {
        final hasError = state.hasError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabel(label, required: true),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppThemeColors.darkCanvas,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasError ? _errorColor : _border,
                  width: hasError ? 1.4 : 1,
                ),
              ),
              child: replacement ??
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      dropdownColor: AppThemeColors.darkSurface,
                      value: value,
                      hint: Text(
                        hint,
                        style: const TextStyle(color: _subtle, fontSize: 13),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: _subtle),
                      itemHeight: itemHeight,
                      items: items,
                      onChanged: _submitting
                          ? null
                          : (v) {
                              onChanged(v);
                              // Clear the error the moment it is resolved.
                              state.didChange(v);
                              fieldKey.currentState?.validate();
                            },
                    ),
                  ),
            ),
            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  state.errorText!,
                  style: const TextStyle(color: _errorColor, fontSize: 12),
                ),
              )
            else if (helperText != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 2),
                child: Text(
                  helperText,
                  style: const TextStyle(color: _subtle, fontSize: 11),
                ),
              ),
          ],
        );
      },
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

  InputDecoration _inputDecoration(String hint, {String? helperText}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _subtle, fontSize: 13),
      helperText: helperText,
      helperStyle: const TextStyle(color: _subtle, fontSize: 11),
      helperMaxLines: 2,
      errorStyle: const TextStyle(color: _errorColor, fontSize: 12),
      errorMaxLines: 3,
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
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _errorColor, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _errorColor, width: 1.6),
      ),
    );
  }

  Widget _buildBloodGroupDropdown() {
    return _dropdownFormField(
      fieldKey: _bloodGroupKey,
      label: 'Blood Group',
      hint: 'Select blood group',
      value: _selectedBloodGroup,
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
      onChanged: (v) => setState(() => _selectedBloodGroup = v),
      validate: () =>
          _selectedBloodGroup == null ? 'Choose a blood group' : null,
    );
  }

  Widget _buildGenderDropdown() {
    return _dropdownFormField(
      fieldKey: _genderKey,
      label: 'Gender',
      hint: 'Select gender',
      value: _selectedGender,
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
      onChanged: (v) => setState(() => _selectedGender = v),
      validate: () => _selectedGender == null ? 'Choose a gender' : null,
    );
  }

  DateTime? _parseDOB(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final patterns = [
      'dd MMM yyyy',
      'dd/MM/yyyy',
      'yyyy-MM-dd',
      'dd-MM-yyyy',
      'MM/dd/yyyy',
      'd/M/yyyy',
      'd-M-yyyy',
    ];
    for (final pattern in patterns) {
      try {
        return DateFormat(pattern).parseStrict(trimmed);
      } catch (_) {}
    }
    return DateTime.tryParse(trimmed);
  }

  Future<void> _pickDOB() async {
    final now = DateTime.now();
    final firstDate = DateTime(1940);
    final lastDate = DateTime(now.year - 14, now.month, now.day);
    final fallbackYear = now.year - 22;
    DateTime initialDate = _dob ?? _parseDOB(_dobCtrl.text.trim()) ?? DateTime(fallbackYear, 1, 1);
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobCtrl.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  Widget _buildDOBPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Date of Birth', required: true),
        const SizedBox(height: 6),
        TextFormField(
          key: _dobKey,
          controller: _dobCtrl,
          enabled: !_submitting,
          style: const TextStyle(color: _label, fontSize: 14),
          cursorColor: _accent,
          decoration: _inputDecoration('DD/MM/YYYY or select date').copyWith(
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today_rounded, size: 18, color: _subtle),
              onPressed: _submitting ? null : _pickDOB,
              tooltip: 'Choose Date of Birth',
            ),
          ),
          onChanged: (val) {
            final parsed = _parseDOB(val);
            if (parsed != null) {
              _dob = parsed;
            }
          },
          validator: (val) {
            final trimmed = val?.trim() ?? '';
            if (trimmed.isEmpty) {
              return 'Date of Birth is required';
            }
            final parsed = _parseDOB(trimmed);
            if (parsed == null) {
              return 'Enter valid date (e.g. 15/08/1998 or 15 Aug 1998)';
            }
            final now = DateTime.now();
            final minAgeDate = DateTime(now.year - 14, now.month, now.day);
            if (parsed.isAfter(minAgeDate)) {
              return 'User must be at least 14 years old';
            }
            return null;
          },
        ),
      ],
    );
  }
}

/// A uniqueness clash found during the pre-flight check.
class _FieldConflict {
  final bool isEmail;
  final String message;

  const _FieldConflict({required this.isEmail, required this.message});
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
