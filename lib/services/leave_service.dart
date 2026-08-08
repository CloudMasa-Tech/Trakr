import 'package:flutter/foundation.dart';
// lib/services/leave_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/leave_request.dart';
import 'attendance_service.dart';
import 'notification_service.dart';

class LeaveService {
  LeaveService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  FirebaseAuth get _auth => _context.auth;

  static const int monthlyLeaveAllowance = 1;

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  bool _isHalfDayLeave(String type) => type.toLowerCase().contains('half');

  Future<_WorkCalendarPolicy> _loadWorkCalendarPolicy() async {
    final doc = await _firestore.collection('geo_config').doc('default').get();
    if (!doc.exists) return const _WorkCalendarPolicy();

    final data = doc.data() ?? {};
    return _WorkCalendarPolicy.fromMap(data);
  }

  double _calculateWorkingLeaveDays(
    String type,
    DateTime start,
    DateTime end,
    _WorkCalendarPolicy policy,
  ) {
    if (end.isBefore(start)) return 0;

    var workingDays = 0;
    var current = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);

    while (!current.isAfter(last)) {
      if (policy.isWorkingDay(current, _dateKey)) {
        workingDays++;
      }
      current = current.add(const Duration(days: 1));
    }

    return _isHalfDayLeave(type) ? workingDays * 0.5 : workingDays.toDouble();
  }

  String _notificationLeaveDurationFromDays(String type, double days) {
    if (_isHalfDayLeave(type)) {
      if (days <= 0.5) return 'Half Day';
      return '${formatLeaveDays(days)} Days';
    }
    return days <= 1 ? 'Full Day' : '${formatLeaveDays(days)} Days';
  }

  String formatLeaveDays(num days) {
    final value = days.toDouble();
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }

  Future<double> _usedUnpaidLeaveDaysForMonth({
    required String userId,
    required DateTime monthDate,
  }) async {
    final startOfMonth = DateTime(monthDate.year, monthDate.month, 1);
    final endOfMonth = DateTime(monthDate.year, monthDate.month + 1, 1);
    final snapshot = await _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .get();

    var total = 0.0;
    for (final doc in snapshot.docs) {
      final request = LeaveRequest.fromFirestore(doc.data(), doc.id);
      if (request.status == 'rejected') continue;
      if (request.endDate.isBefore(startOfMonth) ||
          !request.startDate.isBefore(endOfMonth)) {
        continue;
      }
      total += request.unpaidDayCount;
    }
    return total;
  }

  ({bool isPaid, double paidDays, double unpaidDays}) _paySplitForRequest({
    required double requestedDays,
    required double usedUnpaidDays,
  }) {
    final remainingUnpaid = (monthlyLeaveAllowance - usedUnpaidDays)
        .clamp(0, monthlyLeaveAllowance);
    final unpaidDays = requestedDays < remainingUnpaid
        ? requestedDays
        : remainingUnpaid.toDouble();
    final paidDays = requestedDays - unpaidDays;
    return (
      isPaid: paidDays > 0 && unpaidDays == 0,
      paidDays: paidDays,
      unpaidDays: unpaidDays,
    );
  }

  String _normalizeIdentity(String value) {
    return value.trim().toLowerCase();
  }

  Set<String> _managerAliases(String managerName) {
    final aliases = <String>{};

    void addAlias(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      aliases.add(_normalizeIdentity(trimmed));
      aliases.add(_normalizeIdentity(trimmed.replaceAll(' ', '')));
      if (trimmed.contains('@')) {
        aliases.add(_normalizeIdentity(trimmed.split('@').first));
      }
    }

    final user = _auth.currentUser;
    addAlias(managerName);
    addAlias(user?.uid);
    addAlias(user?.displayName);
    addAlias(user?.email);
    return aliases;
  }

  bool _matchesManagerAlias(String? managerValue, Set<String> managerAliases) {
    if (managerValue == null || managerValue.trim().isEmpty) return false;
    final normalized = _normalizeIdentity(managerValue);
    final compact = _normalizeIdentity(managerValue.replaceAll(' ', ''));

    // Check direct matches
    if (managerAliases.contains(normalized) ||
        managerAliases.contains(compact)) {
      return true;
    }

    // Check if the value is an email and we have the local part in aliases
    if (normalized.contains('@')) {
      final localPart = _normalizeIdentity(normalized.split('@').first);
      if (managerAliases.contains(localPart)) return true;
    }

    return false;
  }

  Set<String> _aliasesFromStaffRecord(
    Map<String, dynamic> record, {
    String? docId,
  }) {
    final aliases = <String>{};

    void addAlias(String? value) {
      if (value == null) return;
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      aliases.add(_normalizeIdentity(trimmed));
      aliases.add(_normalizeIdentity(trimmed.replaceAll(' ', '')));
      if (trimmed.contains('@')) {
        aliases.add(_normalizeIdentity(trimmed.split('@').first));
      }
    }

    addAlias(docId);
    addAlias(record['name']?.toString());
    addAlias(record['email']?.toString());
    addAlias(record['employeeId']?.toString());
    return aliases;
  }

  Future<Map<String, dynamic>?> _findStaffRecordByIdentity(
      String identity) async {
    final normalizedIdentity = _normalizeIdentity(identity);
    if (normalizedIdentity.isEmpty) {
      return null;
    }

    final byDocId =
        await _firestore.collection('staff').doc(identity.trim()).get();
    if (byDocId.exists) {
      return {
        ...byDocId.data()!,
        '_docId': byDocId.id,
      };
    }

    final candidateLookups = await Future.wait([
      _firestore
          .collection('staff')
          .where('employeeId', isEqualTo: identity.trim())
          .limit(1)
          .get(),
      _firestore
          .collection('staff')
          .where('name', isEqualTo: identity.trim())
          .limit(1)
          .get(),
      _firestore
          .collection('staff')
          .where('email', isEqualTo: identity.trim())
          .limit(1)
          .get(),
    ]);

    for (final snapshot in candidateLookups) {
      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return {
          ...doc.data(),
          '_docId': doc.id,
        };
      }
    }

    final allStaff = await _firestore.collection('staff').get();
    for (final doc in allStaff.docs) {
      final data = doc.data();
      final aliases = _aliasesFromStaffRecord(data, docId: doc.id);
      if (aliases.contains(normalizedIdentity)) {
        return {
          ...data,
          '_docId': doc.id,
        };
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _getStaffRecordForUser(String userId) async {
    final byDocId = await _firestore.collection('staff').doc(userId).get();
    if (byDocId.exists) {
      return byDocId.data();
    }

    final byEmployeeId = await _firestore
        .collection('staff')
        .where('employeeId', isEqualTo: userId)
        .limit(1)
        .get();
    if (byEmployeeId.docs.isNotEmpty) {
      return byEmployeeId.docs.first.data();
    }

    final currentUser = _auth.currentUser;
    if (currentUser?.email != null && currentUser!.email!.isNotEmpty) {
      final byEmail = await _firestore
          .collection('staff')
          .where('email', isEqualTo: currentUser.email)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        return byEmail.docs.first.data();
      }
    }

    return null;
  }

  Stream<List<LeaveRequest>> getRequestsForManager(String managerName) {
    debugPrint(
        '🔍 DEBUG: LeaveService.getRequestsForManager - Called for: "$managerName"');

    // We use a StreamController to implement switchMap-like behavior manually
    final controller = StreamController<List<LeaveRequest>>.broadcast();
    StreamSubscription? staffSubscription;
    StreamSubscription? leaveSubscription;

    void cleanup() {
      staffSubscription?.cancel();
      leaveSubscription?.cancel();
    }

    staffSubscription =
        _teamUserIdsStreamForManager(managerName).listen((userIds) {
      debugPrint(
          '📊 DEBUG: LeaveService - Team updated for $managerName: $userIds');

      // Every time the team changes, we resubscribe to leave requests to use the new userIds
      leaveSubscription?.cancel();
      leaveSubscription = _firestore
          .collection('leave_requests')
          .snapshots()
          .asyncMap((snapshot) async {
        final managerAliases =
            await _resolveManagerAliasesThoroughly(managerName);
        final normalizedIds = userIds.map(_normalizeIdentity).toSet();

        debugPrint(
            '🛡️ DEBUG: LeaveService - Filtering ${snapshot.docs.length} total requests in database.');
        if (snapshot.docs.isEmpty) {
          debugPrint(
              '⚠️ WARNING: leave_requests collection is EMPTY in Firestore!');
        }

        final requests = snapshot.docs
            .map((doc) {
              final data = doc.data();
              debugPrint(
                  '   📄 Checking Request ${doc.id}: From="${data['userName']}" AssignedTo="${data['managerName']}" StaffID="${data['userId']}"');
              try {
                return LeaveRequest.fromFirestore(data, doc.id);
              } catch (e) {
                debugPrint(
                    '⚠️ ERROR: Failed to parse LeaveRequest ${doc.id}: $e');
                return null;
              }
            })
            .where((request) {
              if (request == null) return false;

              final requestManager =
                  _normalizeIdentity(request.managerName ?? '');
              final requestManagerCompact = _normalizeIdentity(
                  (request.managerName ?? '').replaceAll(' ', ''));
              final requestUserId = _normalizeIdentity(request.userId);
              final requestEmployeeId =
                  _normalizeIdentity(request.employeeId ?? '');

              bool isMatch = false;

              // 1. Direct Manager Name Match
              if (requestManager.isNotEmpty &&
                  (managerAliases.contains(requestManager) ||
                      managerAliases.contains(requestManagerCompact))) {
                isMatch = true;
              }

              // 2. Team Member Match (by UID or Employee ID)
              if (!isMatch &&
                  (normalizedIds.contains(requestUserId) ||
                      (requestEmployeeId.isNotEmpty &&
                          normalizedIds.contains(requestEmployeeId)))) {
                isMatch = true;
              }

              // 3. Direct Manager Identity Match (if UID/Email stored as managerName)
              if (!isMatch && managerAliases.contains(requestUserId)) {
                isMatch = true;
              }

              if (isMatch) {
                debugPrint(
                    '   ✅ Match: Request from ${request.userName} (ID: ${request.userId}) matches $managerName');
              } else {
                // Optional: very verbose logging for non-matches during debugging
                // debugPrint('   ❌ No match: Request from ${request.userName} assigned to "${request.managerName}" does not match $managerName');
              }
              return isMatch;
            })
            .whereType<LeaveRequest>()
            .toList();

        debugPrint(
            '📈 DEBUG: LeaveService - Emitting ${requests.length} requests');
        return requests;
      }).listen((data) {
        if (!controller.isClosed) controller.add(data);
      }, onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      });
    }, onError: (err) {
      if (!controller.isClosed) controller.addError(err);
    });

    controller.onCancel = cleanup;
    return controller.stream;
  }

  Future<Set<String>> _resolveManagerAliasesThoroughly(
      String managerName) async {
    final aliases = _managerAliases(managerName);

    // 1. Check Managers Collection
    try {
      final managersSnap = await _firestore.collection('managers').get();
      for (final doc in managersSnap.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim();
        final email = (data['email'] as String? ?? '').trim();

        final docAliases = <String>{};
        if (name.isNotEmpty) docAliases.add(_normalizeIdentity(name));
        if (email.isNotEmpty) {
          docAliases.add(_normalizeIdentity(email));
          docAliases.add(_normalizeIdentity(email.split('@').first));
        }
        docAliases.add(_normalizeIdentity(doc.id));

        if (docAliases.any((a) => aliases.contains(a))) {
          aliases.addAll(docAliases);
        }
      }
    } catch (_) {}

    // 2. Check Staff Collection
    try {
      final staffSnap = await _firestore.collection('staff').get();
      for (final doc in staffSnap.docs) {
        final data = doc.data();
        final name = (data['name'] as String? ?? '').trim();
        final email = (data['email'] as String? ?? '').trim();
        final empId = (data['employeeId'] as String? ?? '').trim();

        final docAliases = <String>{};
        if (name.isNotEmpty) docAliases.add(_normalizeIdentity(name));
        if (email.isNotEmpty) {
          docAliases.add(_normalizeIdentity(email));
          docAliases.add(_normalizeIdentity(email.split('@').first));
        }
        if (empId.isNotEmpty) docAliases.add(_normalizeIdentity(empId));
        docAliases.add(_normalizeIdentity(doc.id));

        if (docAliases.any((a) => aliases.contains(a))) {
          aliases.addAll(docAliases);
        }
      }
    } catch (_) {}

    return aliases;
  }

  Stream<List<String>> _teamUserIdsStreamForManager(String managerName) {
    debugPrint(
        '🔍 DEBUG: LeaveService._teamUserIdsStreamForManager - Finding team for manager: "$managerName"');
    return _firestore
        .collection('staff')
        .snapshots()
        .asyncMap((snapshot) async {
      final managerAliases =
          await _resolveManagerAliasesThoroughly(managerName);
      final ids = <String>{};

      debugPrint(
          '🛡️ DEBUG: LeaveService._team - Manager aliases: $managerAliases');

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final reportsTo = data['reportsTo']?.toString() ?? '';
        if (reportsTo.isEmpty) continue;

        final normalizedReportsTo = _normalizeIdentity(reportsTo);
        final normalizedReportsToCompact =
            _normalizeIdentity(reportsTo.replaceAll(' ', ''));

        final matchesManager = managerAliases.contains(normalizedReportsTo) ||
            managerAliases.contains(normalizedReportsToCompact);

        if (!matchesManager) continue;

        final staffName = data['name']?.toString() ?? 'Unknown';
        debugPrint(
            '   ✓ Team member identified: $staffName reports to $managerName');

        final employeeId = data['employeeId']?.toString();
        if (employeeId != null && employeeId.trim().isNotEmpty) {
          ids.add(employeeId.trim());
        }
        final docId = doc.id.trim();
        if (docId.isNotEmpty) {
          ids.add(docId);
        }
      }
      return ids.toList();
    });
  }

  // Stream to listen for ONLY pending requests
  Stream<List<LeaveRequest>> getPendingRequests() {
    return _firestore
        .collection('leave_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
          .toList();
      requests.sort((a, b) => a.startDate.compareTo(b.startDate));
      return requests;
    });
  }

  Stream<List<LeaveRequest>> getRequestsForUser(String userId,
      {int limit = 10}) {
    return _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
          .toList();
      requests.sort((a, b) => b.startDate.compareTo(a.startDate));
      if (requests.length > limit) {
        return requests.take(limit).toList();
      }
      return requests;
    });
  }

  Stream<List<LeaveRequest>> getHistoryForUser(String userId, {int limit = 6}) {
    return getRequestsForUser(userId, limit: limit);
  }

  Stream<LeaveBalanceSummary> getLeaveBalanceSummary(String userId) {
    return _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      var approvedDays = 0.0;
      var pendingDays = 0.0;

      for (final doc in snapshot.docs) {
        final request = LeaveRequest.fromFirestore(doc.data(), doc.id);
        final sameMonth = request.startDate.year == now.year &&
            request.startDate.month == now.month;
        if (!sameMonth) continue;

        final days = request.leaveDayCount;
        if (request.status == 'approved') {
          approvedDays += days;
        } else if (request.status == 'pending') {
          pendingDays += days;
        }
      }

      final usedUnpaid = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
          .where((request) =>
              request.startDate.year == now.year &&
              request.startDate.month == now.month &&
              request.status != 'rejected')
          .fold<double>(0, (total, request) => total + request.unpaidDayCount);
      final remaining = (monthlyLeaveAllowance - usedUnpaid)
          .clamp(0, monthlyLeaveAllowance)
          .toDouble();
      return LeaveBalanceSummary(
        monthlyAllowance: monthlyLeaveAllowance,
        approvedDays: approvedDays,
        pendingDays: pendingDays,
        remainingDays: remaining,
      );
    });
  }

  Future<List<LeaveRequest>> getRequestsForUserOnce(String userId,
      {int limit = 10}) async {
    final snapshot = await _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .get();
    final requests = snapshot.docs
        .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
        .toList();
    requests.sort((a, b) => b.startDate.compareTo(a.startDate));
    if (requests.length > limit) {
      return requests.take(limit).toList();
    }
    return requests;
  }

  Future<LeaveBalanceSummary> getLeaveBalanceSummaryOnce(String userId) async {
    final snapshot = await _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .get();
    final now = DateTime.now();
    var approvedDays = 0.0;
    var pendingDays = 0.0;
    var usedUnpaid = 0.0;

    for (final doc in snapshot.docs) {
      final request = LeaveRequest.fromFirestore(doc.data(), doc.id);
      final sameMonth = request.startDate.year == now.year &&
          request.startDate.month == now.month;
      if (!sameMonth) continue;

      final days = request.leaveDayCount;
      if (request.status == 'approved') {
        approvedDays += days;
      } else if (request.status == 'pending') {
        pendingDays += days;
      }
      if (request.status != 'rejected') {
        usedUnpaid += request.unpaidDayCount;
      }
    }

    final remaining = (monthlyLeaveAllowance - usedUnpaid)
        .clamp(0, monthlyLeaveAllowance)
        .toDouble();
    return LeaveBalanceSummary(
      monthlyAllowance: monthlyLeaveAllowance,
      approvedDays: approvedDays,
      pendingDays: pendingDays,
      remainingDays: remaining,
    );
  }

  Stream<Map<String, int>> getApprovalStats() {
    return _firestore.collection('leave_requests').snapshots().map((snapshot) {
      final now = DateTime.now();
      var pending = 0;
      var approvedToday = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] as String? ?? 'pending';
        if (status == 'pending') pending++;
        if (status == 'approved') {
          final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();
          if (updatedAt != null &&
              updatedAt.year == now.year &&
              updatedAt.month == now.month &&
              updatedAt.day == now.day) {
            approvedToday++;
          }
        }
      }
      return {
        'pending': pending,
        'approvedToday': approvedToday,
      };
    });
  }

  Stream<Map<String, int>> getApprovalStatsByManager(String managerName) {
    return getRequestsForManager(managerName).map((requests) {
      var pending = 0;
      var approved = 0;
      var approvedToday = 0;
      final now = DateTime.now();
      for (final request in requests) {
        if (request.status == 'pending') {
          pending++;
        } else if (request.status == 'approved') {
          approved++;
          final decisionDate =
              request.respondedAt ?? request.updatedAt ?? request.createdAt;
          if (decisionDate != null &&
              decisionDate.year == now.year &&
              decisionDate.month == now.month &&
              decisionDate.day == now.day) {
            approvedToday++;
          }
        }
      }
      return {
        'pending': pending,
        'approved': approved,
        'approvedToday': approvedToday,
      };
    });
  }

  Stream<List<LeaveRequest>> getPendingRequestsByManager(String managerName) {
    return getRequestsForManager(managerName).map((requests) {
      final pending =
          requests.where((request) => request.status == 'pending').toList();
      pending.sort((a, b) => a.startDate.compareTo(b.startDate));
      return pending;
    });
  }

  Stream<List<LeaveRequest>> getApprovedRequestsByManager(
    String managerName, {
    int limit = 20,
  }) {
    return getRequestsForManager(managerName).map((requests) {
      final approved =
          requests.where((request) => request.status == 'approved').toList();
      approved.sort((a, b) {
        final aDate = a.updatedAt ?? a.createdAt ?? a.startDate;
        final bDate = b.updatedAt ?? b.createdAt ?? b.startDate;
        return bDate.compareTo(aDate);
      });
      if (approved.length > limit) {
        return approved.take(limit).toList();
      }
      return approved;
    });
  }

  Stream<List<LeaveRequest>> getDecisionHistoryByManager(
    String managerName, {
    int limit = 20,
  }) {
    return getRequestsForManager(managerName).map((requests) {
      final history = requests
          .where(
            (request) =>
                request.status == 'approved' || request.status == 'rejected',
          )
          .toList();
      history.sort((a, b) {
        final aDate =
            a.respondedAt ?? a.updatedAt ?? a.createdAt ?? a.startDate;
        final bDate =
            b.respondedAt ?? b.updatedAt ?? b.createdAt ?? b.startDate;
        return bDate.compareTo(aDate);
      });
      if (history.length > limit) {
        return history.take(limit).toList();
      }
      return history;
    });
  }

  /// Public method to validate if a manager exists (for UI feedback)
  Future<bool> validateManagerForLeave(String managerName) async {
    try {
      await _validateManagerExists(managerName);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Validates that a manager name exists and is valid
  /// Throws exception if validation fails
  Future<String> _validateManagerExists(String managerName) async {
    if (managerName.trim().isEmpty) {
      throw Exception('Manager name is required.');
    }

    // First, try to find manager in the managers collection
    try {
      // Search by document ID
      final managerDocById =
          await _firestore.collection('managers').doc(managerName.trim()).get();
      if (managerDocById.exists) {
        final canonicalName =
            managerDocById.data()?['name']?.toString().trim() ?? '';
        return canonicalName.isNotEmpty ? canonicalName : managerName.trim();
      }

      // Search by name field
      final managerByName = await _firestore
          .collection('managers')
          .where('name', isEqualTo: managerName.trim())
          .limit(1)
          .get();

      if (managerByName.docs.isNotEmpty) {
        final canonicalName =
            managerByName.docs.first.data()['name']?.toString().trim() ?? '';
        return canonicalName.isNotEmpty ? canonicalName : managerName.trim();
      }

      // Search by email field
      final managerByEmail = await _firestore
          .collection('managers')
          .where('email', isEqualTo: managerName.trim())
          .limit(1)
          .get();

      if (managerByEmail.docs.isNotEmpty) {
        final canonicalName =
            managerByEmail.docs.first.data()['name']?.toString().trim() ?? '';
        return canonicalName.isNotEmpty ? canonicalName : managerName.trim();
      }
    } catch (e) {
      // Continue to staff collection search
    }

    // Fallback: try to find manager in staff collection
    final managerRecord = await _findStaffRecordByIdentity(managerName);
    if (managerRecord == null) {
      throw Exception(
        'Manager "$managerName" not found. Please ensure your manager is registered in the system.',
      );
    }

    final canonicalName = managerRecord['name']?.toString().trim() ?? '';
    return canonicalName.isNotEmpty ? canonicalName : managerName.trim();
  }

  /// Validates all leave request criteria
  /// Returns validation error message or empty string if valid
  Future<String> _validateLeaveRequest({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required String managerName,
    required String reason,
    int advanceNoticeHours = 8,
  }) async {
    // Validate reason
    if (reason.trim().isEmpty) {
      return 'Please provide a reason for your leave request.';
    }

    // Validate dates
    if (endDate.isBefore(startDate)) {
      return 'End date cannot be before start date.';
    }

    // Leave requests must be submitted before office start on the first leave day.
    final officeStart =
        DateTime(startDate.year, startDate.month, startDate.day, 10, 0);
    if (!DateTime.now().isBefore(officeStart)) {
      return 'Leave must be applied before office start time (10:00 AM) on the start date.';
    }

    // Validate manager is assigned
    if (managerName.trim().isEmpty) {
      return 'No manager is assigned to your staff profile. Please contact admin.';
    }

    // Check for overlaps
    final existing = await _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .get();

    final hasOverlap = existing.docs.any((doc) {
      final request = LeaveRequest.fromFirestore(doc.data(), doc.id);
      if (request.status != 'approved' && request.status != 'pending') {
        return false;
      }
      return !request.endDate.isBefore(startDate) &&
          !request.startDate.isAfter(endDate);
    });

    if (hasOverlap) {
      return 'You already have an approved or pending leave request for the selected date range.';
    }

    return ''; // All validations passed
  }

  Future<void> submitLeaveRequest({
    required String userId,
    required String userName,
    String? userPhotoUrl,
    required String department,
    required String type,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    int advanceNoticeHours = 8,
  }) async {
    // Get staff record
    final staffRecord = await _getStaffRecordForUser(userId);
    if (staffRecord == null) {
      throw Exception(
        'Your staff record was not found. Please contact admin before applying for leave.',
      );
    }

    // Get and validate manager
    final assignedManager = staffRecord['reportsTo']?.toString().trim() ?? '';
    if (assignedManager.isEmpty) {
      throw Exception(
        'No manager is assigned to your staff profile. Please contact admin to assign a manager.',
      );
    }

    // Validate manager exists
    final managerName = await _validateManagerExists(assignedManager);

    // Enforce valid types
    if (type != 'Sick Leave' &&
        type != 'Casual Leave' &&
        type != 'Half Day Leave') {
      throw Exception(
          'Invalid leave type. Allowed types are: Sick Leave, Casual Leave, Half Day Leave.');
    }

    // Perform comprehensive validation
    final validationError = await _validateLeaveRequest(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      managerName: managerName,
      reason: reason.trim(),
      advanceNoticeHours: advanceNoticeHours,
    );

    if (validationError.isNotEmpty) {
      throw Exception(validationError);
    }

    // Get employee ID
    final employeeId =
        staffRecord['employeeId']?.toString().trim().isNotEmpty == true
            ? staffRecord['employeeId'].toString().trim()
            : userId;

    final calendarPolicy = await _loadWorkCalendarPolicy();
    final requestedDays = _calculateWorkingLeaveDays(
      type,
      startDate,
      endDate,
      calendarPolicy,
    );
    if (requestedDays <= 0) {
      throw Exception(
        'The selected date range only contains holidays or non-working weekend days. No leave is required for those dates.',
      );
    }
    final paySplit = _paySplitForRequest(
      requestedDays: requestedDays,
      usedUnpaidDays: await _usedUnpaidLeaveDaysForMonth(
        userId: userId,
        monthDate: startDate,
      ),
    );

    // Create leave request
    final request = LeaveRequest(
      id: '',
      userId: userId,
      employeeId: employeeId,
      userName: staffRecord['name']?.toString().trim().isNotEmpty == true
          ? staffRecord['name'].toString().trim()
          : userName,
      userPhotoUrl: userPhotoUrl,
      managerName: managerName,
      type: type,
      department:
          staffRecord['department']?.toString().trim().isNotEmpty == true
              ? staffRecord['department'].toString().trim()
              : department,
      startDate: startDate,
      endDate: endDate,
      status: 'pending',
      reason: reason.trim(),
      createdAt: DateTime.now(),
      isPaid: paySplit.isPaid,
      leaveDayCount: requestedDays,
      paidDayCount: paySplit.paidDays,
      unpaidDayCount: paySplit.unpaidDays,
    );

    // Submit to Firestore
    final requestRef =
        await _firestore.collection('leave_requests').add(request.toMap());

    // Employee leave approval is owned by the assigned manager.
    try {
      await NotificationService().sendLeaveRequestNotification(
        recipient: managerName,
        requestId: requestRef.id,
        employeeId: employeeId,
        employeeName: request.userName,
        leaveType: type,
        startsOn: DateFormat('MMM dd').format(startDate),
        leaveDuration: _notificationLeaveDurationFromDays(type, requestedDays),
        toAdmin: false,
      );
    } catch (e) {
      debugPrint('Failed to send leave request push notification: $e');
    }
  }

  Future<void> submitManagerLeaveRequest({
    required String userId,
    required String userName,
    String? userPhotoUrl,
    required String department,
    required String type,
    required DateTime startDate,
    required DateTime endDate,
    required String reason,
    required String employeeId,
  }) async {
    // Enforce valid types
    if (type != 'Sick Leave' &&
        type != 'Casual Leave' &&
        type != 'Half Day Leave') {
      throw Exception(
          'Invalid leave type. Allowed types are: Sick Leave, Casual Leave, Half Day Leave.');
    }

    final validationError = await _validateLeaveRequest(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      managerName: 'Admin',
      reason: reason.trim(),
    );

    if (validationError.isNotEmpty) {
      throw Exception(validationError);
    }

    final calendarPolicy = await _loadWorkCalendarPolicy();
    final requestedDays = _calculateWorkingLeaveDays(
      type,
      startDate,
      endDate,
      calendarPolicy,
    );
    if (requestedDays <= 0) {
      throw Exception(
        'The selected date range only contains holidays or non-working weekend days. No leave is required for those dates.',
      );
    }
    final paySplit = _paySplitForRequest(
      requestedDays: requestedDays,
      usedUnpaidDays: await _usedUnpaidLeaveDaysForMonth(
        userId: userId,
        monthDate: startDate,
      ),
    );

    // Create leave request
    final request = LeaveRequest(
      id: '',
      userId: userId,
      employeeId: employeeId,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      managerName: 'Admin',
      type: type,
      department: department,
      startDate: startDate,
      endDate: endDate,
      status: 'pending',
      reason: reason.trim(),
      createdAt: DateTime.now(),
      isPaid: paySplit.isPaid,
      leaveDayCount: requestedDays,
      paidDayCount: paySplit.paidDays,
      unpaidDayCount: paySplit.unpaidDays,
    );

    // Convert to map and inject 'isManager: true'
    final map = request.toMap();
    map['isManager'] = true;

    // Submit to Firestore
    final requestRef = await _firestore.collection('leave_requests').add(map);

    // Trigger push notification to Admin
    try {
      await NotificationService().sendLeaveRequestNotification(
        recipient: 'Admin',
        requestId: requestRef.id,
        employeeId: employeeId,
        employeeName: userName,
        leaveType: type,
        startsOn: DateFormat('MMM dd').format(startDate),
        leaveDuration: _notificationLeaveDurationFromDays(type, requestedDays),
        toAdmin: true,
      );
    } catch (e) {
      debugPrint('Failed to send admin push notification: $e');
    }
  }

  /// Validates manager identity and approval permissions
  /// Throws exception if manager is not authorized to approve this request
  Future<void> _validateManagerAuthorization(
      LeaveRequest request, String? actingManagerName,
      {required bool enforceAssignedManager}) async {
    final requestManager = request.managerName?.trim() ?? '';
    if (requestManager.isEmpty) {
      throw Exception(
        'Invalid leave request: No manager is assigned to this request.',
      );
    }

    if (enforceAssignedManager &&
        (actingManagerName == null || actingManagerName.trim().isEmpty)) {
      throw Exception(
        'Manager identity is required to approve or reject this leave request.',
      );
    }

    // If actingManagerName is provided, verify it matches the assigned manager
    if (actingManagerName != null && actingManagerName.trim().isNotEmpty) {
      final actingAliases = _managerAliases(actingManagerName);
      final actingRecord =
          await _findStaffRecordByIdentity(actingManagerName.trim());
      if (actingRecord != null) {
        actingAliases.addAll(
          _aliasesFromStaffRecord(
            actingRecord,
            docId: actingRecord['_docId']?.toString(),
          ),
        );
      }
      final isAuthorized = _matchesManagerAlias(requestManager, actingAliases);

      if (!isAuthorized) {
        throw Exception(
          'Authorization failed: This leave request is assigned to $requestManager. Only assigned managers can approve or reject requests.',
        );
      }
    }
  }

  /// Validates manager response reason
  /// Returns normalized reason or throws exception
  String _validateManagerResponse(String? reason, String action) {
    final normalized = (reason ?? '').trim();
    if (normalized.isEmpty) {
      throw Exception(
        'Please provide a detailed reason for $action this leave request.',
      );
    }
    if (normalized.length < 3) {
      throw Exception(
        'Reason must be at least 3 characters long.',
      );
    }
    return normalized;
  }

  Future<void> _syncApprovedLeaveToAttendance(LeaveRequest request) async {
    final employeeId = (request.employeeId?.trim().isNotEmpty == true
            ? request.employeeId
            : request.userId)
        ?.trim();
    if (employeeId == null || employeeId.isEmpty) return;

    final calendarPolicy = await _loadWorkCalendarPolicy();
    final isHalfDay = _isHalfDayLeave(request.type);
    final leaveKind = request.paidDayCount > 0 && request.unpaidDayCount > 0
        ? 'Mixed Leave'
        : request.isPaid
            ? 'Paid Leave'
            : 'Unpaid Leave';

    String? companyId;
    final staffSnap = await _firestore
        .collection('staff')
        .where('employeeId', isEqualTo: employeeId)
        .limit(1)
        .get();
    if (staffSnap.docs.isNotEmpty) {
      companyId = staffSnap.docs.first.data()['companyId'] as String?;
    } else {
      final userSnap =
          await _firestore.collection('users').doc(employeeId).get();
      companyId = userSnap.data()?['companyId'] as String?;
    }

    var current = DateTime(
      request.startDate.year,
      request.startDate.month,
      request.startDate.day,
    );
    final last = DateTime(
      request.endDate.year,
      request.endDate.month,
      request.endDate.day,
    );

    while (!current.isAfter(last)) {
      if (!calendarPolicy.isWorkingDay(current, _dateKey)) {
        current = current.add(const Duration(days: 1));
        continue;
      }

      final dateKey = _dateKey(current);
      final existing = await _firestore
          .collection('attendance')
          .where('employeeId', isEqualTo: employeeId)
          .where('dateKey', isEqualTo: dateKey)
          .limit(1)
          .get();

      final data = <String, dynamic>{
        'employeeId': employeeId,
        'employeeName': request.userName,
        'department': request.department,
        'date': Timestamp.fromDate(current),
        'dateKey': dateKey,
        'status': isHalfDay ? 'present' : 'absent',
        'checkInTime': null,
        'checkOutTime': null,
        'workingMinutes': 0,
        'workingHours': '00:00',
        'lateMinutes': 0,
        'arrivalBand': 'green',
        'isEarlyCheckout': false,
        'earlyCheckoutMinutes': 0,
        'latePendingMinutes': 0,
        'earlyCheckoutPendingMinutes': 0,
        'permissionPendingMinutes': 0,
        'pendingMinutes': isHalfDay ? 240 : 480,
        'pendingAbsenceStatus': isHalfDay ? 'half_absent' : 'full_absent',
        'policyAction': isHalfDay ? 'half_day_leave' : 'full_day_leave',
        'policyLabel': '${isHalfDay ? 'Half Day ' : ''}$leaveKind',
        'leaveRequestId': request.id,
        'leaveType': request.type,
        'leaveIsPaid': request.isPaid,
        'leavePaidDayCount': request.paidDayCount,
        'leaveUnpaidDayCount': request.unpaidDayCount,
        'currentState': 'NONE',
        'managerName': request.managerName ?? '',
        'companyId': companyId,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (existing.docs.isEmpty) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await _firestore.collection('attendance').add(data);
      } else {
        await existing.docs.first.reference.set(data, SetOptions(merge: true));
      }

      current = current.add(const Duration(days: 1));
    }
  }

  // Update status (Approve or Reject)
  Future<void> updateLeaveStatus(
    String id,
    String newStatus, {
    String? rejectionReason,
    String? managerResponseReason,
    String? actingManagerName,
    bool enforceAssignedManager = false,
  }) async {
    // Validate status
    if (newStatus != 'approved' && newStatus != 'rejected') {
      throw Exception(
          'Invalid leave status. Must be "approved" or "rejected".');
    }

    // Get the leave request
    final doc = await _firestore.collection('leave_requests').doc(id).get();
    if (!doc.exists) {
      throw Exception('Leave request not found.');
    }

    final current = LeaveRequest.fromFirestore(doc.data()!, doc.id);

    // Validate request is pending
    if (current.status != 'pending') {
      throw Exception(
        'Cannot update leave request: Current status is "${current.status}". Only pending requests can be approved or rejected.',
      );
    }

    // Validate manager authorization
    await _validateManagerAuthorization(
      current,
      actingManagerName,
      enforceAssignedManager: enforceAssignedManager,
    );

    // Validate and get manager response reason
    final action = newStatus == 'approved' ? 'approving' : 'rejecting';
    final reason = _validateManagerResponse(
      managerResponseReason ?? rejectionReason,
      action,
    );

    // Get responder identity
    final responder = actingManagerName?.trim().isNotEmpty == true
        ? actingManagerName!.trim()
        : _auth.currentUser?.displayName?.trim().isNotEmpty == true
            ? _auth.currentUser!.displayName!.trim()
            : _auth.currentUser?.email?.split('@').first ?? 'System';

    // Prepare update data
    final updateData = {
      'status': newStatus,
      'managerResponseReason': reason,
      'rejectionReason': newStatus == 'rejected' ? reason : null,
      'respondedBy': responder,
      'respondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Update in Firestore
    await _firestore.collection('leave_requests').doc(id).update(updateData);

    if (newStatus == 'approved') {
      await _syncApprovedLeaveToAttendance(
        LeaveRequest(
          id: current.id,
          userId: current.userId,
          employeeId: current.employeeId,
          userName: current.userName,
          userPhotoUrl: current.userPhotoUrl,
          managerName: current.managerName,
          type: current.type,
          department: current.department,
          startDate: current.startDate,
          endDate: current.endDate,
          status: newStatus,
          isPaid: current.isPaid,
          leaveDayCount: current.leaveDayCount,
          paidDayCount: current.paidDayCount,
          unpaidDayCount: current.unpaidDayCount,
          reason: current.reason,
          managerResponseReason: reason,
          respondedBy: responder,
          respondedAt: DateTime.now(),
          createdAt: current.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
      AttendanceService.clearLeaveCache();
    }

    // Trigger push notification back to the staff member
    try {
      final sent = await NotificationService().sendLeaveDecisionNotification(
        identifier: current.userId,
        approved: newStatus.toLowerCase() == 'approved',
        requestId: id,
        employeeName: current.userName,
        managerName: responder,
      );
      final employeeId = current.employeeId?.trim() ?? '';
      if (!sent &&
          employeeId.isNotEmpty &&
          employeeId != current.userId.trim()) {
        await NotificationService().sendLeaveDecisionNotification(
          identifier: employeeId,
          approved: newStatus.toLowerCase() == 'approved',
          requestId: id,
          employeeName: current.userName,
          managerName: responder,
        );
      }
    } catch (e) {
      debugPrint('Failed to send staff leave update push notification: $e');
    }
  }

  // Get requests for a specific user with filters
  Stream<List<LeaveRequest>> getRequestsForUserWithStatus(
    String userId, {
    String? status,
    int limit = 10,
  }) {
    Query query = _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId);

    if (status != null) {
      query = query.where('status', isEqualTo: status);
    }

    return query.snapshots().map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(
              doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      requests.sort((a, b) => b.startDate.compareTo(a.startDate));
      if (requests.length > limit) {
        return requests.take(limit).toList();
      }
      return requests;
    });
  }

  /// Get a specific leave request with all details
  /// Useful for staff to view their request status and manager's decision
  Future<LeaveRequest?> getLeaveRequestById(String requestId) async {
    try {
      final doc =
          await _firestore.collection('leave_requests').doc(requestId).get();
      if (!doc.exists) {
        return null;
      }
      return LeaveRequest.fromFirestore(doc.data()!, doc.id);
    } catch (e) {
      return null;
    }
  }

  /// Get all responses (approved/rejected) for a user with manager details
  /// This is used by staff to see manager decisions
  Stream<List<LeaveRequest>> getLeaveResponsesForUser(
    String userId, {
    int limit = 20,
  }) {
    return _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .where('status', whereIn: ['approved', 'rejected'])
        .snapshots()
        .map((snapshot) {
          final requests = snapshot.docs
              .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
              .toList();
          // Sort by most recent responses first
          requests.sort((a, b) {
            final aDate =
                a.respondedAt ?? a.updatedAt ?? a.createdAt ?? a.startDate;
            final bDate =
                b.respondedAt ?? b.updatedAt ?? b.createdAt ?? b.startDate;
            return bDate.compareTo(aDate);
          });
          if (requests.length > limit) {
            return requests.take(limit).toList();
          }
          return requests;
        });
  }

  /// Get pending leave requests for a specific user
  /// Useful for staff to see their submitted requests waiting for manager
  Stream<List<LeaveRequest>> getPendingRequestsForUser(String userId) {
    return _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
          .toList();
      // Sort by start date (earliest first)
      requests.sort((a, b) => a.startDate.compareTo(b.startDate));
      return requests;
    });
  }

  /// Get all leave requests with detailed status information
  /// Combines pending, approved, and rejected requests
  Stream<List<LeaveRequest>> getAllLeaveRequestsForUser(
    String userId, {
    int limit = 30,
  }) {
    return _firestore
        .collection('leave_requests')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
          .toList();
      // Sort by most recent first
      requests.sort((a, b) {
        final aDate =
            a.respondedAt ?? a.updatedAt ?? a.createdAt ?? a.startDate;
        final bDate =
            b.respondedAt ?? b.updatedAt ?? b.createdAt ?? b.startDate;
        return bDate.compareTo(aDate);
      });
      if (requests.length > limit) {
        return requests.take(limit).toList();
      }
      return requests;
    });
  }

  /// Verify that a leave request was properly routed to the user's manager
  /// Returns true if the request's manager matches the staff's assigned manager
  Future<bool> isLeaveRequestRoutedCorrectly(
    String userId,
    String requestId,
  ) async {
    try {
      // Get the leave request
      final reqDoc =
          await _firestore.collection('leave_requests').doc(requestId).get();
      if (!reqDoc.exists) {
        return false;
      }
      final request = LeaveRequest.fromFirestore(reqDoc.data()!, requestId);

      // Get the staff record
      final staffRecord = await _getStaffRecordForUser(userId);
      if (staffRecord == null) {
        return false;
      }

      final assignedManager = staffRecord['reportsTo']?.toString().trim() ?? '';
      final requestManager = request.managerName?.toString().trim() ?? '';

      return assignedManager.toLowerCase() == requestManager.toLowerCase();
    } catch (e) {
      return false;
    }
  }

  /// Get manager information for a specific leave request
  /// Returns manager's staff record details
  Future<Map<String, dynamic>?> getLeaveRequestManagerInfo(
    String requestId,
  ) async {
    try {
      final doc =
          await _firestore.collection('leave_requests').doc(requestId).get();
      if (!doc.exists) {
        return null;
      }

      final request = LeaveRequest.fromFirestore(doc.data()!, requestId);
      final managerName = request.managerName?.trim();

      if (managerName == null || managerName.isEmpty) {
        return null;
      }

      // Try to find manager in staff collection
      final managerDoc =
          await _firestore.collection('staff').doc(managerName).get();
      if (managerDoc.exists) {
        return managerDoc.data();
      }

      // Try to find by name field
      final nameQuery = await _firestore
          .collection('staff')
          .where('name', isEqualTo: managerName)
          .limit(1)
          .get();

      if (nameQuery.docs.isNotEmpty) {
        return nameQuery.docs.first.data();
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Get pending leave requests for a team (list of user IDs)
  Stream<List<LeaveRequest>> getPendingRequestsForTeam(List<String> userIds) {
    if (userIds.isEmpty) {
      return Stream.value([]);
    }
    return _firestore
        .collection('leave_requests')
        .where('status', isEqualTo: 'pending')
        .where('userId', whereIn: userIds)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
          .toList();
      requests.sort((a, b) => a.startDate.compareTo(b.startDate));
      return requests;
    });
  }

  // Get all leave requests for a team
  Stream<List<LeaveRequest>> getRequestsForTeam(List<String> userIds) {
    if (userIds.isEmpty) {
      return Stream.value([]);
    }
    return _firestore
        .collection('leave_requests')
        .where('userId', whereIn: userIds)
        .snapshots()
        .map((snapshot) {
      final requests = snapshot.docs
          .map((doc) => LeaveRequest.fromFirestore(doc.data(), doc.id))
          .toList();
      requests.sort((a, b) => b.startDate.compareTo(a.startDate));
      return requests;
    });
  }
}

