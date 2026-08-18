import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../utils/departments.dart';

class AttendanceCompanySummary {
  final int staffCount;
  final int presentToday;
  final int lateToday;
  final int absentToday;

  const AttendanceCompanySummary({
    required this.staffCount,
    required this.presentToday,
    required this.lateToday,
    required this.absentToday,
  });
}

class LeaveCompanySummary {
  final int total;
  final int pending;
  final int approved;
  final int rejected;

  const LeaveCompanySummary({
    required this.total,
    required this.pending,
    required this.approved,
    required this.rejected,
  });
}

class CompanyActivityEvent {
  final String staffName;
  final String eventType;
  final DateTime timestamp;
  final bool qrValidated;
  final bool geofenceValidated;

  const CompanyActivityEvent({
    required this.staffName,
    required this.eventType,
    required this.timestamp,
    required this.qrValidated,
    required this.geofenceValidated,
  });
}

class CompanyAdminRow {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String? companyId;
  final String companyName;
  final bool isActive;

  const CompanyAdminRow({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    this.companyId,
    required this.companyName,
    required this.isActive,
  });
}

class CompanyOffice {
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final num? radius;

  const CompanyOffice({
    required this.name,
    this.address,
    this.latitude,
    this.longitude,
    this.radius,
  });
}

/// Read-side analytics for the Super Admin Client Onboarding module.
///
/// Collections that carry an optional `companyId` (`staff`, `managers`,
/// `users`, `admins`, `offices`) are queried directly. Collections that are
/// keyed only by `employeeId` (`attendance`, `attendance_logs`,
/// `leave_requests`) are joined to the company through its staff directory.
class CompanyAnalyticsService {
  CompanyAnalyticsService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;

