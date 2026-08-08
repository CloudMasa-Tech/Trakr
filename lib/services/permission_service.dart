import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/permission_request.dart';
import 'notification_service.dart';

class PermissionService {
  PermissionService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  FirebaseAuth get _auth => _context.auth;

  // ─── Identity helpers (mirrors LeaveService exactly) ──────────────────────

  String _normalizeIdentity(String value) => value.trim().toLowerCase();

  Set<String> _managerAliases(String managerName) {
    final aliases = <String>{};

    void addAlias(String? value) {
      if (value == null) return;
      final t = value.trim();
      if (t.isEmpty) return;
      aliases.add(_normalizeIdentity(t));
      aliases.add(_normalizeIdentity(t.replaceAll(' ', '')));
      if (t.contains('@')) {
        aliases.add(_normalizeIdentity(t.split('@').first));
      }
    }

    final user = _auth.currentUser;
    addAlias(managerName);
    addAlias(user?.uid);
    addAlias(user?.displayName);
    addAlias(user?.email);
    return aliases;
  }

  /// Thoroughly resolves all aliases for a manager by checking both the
  /// `managers` and `staff` Firestore collections (same as LeaveService).
  Future<Set<String>> _resolveManagerAliasesThoroughly(
      String managerName) async {
    final aliases = _managerAliases(managerName);

    // 1. Expand from managers collection
    try {
      final snap = await _firestore.collection('managers').get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final name = (d['name'] as String? ?? '').trim();
        final email = (d['email'] as String? ?? '').trim();

        final docAliases = <String>{};
        if (name.isNotEmpty) docAliases.add(_normalizeIdentity(name));
        if (email.isNotEmpty) {
          docAliases.add(_normalizeIdentity(email));
          docAliases.add(_normalizeIdentity(email.split('@').first));
        }
        docAliases.add(_normalizeIdentity(doc.id));

        if (docAliases.any(aliases.contains)) {
          aliases.addAll(docAliases);
        }
      }
    } catch (_) {}

    // 2. Expand from staff collection
    try {
      final snap = await _firestore.collection('staff').get();
      for (final doc in snap.docs) {
        final d = doc.data();
        final name = (d['name'] as String? ?? '').trim();
        final email = (d['email'] as String? ?? '').trim();
        final empId = (d['employeeId'] as String? ?? '').trim();

        final docAliases = <String>{};
        if (name.isNotEmpty) docAliases.add(_normalizeIdentity(name));
        if (email.isNotEmpty) {
          docAliases.add(_normalizeIdentity(email));
          docAliases.add(_normalizeIdentity(email.split('@').first));
        }
        if (empId.isNotEmpty) docAliases.add(_normalizeIdentity(empId));
        docAliases.add(_normalizeIdentity(doc.id));

        if (docAliases.any(aliases.contains)) {
          aliases.addAll(docAliases);
        }
      }
    } catch (_) {}