class LeaveBalanceSummary {
  final num monthlyAllowance;
  final num approvedDays;
  final num pendingDays;
  final num remainingDays;

  const LeaveBalanceSummary({
    required this.monthlyAllowance,
    required this.approvedDays,
    required this.pendingDays,
    required this.remainingDays,
  });
}

class _WorkCalendarPolicy {
  final bool sundayWorking;
  final Set<String> holidayDates;

  const _WorkCalendarPolicy({
    this.sundayWorking = false,
    this.holidayDates = const {},
  });

  factory _WorkCalendarPolicy.fromMap(Map<String, dynamic> data) {
    final holidayDates = _parseHolidayDates(data['holidayDates']);

    final holidayEvents = data['holidayEvents'];
    if (holidayEvents is List) {
      for (final event in holidayEvents.whereType<Map>()) {
        final map = Map<String, dynamic>.from(event);
        final dateKey = map['dateKey']?.toString().trim();
        if (dateKey != null && dateKey.isNotEmpty) {
          holidayDates.add(dateKey);
          continue;
        }

        final rawDate = map['date'];
        if (rawDate is Timestamp) {
          holidayDates.add(_formatDateKey(rawDate.toDate()));
        } else {
          final parsed = DateTime.tryParse(rawDate?.toString() ?? '');
          if (parsed != null) holidayDates.add(_formatDateKey(parsed));
        }
      }
    }

    return _WorkCalendarPolicy(
      sundayWorking: data['sundayWorking'] as bool? ?? false,
      holidayDates: holidayDates,
    );
  }

  bool isWorkingDay(DateTime date, String Function(DateTime) dateKey) {
    if (holidayDates.contains(dateKey(date))) return false;
    if (date.weekday == DateTime.saturday) return true;
    if (date.weekday == DateTime.sunday && !sundayWorking) return false;
    return true;
  }

  static Set<String> _parseHolidayDates(Object? data) {
    if (data is List) {
      return data
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    if (data is String) {
      return data
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    return {};
  }

  static String _formatDateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