  /// Total number of login accounts in the `users` directory.
  Future<int> getTotalUserCount() async {
    try {
      final snap = await _firestore.collection('users').limit(1000).get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Total number of Company Admin login accounts (`users` docs with the
  /// `company_admin` role).
  Future<int> getTotalCompanyAdminCount() async {
    try {
      final snap = await _firestore
          .collection('users')
          .where('role', whereIn: const ['admin', 'company_admin'])
          .limit(1000)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Total number of staff (engineers) across the platform.
  Future<int> getStaffCountTotal() async {
    try {
      final snap = await _firestore.collection('staff').limit(1000).get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Total number of manager accounts across the platform.
  Future<int> getManagerCountTotal() async {
    try {
      final snap = await _firestore.collection('managers').limit(1000).get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Distinct staff who recorded any attendance today. Used as the "Active
  /// Users Today" figure on the Super Admin dashboard.
  Future<int> getActiveUsersToday() async {
    try {
      final now = DateTime.now();
      final dateKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final snap = await _firestore
          .collection('attendance')
          .where('dateKey', isEqualTo: dateKey)
          .limit(1000)
          .get();
      final seen = <String>{};
      for (final doc in snap.docs) {
        final employeeId = (doc.data()['employeeId'] as String? ?? '').trim();
        if (employeeId.isEmpty) continue;
        seen.add(employeeId);
      }
      return seen.length;
    } catch (_) {
      return 0;
    }
  }

  /// Company Admin directory rows: `users` login accounts carrying the
  /// `company_admin` role, with their company name resolved from the
  /// `companies` collection.
  Stream<List<CompanyAdminRow>> streamCompanyAdmins() async* {
    final seen = <String>{};
    final companies = <String, String>{};
    try {
      final snap = await _firestore.collection('companies').get();
      for (final doc in snap.docs) {
        companies[doc.id] = (doc.data()['name'] as String? ?? '').trim();
      }
    } catch (_) {}

    Stream<QuerySnapshot<Map<String, dynamic>>> usersStream() {
      return _firestore
          .collection('users')
          .where('role', whereIn: const ['admin', 'company_admin'])
          .snapshots();
    }

    await for (final snap in usersStream()) {
      final rows = <CompanyAdminRow>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final uid = doc.id;
        seen.add(uid);
        rows.add(CompanyAdminRow(
          uid: uid,
          name: (data['name'] as String? ?? '').trim(),
          email: (data['email'] as String? ?? '').trim(),
          phone: (data['phone'] as String? ?? '').trim(),
          companyId: data['companyId'] as String?,
          companyName: companies[data['companyId']] ?? 'Unknown',
          isActive: data['isActive'] ?? data['status'] != 'inactive',
        ));
      }
      rows.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      yield rows;
    }
  }

  /// Latest user accounts created on the platform, used for the dashboard
  /// "Recent Activity" feed.
  Stream<List<Map<String, dynamic>>> streamRecentUsers() {
    return _firestore
        .collection('users')
        .orderBy('createdAt', descending: true)
        .limit(8)
        .snapshots()
        .map((snap) {
      final events = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        events.add({
          'name': (data['name'] as String? ?? '').trim(),
          'email': (data['email'] as String? ?? '').trim(),
          'role': (data['role'] as String? ?? '').trim(),
          'companyId': data['companyId'],
          'createdAt': (data['createdAt'] as Timestamp?)?.toDate(),
        });
      }
      return events;
    });
  }

  /// Maps companyId -> number of login accounts (`users` docs).
  Future<Map<String, int>> getUserCountByCompany() async {
    final counts = <String, int>{};
    try {
      final snap = await _firestore.collection('users').limit(1000).get();
      for (final doc in snap.docs) {
        final companyId = doc.data()['companyId'] as String?;
        if (companyId == null || companyId.isEmpty) continue;
        counts[companyId] = (counts[companyId] ?? 0) + 1;
      }
    } catch (_) {}
    return counts;
  }

  /// Maps companyId -> name of the primary Company Admin, resolved from the
  /// `users` and `admins` directories.
  Future<Map<String, String>> getCompanyAdminMap() async {
    final map = <String, String>{};
    try {
      final usersSnap = await _firestore.collection('users').limit(1000).get();
      for (final doc in usersSnap.docs) {
        final data = doc.data();
        final companyId = data['companyId'] as String?;
        final name = (data['name'] as String? ?? '').trim();
        final role = (data['role'] as String? ?? '').trim().toLowerCase();
        if (companyId == null || companyId.isEmpty || name.isEmpty) continue;
        if (role == 'company_admin' ||
            role == 'companyadmin' ||
            role == 'admin') {
          map.putIfAbsent(companyId, () => name);
        }
      }
    } catch (_) {}
    try {
      final adminsSnap =
          await _firestore.collection('admins').limit(1000).get();
      for (final doc in adminsSnap.docs) {
        final data = doc.data();
        final companyId = data['companyId'] as String?;
        final name = (data['name'] as String? ?? '').trim();
        if (companyId == null || companyId.isEmpty || name.isEmpty) continue;
        map.putIfAbsent(companyId, () => name);
      }
    } catch (_) {}
    return map;
  }

  /// Staff doc ids that belong to a company. Staff docs are keyed by
  /// `employeeId`, which is the join key used by `attendance` and
  /// `attendance_logs`.
  Future<Set<String>> getCompanyStaffIds(String companyId) async {
    try {
      final snap = await _firestore
          .collection('staff')
          .where('companyId', isEqualTo: companyId)
          .get();
      return snap.docs.map((doc) => doc.id).toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<int> getStaffCount(String companyId) async {
    try {
      final snap = await _firestore
          .collection('staff')
          .where('companyId', isEqualTo: companyId)
          .limit(1000)
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  /// Departments (normalized) with head-counts for a company.
  Stream<List<MapEntry<String, int>>> streamDepartments(String companyId) {
    return _firestore
        .collection('staff')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map(_groupByString);
  }

  /// Designations (position) with head-counts for a company.
  Stream<List<MapEntry<String, int>>> streamDesignations(String companyId) {
    return _firestore
        .collection('staff')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((snap) {
      final counts = <String, int>{};
      for (final doc in snap.docs) {
        final position = (doc.data()['position'] as String? ?? '').trim();
        if (position.isEmpty) continue;
        counts[position] = (counts[position] ?? 0) + 1;
      }
      return counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    });
  }

  List<MapEntry<String, int>> _groupByString(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final department = displayDepartment(doc.data()['department'] as String?);
      if (department.isEmpty) continue;
      counts[department] = (counts[department] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Offices tagged with the company's id. The seed writes the default office
  /// with a `companyId`, so newly onboarded tenants appear here once their
  /// geofence is configured.
  Stream<List<CompanyOffice>> streamOffices(String companyId) {
    return _firestore
        .collection('offices')
        .where('companyId', isEqualTo: companyId)
        .snapshots()
        .map((snap) {
      final offices = <CompanyOffice>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        offices.add(CompanyOffice(
          name: (data['name'] as String? ?? '').trim().isEmpty
              ? 'Office'
              : (data['name'] as String? ?? '').trim(),
          address: data['address'] as String?,
          latitude: (data['latitude'] as num?)?.toDouble(),
          longitude: (data['longitude'] as num?)?.toDouble(),
          radius: data['radius'] ?? data['geoFenceRadius'],
        ));
      }
      offices.sort((a, b) => a.name.compareTo(b.name));
      return offices;
    });
  }

  /// Today's attendance summary for a company, joined through its staff ids.
  Stream<AttendanceCompanySummary> streamAttendanceSummary(
    String todayKey,
    Set<String> staffIds,
  ) {
    if (staffIds.isEmpty) {
      return Stream.value(
        const AttendanceCompanySummary(
          staffCount: 0,
          presentToday: 0,
          lateToday: 0,
          absentToday: 0,
        ),
      );
    }
    return _firestore
        .collection('attendance')
        .where('dateKey', isEqualTo: todayKey)
        .limit(1000)
        .snapshots()
        .map((snap) {
      var present = 0;
      var late = 0;
      final seen = <String>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final employeeId = (data['employeeId'] as String? ?? '').trim();
        if (!staffIds.contains(employeeId)) continue;
        seen.add(employeeId);
        present++;
        final lateMinutes = (data['lateMinutes'] as num?)?.toInt() ?? 0;
        if (lateMinutes > 0) late++;
      }
      final absent = max(0, staffIds.length - seen.length);
      return AttendanceCompanySummary(
        staffCount: staffIds.length,
        presentToday: present,
        lateToday: late,
        absentToday: absent,
      );
    });
  }

  /// Live leave request summary for a company's staff.
  Stream<LeaveCompanySummary> streamLeaveSummary(Set<String> staffIds) {
    if (staffIds.isEmpty) {
      return Stream.value(
        const LeaveCompanySummary(
          total: 0,
          pending: 0,
          approved: 0,
          rejected: 0,
        ),
      );
    }
    return _firestore
        .collection('leave_requests')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .snapshots()
        .map((snap) {
      var total = 0;
      var pending = 0;
      var approved = 0;
      var rejected = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final employeeId = (data['employeeId'] as String? ?? '').trim();
        if (!staffIds.contains(employeeId)) continue;
        total++;
        switch ((data['status'] as String? ?? '').trim().toLowerCase()) {
          case 'approved':
            approved++;
          case 'pending':
            pending++;
          case 'rejected':
            rejected++;
        }
      }
      return LeaveCompanySummary(
        total: total,
        pending: pending,
        approved: approved,
        rejected: rejected,
      );
    });
  }

  /// Latest audit-trail events (check-in/out, exits, returns) for the company's
  /// staff.
  Stream<List<CompanyActivityEvent>> streamRecentActivity(
    Set<String> staffIds,
  ) {
    if (staffIds.isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection('attendance_logs')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
      final events = <CompanyActivityEvent>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        final staffId = (data['staffId'] as String? ?? '').trim();
        if (!staffIds.contains(staffId)) continue;
        events.add(CompanyActivityEvent(
          staffName: (data['staffName'] as String? ?? '').trim(),
          eventType: (data['eventType'] as String? ?? 'CHECK_IN'),
          timestamp:
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          qrValidated: data['qrValidated'] ?? false,
          geofenceValidated: data['geofenceValidated'] ?? false,
        ));
        if (events.length >= 10) break;
      }
      return events;
    });
  }

  /// Activates or deactivates a Company Admin in both the `users` and `admins`
  /// directories.
  Future<void> setCompanyAdminActive(
    String uid, {
    required bool isActive,
  }) async {
    final batch = _firestore.batch();
    final updates = <String, dynamic>{
      'isActive': isActive,
      'status': isActive ? 'active' : 'inactive',
      'updatedAt': FieldValue.serverTimestamp(),
    };
    batch.update(_firestore.collection('users').doc(uid), updates);
    try {
      batch.update(_firestore.collection('admins').doc(uid), updates);
    } catch (_) {}
    await batch.commit();
  }

  /// Moves a Company Admin to another company in both directories.
  Future<void> reassignCompanyAdmin(String uid, String companyId) async {
    final batch = _firestore.batch();
    final updates = <String, dynamic>{
      'companyId': companyId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    batch.update(_firestore.collection('users').doc(uid), updates);
    try {
      batch.update(_firestore.collection('admins').doc(uid), updates);
    } catch (_) {}
    await batch.commit();
  }

  /// Permanently deletes a company and its company-scoped directory docs
  /// (`users` and `admins`). Firebase Auth accounts are left untouched.
  Future<void> deleteCompany(String companyId) async {
    final batch = _firestore.batch();
    batch.delete(_firestore.collection('companies').doc(companyId));
    try {
      final usersSnap = await _firestore
          .collection('users')
          .where('companyId', isEqualTo: companyId)
          .get();
      for (final doc in usersSnap.docs) {
        batch.delete(doc.reference);
      }
    } catch (_) {}
    try {
      final adminsSnap = await _firestore
          .collection('admins')
          .where('companyId', isEqualTo: companyId)
          .get();
      for (final doc in adminsSnap.docs) {
        batch.delete(doc.reference);
      }
    } catch (_) {}
    await batch.commit();
  }
}
