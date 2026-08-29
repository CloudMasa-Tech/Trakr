// lib/screens/app_shell.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../firebase/firebase_context_provider.dart';
import '../widgets/common/firestore_notification_banner.dart';
import '../widgets/common/sidebar.dart';
import '../services/profile_photo_sync_service.dart';
import '../utils/profile_photo_picker.dart';
import 'dashboard/attendance_dashboard_screen.dart';
import 'geo_tag/geo_tag_screen.dart';
import 'admin/attendance_history_screen.dart';
import 'admin/manager_attendance_log_screen.dart';
import 'admin/weekend_holiday_screen.dart';
import 'admin/manager_requests_screen.dart';
import 'admin/notifications_history_screen.dart';

import 'admin/team_directory_screen.dart';
import 'admin/user_roles_screen.dart';
import 'admin/designations_screen.dart';
import 'staff/checkout_request_screen.dart';
import 'admin/payroll_screen.dart';
import 'admin/monthly_analysis_screen.dart';
import '../theme/app_theme_colors.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;
  final Future<void> Function() onLogout;

  const AppShell({
    super.key,
    this.initialIndex = 0,
    required this.onLogout,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _selectedIndex;
  String? _adminDocId;
  String? _adminProfileCollection;
  Map<String, dynamic>? _adminDocData;
  bool _savingAdminPhoto = false;
  bool _logoutDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _resolveAdminContext();
  }

  Future<void> _resolveAdminContext() async {
    try {
      final profileRef = await _resolveAdminProfileRef(createIfMissing: true);
      if (profileRef != null) {
        final docSnap = await profileRef.get();
        if (!mounted) return;
        setState(() {
          _adminDocId = docSnap.id;
          _adminProfileCollection = profileRef.parent.id;
          _adminDocData = docSnap.data();
        });
      }
    } catch (_) {}
  }

  Map<String, dynamic> _defaultAdminProfileData(User user) {
    final email = user.email?.trim().toLowerCase() ?? '';
    final displayName = user.displayName?.trim();
    final fallbackName = _nameFromEmail(email);
    return {
      'name': displayName?.isNotEmpty == true ? displayName : fallbackName,
      'email': email,
      'department': 'Administrator',
      'position': 'Administrator',
      'photoUrl': user.photoURL,
      'authUid': user.uid,
      'role': 'company_admin',
      'joinDate': user.metadata.creationTime != null
          ? Timestamp.fromDate(user.metadata.creationTime!)
          : FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  String _nameFromEmail(String email) {
    if (email.trim().isEmpty) return 'Admin';
    final localPart = email.trim().split('@').first;
    final name = localPart
        .split(RegExp(r'[._-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    return name.isEmpty ? 'Admin' : name;
  }

  String _currentAdminNameFallback() {
    final user = FirebaseContextProvider.current.auth.currentUser;
    final displayName = user?.displayName?.trim();
    if (displayName?.isNotEmpty == true) return displayName!;
    return _nameFromEmail(user?.email?.trim().toLowerCase() ?? '');
  }

  List<String> _adminNotificationIdentities() {
    final user = FirebaseContextProvider.current.auth.currentUser;
    return [
      'Admin',
      'admin',
      if (user?.uid.trim().isNotEmpty == true) user!.uid.trim(),
      if (user?.email?.trim().isNotEmpty == true)
        user!.email!.trim().toLowerCase(),
      if (_adminDocId?.trim().isNotEmpty == true) _adminDocId!.trim(),
      if (_adminDocData?['name']?.toString().trim().isNotEmpty == true)
        _adminDocData!['name'].toString().trim(),
    ];
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveAdminProfileRef({
    required bool createIfMissing,
  }) async {
    final user = FirebaseContextProvider.current.auth.currentUser;
    final db = FirebaseContextProvider.current.firestore;

    if (_adminDocId?.trim().isNotEmpty == true &&
        _adminProfileCollection?.trim().isNotEmpty == true) {
      final ref = db
          .collection(_adminProfileCollection!.trim())
          .doc(_adminDocId!.trim());
      try {
        final doc = await ref.get();
        if (doc.exists) return ref;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    if (user != null) {
      try {
        final querySnap = await db
            .collection('admins')
            .where('authUid', isEqualTo: user.uid)
            .limit(1)
            .get();
        if (querySnap.docs.isNotEmpty) {
          _adminDocId = querySnap.docs.first.id;
          _adminProfileCollection = 'admins';
          return querySnap.docs.first.reference;
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    final userEmail = user?.email?.trim().toLowerCase();
    if (user != null && userEmail?.isNotEmpty == true) {
      try {
        final querySnap = await db
            .collection('admins')
            .where('email', isEqualTo: userEmail)
            .limit(1)
            .get();
        if (querySnap.docs.isNotEmpty) {
          _adminDocId = querySnap.docs.first.id;
          _adminProfileCollection = 'admins';
          if (createIfMissing) {
            await querySnap.docs.first.reference.set(
              {
                'authUid': user.uid,
                'role': 'admin',
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
          return querySnap.docs.first.reference;
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    if (user != null) {
      final userProfileRef = db.collection('users').doc(user.uid);
      try {
        final userProfile = await userProfileRef.get();
        if (userProfile.exists) {
          _adminDocId = userProfileRef.id;
          _adminProfileCollection = 'users';
          return userProfileRef;
        }
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    if (!createIfMissing || user == null) return null;

    final docRef = db.collection('users').doc(user.uid);
    await docRef.set(_defaultAdminProfileData(user), SetOptions(merge: true));
    _adminDocId = docRef.id;
    _adminProfileCollection = 'users';
    return docRef;
  }

  Future<void> _writeAdminProfileUpdates(Map<String, dynamic> updates) async {
    final user = FirebaseContextProvider.current.auth.currentUser;
    if (user == null) {
      throw Exception('No signed-in admin user.');
    }

    final profileRef = await _resolveAdminProfileRef(createIfMissing: true);
    if (profileRef == null) {
      throw Exception('Admin profile not found.');
    }

    final payload = {
      ...updates,
      'role': 'company_admin',
      'authUid': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await profileRef.set(payload, SetOptions(merge: true));
      _adminDocId = profileRef.id;
      _adminProfileCollection = profileRef.parent.id;
      final userRef = FirebaseContextProvider.current.firestore
          .collection('users')
          .doc(user.uid);
      if (profileRef.path != userRef.path) {
        await userRef.set(payload, SetOptions(merge: true));
      }
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied' || profileRef.parent.id == 'users') {
        rethrow;
      }
      final userRef = FirebaseContextProvider.current.firestore
          .collection('users')
          .doc(user.uid);
      await userRef.set(
        {
          ..._defaultAdminProfileData(user),
          ...payload,
        },
        SetOptions(merge: true),
      );
      _adminDocId = userRef.id;
      _adminProfileCollection = 'users';
    }
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
      case 1:
        return const AttendanceDashboardScreen();
      case 2:
      case 10:
        return const _SystemSettingsScreen();

      case 3:
        return const TeamDirectoryScreen();
      case 4:
        return const PayrollScreen();

      case 7:
        return const _SystemSettingsScreen();
      case 8:
        return const ManagerRequestsScreen();
      case 9:
        return const CheckoutRequestScreen();
      case 11:
        return const AttendanceHistoryScreen();
      case 12:
        return const ManagerAttendanceLogScreen();
      case 13:
        return const MonthlyAnalysisScreen();
      case 14:
        return const NotificationsHistoryScreen();
      case 15:
        return const UserRolesScreen();
      case 16:
        return const DesignationsScreen();
      default:
        return const AttendanceDashboardScreen();
    }
  }

  Future<void> _showLogoutConfirmation() async {
    if (_logoutDialogOpen || !mounted) {
      return;
    }
    _logoutDialogOpen = true;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      _logoutDialogOpen = false;
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dark.error,
              foregroundColor: AppColors.dark.textPrimary,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    _logoutDialogOpen = false;

    if (confirmed == true) {
      await widget.onLogout();
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      // The router's redirect lands signed-out users back on the auth gate.
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= 980;
        final page = _buildPage(_selectedIndex);

        if (showSidebar) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: AppBackground(
              forceDark: true,
              child: Column(
                children: [
                  FirestoreNotificationBanner(
                    identities: _adminNotificationIdentities(),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        Sidebar(
                          selectedIndex: _selectedIndex,
                          onItemSelected: (i) =>
                              setState(() => _selectedIndex = i),
                          onLogout: _showLogoutConfirmation,
                          onProfileTap: () => _showAdminProfilePopup(context),
                          adminName: _adminDocData?['name']?.toString(),
                          adminRole: _adminDocData?['position']?.toString() ??
                              _adminDocData?['department']?.toString(),
                          photoUrl: _adminDocData?['photoUrl']?.toString(),
                        ),
                        Expanded(
                          child: page,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        int bottomBarIndex = 0;
        if (_selectedIndex == 0) {
          bottomBarIndex = 0;
        } else if (_selectedIndex == 11) {
          bottomBarIndex = 1;
        } else if (_selectedIndex == 2) {
          bottomBarIndex = 2;
        } else if (_selectedIndex == 3) {
          bottomBarIndex = 3;
        } else {
          bottomBarIndex = 4;
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: AppBackground(
            forceDark: true,
            child: SafeArea(
              child: Column(
                children: [
                  FirestoreNotificationBanner(
                    identities: _adminNotificationIdentities(),
                  ),
                  _buildMobileHeader(context),
                  Expanded(child: page),
                ],
              ),
            ),
          ),
          bottomNavigationBar: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: AppColors.dark.background,
            ),
            child: BottomNavigationBar(
              currentIndex: bottomBarIndex,
              onTap: (index) {
                if (index == 4) {
                  _showMoreBottomSheet(context);
                } else {
                  int targetIndex = 0;
                  if (index == 0) {
                    targetIndex = 0;
                  } else if (index == 1) {
                    targetIndex = 11;
                  } else if (index == 2) {
                    targetIndex = 2;
                  } else if (index == 3) {
                    targetIndex = 3;
                  }
                  setState(() {
                    _selectedIndex = targetIndex;
                  });
                }
              },
              backgroundColor: AppColors.dark.background,
              selectedItemColor: AppColors.dark.focus,
              unselectedItemColor: AppColors.dark.textMuted,
              type: BottomNavigationBarType.fixed,
              selectedLabelStyle:
                  const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 10),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.grid_view_rounded, size: 20),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.history_rounded, size: 20),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.location_on_outlined, size: 20),
                  label: 'Geo-Tag',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline_rounded, size: 20),
                  label: 'Team',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.more_horiz_rounded, size: 20),
                  label: 'More',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAdminProfilePopup(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final doc = _adminDocData;
        final name = doc?['name']?.toString() ?? _currentAdminNameFallback();
        final designation = doc?['position']?.toString() ??
            doc?['department']?.toString() ??
            'HR Admin';
        final email = doc?['email']?.toString() ??
            FirebaseContextProvider.current.auth.currentUser?.email ??
            '';

        String joinDateStr = 'Not set';
        if (doc?['joinDate'] is Timestamp) {
          joinDateStr = DateFormat('dd MMM yyyy')
              .format((doc!['joinDate'] as Timestamp).toDate());
        } else if (doc?['createdAt'] is Timestamp) {
          joinDateStr = DateFormat('dd MMM yyyy')
              .format((doc!['createdAt'] as Timestamp).toDate());
        } else if (FirebaseContextProvider
                .current.auth.currentUser?.metadata.creationTime !=
            null) {
          joinDateStr = DateFormat('dd MMM yyyy').format(FirebaseContextProvider
              .current.auth.currentUser!.metadata.creationTime!);
        }

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.dark.surfaceRaised,
                  AppColors.dark.background
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.dark.border, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.dark.overlay,
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.dark.secondary,
                          AppColors.dark.focus
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(22),
                        topRight: Radius.circular(22),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.dark.secondary,
                                AppColors.dark.focus
                              ],
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: AppColors.dark.background,
                            backgroundImage: _getAdminProfileImage(
                                doc?['photoUrl']?.toString()),
                            child:
                                doc?['photoUrl']?.toString().isNotEmpty == true
                                    ? null
                                    : Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : 'A',
                                        style: TextStyle(
                                          color: AppColors.dark.textPrimary,
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _savingAdminPhoto
                                  ? null
                                  : () {
                                      Navigator.of(context).pop();
                                      _pickAndSaveAdminPhoto();
                                    },
                              icon: const Icon(Icons.photo_camera_rounded,
                                  size: 16),
                              label: const Text('Upload photo'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.dark.focus,
                                side: BorderSide(
                                  color: AppColors.dark.focus,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            if (doc?['photoUrl']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ==
                                true)
                              TextButton.icon(
                                onPressed: _savingAdminPhoto
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                        _saveAdminPhotoUrl(null);
                                      },
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 16),
                                label: const Text('Remove photo'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.dark.error,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.dark.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.dark.secondary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.dark.secondary
                                    .withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            designation.toUpperCase(),
                            style: TextStyle(
                              color: AppColors.dark.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: AppColors.dark.border, height: 1),
                        const SizedBox(height: 16),
                        _buildProfileDetailRow(
                            Icons.email_outlined, 'Email Address', email),
                        _buildProfileDetailRow(Icons.calendar_today_outlined,
                            'Joined Date', joinDateStr),
                        if (doc?['phone'] != null &&
                            doc!['phone'].toString().isNotEmpty)
                          _buildProfileDetailRow(Icons.phone_outlined,
                              'Phone Number', doc['phone'].toString()),
                        if (doc?['bloodGroup'] != null &&
                            doc!['bloodGroup'].toString().isNotEmpty)
                          _buildProfileDetailRow(Icons.bloodtype_outlined,
                              'Blood Group', doc['bloodGroup'].toString()),
                        if (doc?['gender'] != null &&
                            doc!['gender'].toString().isNotEmpty)
                          _buildProfileDetailRow(Icons.transgender_outlined,
                              'Gender', doc['gender'].toString()),
                        if (doc?['nationality'] != null &&
                            doc!['nationality'].toString().isNotEmpty)
                          _buildProfileDetailRow(Icons.flag_outlined,
                              'Nationality', doc['nationality'].toString()),
                        if (doc?['dob'] is Timestamp)
                          _buildProfileDetailRow(
                              Icons.cake_outlined,
                              'Date of Birth',
                              DateFormat('dd MMM yyyy')
                                  .format((doc!['dob'] as Timestamp).toDate())),
                        if (doc?['address'] != null &&
                            doc!['address'].toString().isNotEmpty)
                          _buildProfileDetailRow(Icons.location_on_outlined,
                              'Address', doc['address'].toString()),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _showEditProfileDialog(context);
                            },
                            icon: const Icon(Icons.edit_rounded, size: 17),
                            label: const Text('Edit Profile'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.dark.focus,
                              side: BorderSide(
                                color: AppColors.dark.focus,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.dark.border,
                              foregroundColor: AppColors.dark.textPrimary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Close',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.dark.border,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.dark.textSecondary, size: 16),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppColors.dark.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: AppColors.dark.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider? _getAdminProfileImage(String? photoUrl) {
    final raw = photoUrl?.trim();
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

  Future<void> _pickAndSaveAdminPhoto() async {
    if (_savingAdminPhoto) return;
    try {
      setState(() => _savingAdminPhoto = true);
      final photoUrl = await pickProfilePhotoDataUrl();
      if (photoUrl == null) {
        if (mounted) setState(() => _savingAdminPhoto = false);
        return;
      }
      await _saveAdminPhotoUrl(photoUrl);
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingAdminPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking photo: $e'),
          backgroundColor: AppColors.dark.error,
        ),
      );
    }
  }

  Future<void> _saveAdminPhotoUrl(String? photoUrl) async {
    if (_savingAdminPhoto && photoUrl == null) return;
    try {
      setState(() => _savingAdminPhoto = true);
      await _writeAdminProfileUpdates({
        'photoUrl': photoUrl,
      });
      final adminEmployeeId = _adminDocData?['employeeId']?.toString();
      if (adminEmployeeId?.trim().isNotEmpty == true) {
        await ProfilePhotoSyncService.updateAttendancePhoto(
          photoUrl: photoUrl ?? '',
          employeeIds: [adminEmployeeId!.trim()],
        );
      }
      await _resolveAdminContext();
      if (!mounted) return;
      setState(() {
        _adminDocData = {
          ...?_adminDocData,
          'photoUrl': photoUrl,
        };
        _savingAdminPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            photoUrl == null
                ? 'Profile photo removed.'
                : 'Profile photo updated.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingAdminPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating photo: $e'),
          backgroundColor: AppColors.dark.error,
        ),
      );
    }
  }

  Widget _buildMobileHeader(BuildContext context) {
    final doc = _adminDocData;
    final name = doc?['name']?.toString() ?? _currentAdminNameFallback();
    final email = doc?['email']?.toString() ??
        FirebaseContextProvider.current.auth.currentUser?.email ??
        '';

    String joinDateStr = 'Not set';
    if (doc?['joinDate'] is Timestamp) {
      joinDateStr = DateFormat('dd MMM yyyy')
          .format((doc!['joinDate'] as Timestamp).toDate());
    } else if (doc?['createdAt'] is Timestamp) {
      joinDateStr = DateFormat('dd MMM yyyy')
          .format((doc!['createdAt'] as Timestamp).toDate());
    } else if (FirebaseContextProvider
            .current.auth.currentUser?.metadata.creationTime !=
        null) {
      joinDateStr = DateFormat('dd MMM yyyy').format(FirebaseContextProvider
          .current.auth.currentUser!.metadata.creationTime!);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.dark.background.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dark.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.overlay,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _showAdminProfilePopup(context),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.dark.secondary,
                          AppColors.dark.focus
                        ],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.dark.background,
                      backgroundImage:
                          _getAdminProfileImage(doc?['photoUrl']?.toString()),
                      child: doc?['photoUrl']?.toString().isNotEmpty == true
                          ? null
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'A',
                              style: TextStyle(
                                color: AppColors.dark.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: AppColors.dark.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.dark.secondary
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'ADMIN',
                                style: TextStyle(
                                  color: AppColors.dark.secondary,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email,
                          style: TextStyle(
                            color: AppColors.dark.textSecondary,
                            fontSize: 10.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Joined: $joinDateStr',
                          style: TextStyle(
                            color: AppColors.dark.textMuted,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _showEditProfileDialog(context),
            icon:
                Icon(Icons.edit_rounded, color: AppColors.dark.focus, size: 17),
            tooltip: 'Edit profile',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.dark.focus.withValues(alpha: 0.08),
              padding: const EdgeInsets.all(8),
            ),
          ),
          IconButton(
            onPressed: () async {
              await _showLogoutConfirmation();
            },
            icon: Icon(Icons.logout_rounded,
                color: AppColors.dark.error, size: 20),
            tooltip: 'Logout',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.dark.error.withValues(alpha: 0.12),
              padding: const EdgeInsets.all(8),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final doc = _adminDocData;
    final initialEmail = doc?['email']?.toString() ??
        FirebaseContextProvider.current.auth.currentUser?.email ??
        '';
    DateTime selectedDate = DateTime.now();
    if (doc?['joinDate'] is Timestamp) {
      selectedDate = (doc!['joinDate'] as Timestamp).toDate();
    } else if (doc?['createdAt'] is Timestamp) {
      selectedDate = (doc!['createdAt'] as Timestamp).toDate();
    }

    final emailController = TextEditingController(text: initialEmail);
    final formKey = GlobalKey<FormState>();
    String? tempPhotoUrl = doc?['photoUrl']?.toString();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final avatarImage = _getAdminProfileImage(tempPhotoUrl);
            return AlertDialog(
              backgroundColor: AppColors.dark.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppColors.dark.border),
              ),
              title: Row(
                children: [
                  Icon(Icons.edit_rounded,
                      color: AppColors.dark.focus, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Edit Admin Profile',
                    style: TextStyle(
                        color: AppColors.dark.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Avatar Editor
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.dark.secondary,
                                  AppColors.dark.focus
                                ],
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: AppColors.dark.background,
                              backgroundImage: avatarImage,
                              child: tempPhotoUrl?.trim().isNotEmpty == true
                                  ? null
                                  : Text(
                                      'A',
                                      style: TextStyle(
                                        color: AppColors.dark.textPrimary,
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          InkWell(
                            onTap: () async {
                              try {
                                final photoUrl =
                                    await pickProfilePhotoDataUrl();
                                if (photoUrl != null) {
                                  if (!context.mounted) return;
                                  setDialogState(() {
                                    tempPhotoUrl = photoUrl;
                                  });
                                }
                              } catch (e) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text('Error picking photo: $e'),
                                      backgroundColor: AppColors.dark.error),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.dark.focus,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.camera_alt_rounded,
                                color: AppColors.dark.background,
                                size: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (tempPhotoUrl != null && tempPhotoUrl!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () {
                            setDialogState(() {
                              tempPhotoUrl = null;
                            });
                          },
                          icon: Icon(Icons.delete_outline_rounded,
                              color: AppColors.dark.error, size: 16),
                          label: Text('Remove Photo',
                              style: TextStyle(
                                  color: AppColors.dark.error, fontSize: 12)),
                        ),
                      ],
                      const SizedBox(height: 18),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Working Email',
                          style: TextStyle(
                              color: AppColors.dark.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: emailController,
                        style: TextStyle(
                            color: AppColors.dark.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.dark.surfaceRaised,
                          hintText: 'Enter working email',
                          hintStyle: TextStyle(color: AppColors.dark.textMuted),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                BorderSide(color: AppColors.dark.border),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Email is required';
                          }
                          if (!val.contains('@')) {
                            return 'Invalid email address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Date of Joining',
                          style: TextStyle(
                              color: AppColors.dark.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2000),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.dark(
                                    primary: AppColors.dark.focus,
                                    onPrimary: AppColors.dark.background,
                                    surface: AppColors.dark.background,
                                    onSurface: AppColors.dark.textPrimary,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setDialogState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.dark.surfaceRaised,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.dark.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('dd MMM yyyy').format(selectedDate),
                                style: TextStyle(
                                    color: AppColors.dark.textPrimary,
                                    fontSize: 13),
                              ),
                              Icon(Icons.calendar_today_rounded,
                                  color: AppColors.dark.focus, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel',
                      style: TextStyle(color: AppColors.dark.textMuted)),
                ),
                FilledButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final email = emailController.text.trim();
                      try {
                        await _writeAdminProfileUpdates({
                          'email': email.toLowerCase(),
                          'joinDate': Timestamp.fromDate(selectedDate),
                          'photoUrl': tempPhotoUrl,
                        });

                        await _resolveAdminContext(); // Reload context
                        if (context.mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  const Text('Profile updated successfully!'),
                              backgroundColor: AppColors.dark.focus,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error updating profile: $e'),
                              backgroundColor: AppColors.dark.error,
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.dark.focus,
                    foregroundColor: AppColors.dark.background,
                  ),
                  child: const Text('Save',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showMoreBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.dark.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final moreItems = [
          {
            'index': 12,
            'label': 'Manager Activity Log',
            'icon': Icons.manage_history_rounded
          },
          {
            'index': 13,
            'label': 'Monthly Analysis',
            'icon': Icons.analytics_outlined
          },
          {
            'index': 4,
            'label': 'Payroll & Compensation',
            'icon': Icons.payments_outlined
          },
          {
            'index': 7,
            'label': 'Settings',
            'icon': Icons.settings_outlined
          },
          {
            'index': 9,
            'label': 'Checkout Request',
            'icon': Icons.assignment_late_outlined
          },
          {
            'index': 8,
            'label': 'Manager Requests',
            'icon': Icons.notifications_active_outlined
          },
          {
            'index': 14,
            'label': 'Notifications',
            'icon': Icons.notifications_outlined
          },
          {
            'index': 15,
            'label': 'Roles & Permissions',
            'icon': Icons.admin_panel_settings_outlined
          },
          {
            'index': 16,
            'label': 'Designations',
            'icon': Icons.work_outline_rounded
          },
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'More Options',
                      style: TextStyle(
                        color: AppColors.dark.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.dark.textSecondary, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: moreItems.length,
                    itemBuilder: (context, idx) {
                      final item = moreItems[idx];
                      final isSelected = _selectedIndex == item['index'];
                      return InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _selectedIndex = item['index'] as int;
                          });
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.dark.focus.withValues(alpha: 0.12)
                                : AppColors.dark.hover,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.dark.focus.withValues(alpha: 0.3)
                                  : AppColors.dark.border,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                item['icon'] as IconData,
                                color: isSelected
                                    ? AppColors.dark.focus
                                    : AppColors.dark.textSecondary,
                                size: 24,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item['label'] as String,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.dark.focus
                                      : AppColors.dark.textPrimary,
                                  fontSize: 10.5,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// System Settings screen: tabs embedding geo-fencing and weekly off / holidays
class _SystemSettingsScreen extends StatelessWidget {
  const _SystemSettingsScreen();

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'System Settings',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Geo-fencing rules and weekly off / holiday configuration',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: colors.focus.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                labelColor: colors.focus,
                unselectedLabelColor: colors.textSecondary,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: const [
                  Tab(height: 44, text: 'Geo-Fencing'),
                  Tab(height: 44, text: 'Weekly Off & Holidays'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Expanded(
              child: TabBarView(
                children: [
                  GeoTagScreen(),
                  WeekendHolidayScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