    return aliases;
  }

  // ─── Team resolution (mirrors LeaveService._teamUserIdsStreamForManager) ──

  /// Returns a stream of all employee/doc IDs for staff that report to
  /// [managerName].  Fetches all staff in-memory; no Firestore whereIn limit.
  Stream<List<String>> _teamEmployeeIdsStream(String managerName) {
    return _firestore
        .collection('staff')
        .snapshots()
        .asyncMap((snapshot) async {
      final managerAliases =
          await _resolveManagerAliasesThoroughly(managerName);
      final ids = <String>{};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final reportsTo = (data['reportsTo'] as String? ?? '').trim();
        if (reportsTo.isEmpty) continue;

        final rNorm = _normalizeIdentity(reportsTo);
        final rCompact = _normalizeIdentity(reportsTo.replaceAll(' ', ''));

        if (!managerAliases.contains(rNorm) &&
            !managerAliases.contains(rCompact)) {
          continue;
        }

        final empId = (data['employeeId'] as String? ?? '').trim();
        if (empId.isNotEmpty) ids.add(empId);
        final docId = doc.id.trim();
        if (docId.isNotEmpty) ids.add(docId);
      }

      return ids.toList();
    });
  }

  // ─── Manager query (mirrors LeaveService.getRequestsForManager exactly) ───

  /// Returns a stream of all permission requests for the manager's team.
  ///
  /// Matching strategy (same triple-check as LeaveService):
  ///  1. `managerName` field in the doc matches a manager alias.
  ///  2. `employeeId` or `userId` in the doc belongs to the manager's team.
  ///  3. `userId` in the doc is the manager themselves (edge-case safety).
  Stream<List<PermissionRequest>> getPermissionRequestsForManager(
      String managerName) {
    final controller = StreamController<List<PermissionRequest>>.broadcast();
    StreamSubscription? teamSub;
    StreamSubscription? requestSub;

    void cleanup() {
      teamSub?.cancel();
      requestSub?.cancel();
    }

    teamSub = _teamEmployeeIdsStream(managerName).listen((teamIds) {
      requestSub?.cancel();
      requestSub = _firestore
          .collection('permission_requests')
          .snapshots()
          .asyncMap((snapshot) async {
        final managerAliases =
            await _resolveManagerAliasesThoroughly(managerName);
        final normalizedTeam = teamIds.map(_normalizeIdentity).toSet();

        final results = <PermissionRequest>[];
        for (final doc in snapshot.docs) {
          PermissionRequest req;
          try {
            req = PermissionRequest.fromFirestore(doc);
          } catch (_) {
            continue;
          }

          final reqManager = _normalizeIdentity(req.managerName);
          final reqManagerCompact =
              _normalizeIdentity(req.managerName.replaceAll(' ', ''));
          final reqEmpId = _normalizeIdentity(req.employeeId);
          // Legacy docs may have stored Firebase UID in employeeId or userId
          final reqUserId =
              _normalizeIdentity(doc.data()['userId']?.toString() ?? '');

          bool isMatch = false;

          // 1. Direct managerName match
          if (reqManager.isNotEmpty &&
              (managerAliases.contains(reqManager) ||
                  managerAliases.contains(reqManagerCompact))) {
            isMatch = true;
          }

          // 2. Team member match (by employeeId or userId stored in doc)
          if (!isMatch &&
              (normalizedTeam.contains(reqEmpId) ||
                  (reqUserId.isNotEmpty &&
                      normalizedTeam.contains(reqUserId)))) {
            isMatch = true;
          }

          // 3. userId equals manager (edge-case)
          if (!isMatch && managerAliases.contains(reqEmpId)) {
            // exclude – this would be the manager's own requests
          }

          if (isMatch) results.add(req);
        }

        // Sort newest first
        results.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
        return results;
      }).listen(
        (data) {
          if (!controller.isClosed) controller.add(data);
        },
        onError: (err) {
          if (!controller.isClosed) controller.addError(err);
        },
      );
    }, onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    });

    controller.onCancel = cleanup;
    return controller.stream;
  }

  // ─── Employee query ────────────────────────────────────────────────────────

  Stream<List<PermissionRequest>> getPermissionRequestsForEmployee(
      String employeeId) {
    return _firestore
        .collection('permission_requests')
        .where('employeeId', isEqualTo: employeeId)
        .orderBy('requestedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PermissionRequest.fromFirestore(d)).toList());
  }

  Stream<List<PermissionRequest>> getPermissionRequestsStreamAll({
    int? limit,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('permission_requests')
        .orderBy('requestedAt', descending: true);
    if (limit != null && limit > 0) {
      query = query.limit(limit);
    }
    return query.snapshots().map(
          (snap) =>
              snap.docs.map((d) => PermissionRequest.fromFirestore(d)).toList(),
        );
  }

  // ─── Submit ────────────────────────────────────────────────────────────────

  Future<String> _validatePermissionRequest({
    required String employeeId,
    required String managerName,
    required String reason,
    String? permissionType,
    DateTime? fromTime,
    DateTime? toTime,
  }) async {
    if (reason.trim().isEmpty) {
      return 'Please provide a reason for your permission request.';
    }

    if (managerName.trim().isEmpty) {
      return 'No approver is assigned for this permission request.';
    }

    if (permissionType != 'Late Arrival' &&
        permissionType != 'Personal Permission' &&
        permissionType != 'Off-duty') {
      return 'Invalid permission type. Allowed types are: Late Arrival, Personal Permission, Off-duty.';
    }

    if (fromTime == null || toTime == null) {
      return 'Please select both From and To times.';
    }

    if (!toTime.isAfter(fromTime)) {
      return 'To Time must be after From Time.';
    }

    if (fromTime.isBefore(DateTime.now())) {
      return 'Permission start time cannot be in the past.';
    }

    final officeStart =
        DateTime(fromTime.year, fromTime.month, fromTime.day, 10, 0);
    final officeEnd =
        DateTime(fromTime.year, fromTime.month, fromTime.day, 18, 0);
    if (fromTime.isBefore(officeStart) || toTime.isAfter(officeEnd)) {
      return 'Permission time must be within standard office hours (10:00 AM to 06:00 PM).';
    }

    final existing = await _firestore
        .collection('permission_requests')
        .where('employeeId', isEqualTo: employeeId)
        .get();

    final hasOverlap = existing.docs.any((doc) {
      final request = PermissionRequest.fromFirestore(doc);
      if (request.status != 'approved' && request.status != 'pending') {
        return false;
      }
      final existingFrom = request.fromTime;
      final existingTo = request.toTime;
      if (existingFrom == null || existingTo == null) return false;
      return fromTime.isBefore(existingTo) && toTime.isAfter(existingFrom);
    });

    if (hasOverlap) {
      return 'You already have an approved or pending permission request for the selected time.';
    }

    return '';
  }

  Future<void> submitPermissionRequest({
    required String employeeId,
    required String employeeName,
    required String department,
    required String managerName,
    required String reason,
    String? permissionType,
    bool isManager = false,
    String? requesterUserId,
    String? staffId,
    String? email,
    DateTime? date,
    DateTime? fromTime,
    DateTime? toTime,
  }) async {
    final validationError = await _validatePermissionRequest(
      employeeId: employeeId,
      managerName: managerName,
      reason: reason,
      permissionType: permissionType,
      fromTime: fromTime,
      toTime: toTime,
    );

    if (validationError.isNotEmpty) {
      throw Exception(validationError);
    }

    final request = PermissionRequest(
      id: '',
      employeeId: employeeId,
      employeeName: employeeName,
      department: department,
      managerName: managerName,
      reason: reason.trim(),
      permissionType: permissionType,
      status: 'pending',
      requestedAt: DateTime.now(),
      date: date,
      fromTime: fromTime,
      toTime: toTime,
    );

    final map = request.toMap();
    map['type'] = permissionType;
    map['createdAt'] = FieldValue.serverTimestamp();
    map['updatedAt'] = FieldValue.serverTimestamp();
    map['staffName'] = employeeName;
    if (requesterUserId?.trim().isNotEmpty == true) {
      map['userId'] = requesterUserId!.trim();
    }
    if (staffId?.trim().isNotEmpty == true) {
      map['staffId'] = staffId!.trim();
    }
    if (email?.trim().isNotEmpty == true) {
      map['email'] = email!.trim();
    }
    if (isManager) {
      map['isManager'] = true;
    }

    final requestRef =
        await _firestore.collection('permission_requests').add(map);

    // Employee permission approval is owned by the assigned manager.
    try {
      final recipients = <String>{if (isManager) 'Admin' else managerName};
      for (final recipient in recipients) {
        await NotificationService().sendPermissionRequestNotification(
          recipient: recipient,
          requestId: requestRef.id,
          employeeId: employeeId,
          employeeName: employeeName,
          permissionType: permissionType ?? 'General',
          fromTime: fromTime,
          toTime: toTime,
          toAdmin: recipient.toLowerCase() == 'admin',
        );
      }
    } catch (e) {
      debugPrint('Failed to send permission request push notification: $e');
    }
  }

  // ─── Approve / Reject ──────────────────────────────────────────────────────

  Future<void> approvePermissionRequest({
    required String requestId,
    required String managerName,
    required String response,
    required bool isPaid,
    DateTime? returnTime,
  }) async {
    await _firestore.collection('permission_requests').doc(requestId).update({
      'status': 'approved',
      'managerResponse': response,
      'isPaid': isPaid,
      'returnTime': returnTime != null ? Timestamp.fromDate(returnTime) : null,
      'approvedReturnTime':
          returnTime != null ? Timestamp.fromDate(returnTime) : null,
      'approvedAt': Timestamp.fromDate(DateTime.now()),
      'respondedAt': Timestamp.fromDate(DateTime.now()),
      'respondedBy': managerName,
    });

    final request =
        await _firestore.collection('permission_requests').doc(requestId).get();
    final data = request.data();
    if (data != null) {
      final employeeId = data['employeeId'] as String? ?? '';
      final employeeName = data['employeeName'] as String? ?? 'Staff';
      final department = data['department'] as String? ?? '';
      final permissionType = data['permissionType'] as String? ?? 'General';
      final content = returnTime == null
          ? '$employeeName permission approved for $permissionType.'
          : '$employeeName permission approved until ${_formatTime(returnTime)}.';
      await _createPermissionNotification(
        employeeId: employeeId,
        employeeName: employeeName,
        department: department,
        managerName: managerName,
        content: content,
        status: 'approved',
      );

      // Trigger push notification back to the staff member
      try {
        final sent =
            await NotificationService().sendPermissionDecisionNotification(
          identifier: employeeId,
          approved: true,
          returnTime: returnTime,
        );
        final userId = data['userId']?.toString().trim() ?? '';
        if (!sent && userId.isNotEmpty && userId != employeeId.trim()) {
          await NotificationService().sendPermissionDecisionNotification(
            identifier: userId,
            approved: true,
            returnTime: returnTime,
          );
        }
      } catch (e) {
        debugPrint('Failed to send permission approval push notification: $e');
      }
    }
  }

  Future<void> rejectPermissionRequest(
      String requestId, String managerName, String rejectionReason) async {
    await _firestore.collection('permission_requests').doc(requestId).update({
      'status': 'rejected',
      'rejectionReason': rejectionReason,
      'respondedAt': Timestamp.fromDate(DateTime.now()),
      'respondedBy': managerName,
    });

    final request =
        await _firestore.collection('permission_requests').doc(requestId).get();
    final data = request.data();
    if (data != null) {
      final employeeId = data['employeeId'] as String? ?? '';
      await _createPermissionNotification(
        employeeId: employeeId,
        employeeName: data['employeeName'] as String? ?? 'Staff',
        department: data['department'] as String? ?? '',
        managerName: managerName,
        content:
            '${data['employeeName'] ?? 'Staff'} permission request was rejected.',
        status: 'rejected',
      );

      // Trigger push notification back to the staff member
      try {
        final sent =
            await NotificationService().sendPermissionDecisionNotification(
          identifier: employeeId,
          approved: false,
        );
        final userId = data['userId']?.toString().trim() ?? '';
        if (!sent && userId.isNotEmpty && userId != employeeId.trim()) {
          await NotificationService().sendPermissionDecisionNotification(
            identifier: userId,
            approved: false,
          );
        }
      } catch (e) {
        debugPrint('Failed to send permission rejection push notification: $e');
      }
    }
  }

  // ─── Stats ─────────────────────────────────────────────────────────────────

  Stream<Map<String, int>> getApprovalStatsByManager(String managerName) {
    return getPermissionRequestsForManager(managerName).map((requests) {
      int pending = 0, approved = 0, rejected = 0;
      for (final r in requests) {
        switch (r.status) {
          case 'pending':
            pending++;
            break;
          case 'approved':
            approved++;
            break;
          case 'rejected':
            rejected++;
            break;
        }
      }
      return {'pending': pending, 'approved': approved, 'rejected': rejected};
    });
  }

  // ─── Active permission for checkout flow ──────────────────────────────────

  Future<PermissionRequest?> getActiveApprovedPermission(
      String employeeId) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    // Keep this checkout validation index-free. Combining employeeId, status,
    // returnedToOffice and requestedAt requires a composite index; this screen
    // should return our validation message instead of a Firebase index error.
    final snap = await _firestore
        .collection('permission_requests')
        .where('employeeId', isEqualTo: employeeId)
        .get();

    if (snap.docs.isEmpty) return null;

    final requests =
        snap.docs.map((d) => PermissionRequest.fromFirestore(d)).where((req) {
      if (req.status != 'approved') return false;
      if (req.returnedToOffice) return false;
      if (req.requestedAt.isBefore(startOfToday)) return false;
      return true;
    }).toList()
          ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

    for (final req in requests) {
      if (req.returnTime == null || req.returnTime!.isAfter(now)) return req;
    }
    return null;
  }

  Future<PermissionRequest?> getOpenApprovedPermission(
      String employeeId) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final snap = await _firestore
        .collection('permission_requests')
        .where('employeeId', isEqualTo: employeeId)
        .get();

    if (snap.docs.isEmpty) return null;

    final requests =
        snap.docs.map((d) => PermissionRequest.fromFirestore(d)).where((req) {
      if (req.status != 'approved') return false;
      if (req.returnedToOffice) return false;
      if (req.requestedAt.isBefore(startOfToday)) return false;
      return true;
    }).toList()
          ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

    return requests.isEmpty ? null : requests.first;
  }

  Future<void> _createPermissionNotification({
    required String employeeId,
    required String employeeName,
    required String department,
    required String managerName,
    required String content,
    required String status,
  }) async {
    final recipients = <String>{
      'Admin',
      employeeId,
      if (managerName.trim().isNotEmpty) managerName.trim(),
    };

    for (final recipient in recipients) {
      await _firestore.collection('notifications').add({
        'recipient': recipient,
        'type': 'Permission',
        'content': content,
        'status': 'Sent',
        'suppressFirestorePush': true,
        'allowFirestorePush': false,
        'timestamp': FieldValue.serverTimestamp(),
        'employeeId': employeeId,
        'employeeName': employeeName,
        'department': department,
        'managerName': managerName,
        'permissionStatus': status,
      });
    }
  }

  String _formatTime(DateTime value) {
    final ist = value.toUtc().add(const Duration(hours: 5, minutes: 30));
    final period = ist.hour >= 12 ? 'PM' : 'AM';
    final hour = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:'
        '${ist.minute.toString().padLeft(2, '0')} $period';
  }
}
