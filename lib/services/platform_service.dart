import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/platform_models.dart';

/// Platform-level data access for the Super Admin console.
///
/// Aggregated counters live in a single `platformStats/dashboard` document so
/// the console stays within the Firebase Spark plan (no collection scans on
/// every screen load). Super Admin mutations bump the counters with
/// [FieldValue.increment]; [reconcileStats] recomputes them from source
/// collections when they are missing or stale, and can be triggered manually.
class PlatformService {
  PlatformService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;
  FirebaseAuth get _auth => _context.auth;

  static const String statsPath = 'platformStats/dashboard';
  static const String _activityCollection = 'activity_logs';
  static const String _auditCollection = 'audit_logs';
  static const String _securityCollection = 'security_events';
  static const String _announcementsCollection = 'announcements';
  static const String _invoicesCollection = 'billing/invoices';
  static const String _paymentsCollection = 'billing/payments';
  static const String _usersCollection = 'users';

  String get _currentEmail =>
      _auth.currentUser?.email?.trim().toLowerCase() ?? 'super_admin';

  /// Email of the signed-in operator (falls back to `super_admin`).
  static String get currentEmail =>
      FirebaseContextProvider.current.auth.currentUser?.email
          ?.trim()
          .toLowerCase() ??
      'super_admin';

  void _log(String message) {
    debugPrint(
      '[PlatformService] $message (uid=${_auth.currentUser?.uid ?? 'none'})',
    );
  }

  // ---------------------------------------------------------------------------
  // Aggregated stats
  // ---------------------------------------------------------------------------

  Stream<PlatformStats> streamStats() {
    _log('STREAM platformStats/dashboard');
    return _firestore
        .collection('platformStats')
        .doc('dashboard')
        .snapshots()
        .map((doc) => PlatformStats.fromFirestore(doc));
  }

  /// Reads the stats document, creating it (and reconciling from source data)
  /// on first use so the dashboard is accurate for pre-existing data.
  Future<PlatformStats> getStats() async {
    const path = statsPath;
    _log('READ $path');
    try {
      final doc = await _firestore.doc(path).get();
      if (!doc.exists) {
        _log('READ $path MISSING — running reconcileStats');
        await reconcileStats();
        final fresh = await _firestore.doc(path).get();
        _log('READ $path SUCCESS after reconcile');
        return PlatformStats.fromFirestore(fresh);
      }
      _log('READ $path SUCCESS');
      final stats = PlatformStats.fromFirestore(doc);
      final stale = stats.lastUpdated == null ||
          DateTime.now().difference(stats.lastUpdated!) >
              const Duration(hours: 24);
      if (stale) {
        _log('READ $path STALE — running reconcileStats in background');
        unawaited(reconcileStats());
      }
      return stats;
    } on FirebaseException catch (e) {
      _log('READ $path FAILED (${e.code}): ${e.message}');
      return const PlatformStats();
    }
  }

  /// Applies numeric deltas (positive or negative) to the stats document.
  Future<void> bumpStats(Map<String, dynamic> deltas) async {
    final ref = _firestore.doc(statsPath);
    final data = <String, dynamic>{};
    deltas.forEach((key, value) {
      data[key] = value is num ? FieldValue.increment(value) : value;
    });
    data['lastUpdated'] = FieldValue.serverTimestamp();
    await ref.set(data, SetOptions(merge: true));
  }

  /// Recomputes every counter from the source collections. Used on first load
  /// (stats missing) and via the "Refresh stats" button.
  Future<void> reconcileStats() async {
    _log('RECONCILE start — reading source collections');

    var companiesSnapDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    try {
      final companiesSnap = await _firestore.collection('companies').get();
      companiesSnapDocs = companiesSnap.docs;
      _log(
          'RECONCILE READ companies SUCCESS (${companiesSnapDocs.length} docs)');
    } on FirebaseException catch (e) {
      _log('RECONCILE READ companies FAILED (${e.code}): ${e.message}');
      // Continue with empty companies — all company-derived stats will be zero
    }

    final now = DateTime.now();

    var active = 0;
    var suspended = 0;
    var pending = 0;
    var trial = 0;
    var paid = 0;
    var expiring = 0;
    var planFree = 0;
    var planStarter = 0;
    var planPro = 0;
    var planEnterprise = 0;
    final companiesByMonth = <String, int>{};

    for (final doc in companiesSnapDocs) {
      final data = doc.data();
      final isActive = data['isActive'] ?? true;
      if (isActive == true) {
        active++;
      } else {
        suspended++;
      }
      final status = (data['subscriptionStatus'] as String? ?? 'active');
      if (status == 'trial') trial++;
      if (status == 'active') paid++;
      final plan = (data['plan'] as String? ?? 'Free');
      switch (plan) {
        case 'Starter':
          planStarter++;
        case 'Pro':
          planPro++;
        case 'Enterprise':
          planEnterprise++;
        default:
          planFree++;
      }
      final renewsAt = data['renewsAt'] is Timestamp
          ? (data['renewsAt'] as Timestamp).toDate()
          : null;
      if (renewsAt != null &&
          renewsAt.isBefore(now.add(const Duration(days: 7)))) {
        expiring++;
      }
      final created = data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null;
      if (created != null) {
        final key =
            '${created.year}-${created.month.toString().padLeft(2, '0')}';
        companiesByMonth[key] = (companiesByMonth[key] ?? 0) + 1;
      }
    }

    int userCount = 0;
    int activeToday = 0;
    try {
      _log('RECONCILE READ users (limit 1000)');
      final usersSnap = await _firestore.collection('users').limit(1000).get();
      userCount = usersSnap.docs.length;
      _log('RECONCILE READ users SUCCESS ($userCount docs)');
    } catch (e) {
      _log('RECONCILE READ users FAILED: $e');
    }
    try {
      final todayKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      _log('RECONCILE READ attendance (dateKey=$todayKey)');
      final attendanceSnap = await _firestore
          .collection('attendance')
          .where('dateKey', isEqualTo: todayKey)
          .limit(1000)
          .get();
      _log(
          'RECONCILE READ attendance SUCCESS (${attendanceSnap.docs.length} docs)');
      final seen = <String>{};
      for (final doc in attendanceSnap.docs) {
        final employeeId = (doc.data()['employeeId'] as String? ?? '').trim();
        if (employeeId.isEmpty) continue;
        seen.add(employeeId);
      }
      activeToday = seen.length;
    } catch (e) {
      _log('RECONCILE READ attendance FAILED: $e');
    }

    var openTickets = 0;
    var closedTickets = 0;
    try {
      _log('RECONCILE READ support_tickets (limit 1000)');
      final ticketsSnap =
          await _firestore.collection('support_tickets').limit(1000).get();
      _log(
          'RECONCILE READ support_tickets SUCCESS (${ticketsSnap.docs.length} docs)');
      for (final doc in ticketsSnap.docs) {
        final status = (doc.data()['status'] as String? ?? 'open');
        if (status == 'resolved') {
          closedTickets++;
        } else {
          openTickets++;
        }
      }
    } catch (e) {
      _log('RECONCILE READ support_tickets FAILED: $e');
    }

    _log('WRITE $statsPath (reconcile merge)');
    try {
      await _firestore.doc(statsPath).set({
        'totalCompanies': companiesSnapDocs.length,
        'activeCompanies': active,
        'suspendedCompanies': suspended,
        'pendingApprovals': pending,
        'totalUsers': userCount,
        'activeUsersToday': activeToday,
        'activeSubscriptions': paid,
        'trialCompanies': trial,
        'expiringSubscriptions': expiring,
        'planFree': planFree,
        'planStarter': planStarter,
        'planPro': planPro,
        'planEnterprise': planEnterprise,
        'openTickets': openTickets,
        'closedTickets': closedTickets,
        'companiesByMonth': companiesByMonth,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _log('WRITE $statsPath SUCCESS');
    } on FirebaseException catch (e) {
      _log('WRITE $statsPath FAILED (${e.code}): ${e.message}');
      // Permission denied or other Firestore error — stats remain stale but
      // the dashboard will fall back to whatever was previously stored.
    }
  }

  // ---------------------------------------------------------------------------
  // Activity feed
  // ---------------------------------------------------------------------------

  Future<void> recordActivity({
    required String type,
    required String title,
    String? detail,
    String? companyId,
    String? companyName,
  }) async {
    try {
      await _firestore.collection(_activityCollection).add({
        'type': type,
        'title': title,
        if (detail != null) 'detail': detail,
        if (companyId != null) 'companyId': companyId,
        if (companyName != null) 'companyName': companyName,
        'actorEmail': _currentEmail,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Activity recording is best-effort and must never break an action.
    }
  }

  Stream<List<PlatformActivityEvent>> streamActivity({int limit = 12}) {
    _log('STREAM activity_logs (limit=$limit)');
    return _firestore
        .collection(_activityCollection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map(PlatformActivityEvent.fromFirestore).toList());
  }

  // ---------------------------------------------------------------------------
  // Audit trail
  // ---------------------------------------------------------------------------

  Future<void> recordAudit({
    required String category,
    required String action,
    String? actorRole,
    String? targetType,
    String? targetId,
    String? targetName,
    Map<String, dynamic> changes = const {},
  }) async {
    try {
      await _firestore.collection(_auditCollection).add({
        'category': category,
        'action': action,
        'actorEmail': _currentEmail,
        if (actorRole != null) 'actorRole': actorRole,
        if (targetType != null) 'targetType': targetType,
        if (targetId != null) 'targetId': targetId,
        if (targetName != null) 'targetName': targetName,
        'changes': changes,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Stream<List<AuditEvent>> streamAuditLogs({int limit = 200}) {
    return _firestore
        .collection(_auditCollection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(AuditEvent.fromFirestore).toList());
  }

  /// One-shot fetch of a large slice of the audit trail (bounded) for export.
  Future<List<AuditEvent>> fetchAuditLogsAll({int limit = 1000}) async {
    final snap = await _firestore
        .collection(_auditCollection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(AuditEvent.fromFirestore).toList();
  }

  // ---------------------------------------------------------------------------
  // Security events
  // ---------------------------------------------------------------------------

  Future<void> recordSecurityEvent({
    required String type,
    required String email,
    String? detail,
  }) async {
    try {
      await _firestore.collection(_securityCollection).add({
        'type': type,
        'email': email,
        if (detail != null) 'detail': detail,
        'timestamp': FieldValue.serverTimestamp(),
      });
      final counter = switch (type) {
        'failed_login' => 'failedLogins',
        'locked_account' => 'lockedAccounts',
        'suspicious_login' => 'suspiciousLogins',
        'password_reset' => 'passwordResets',
        _ => 'failedLogins',
      };
      await bumpStats({counter: 1});
    } catch (_) {}
  }

  Stream<List<SecurityEvent>> streamSecurityEvents({int limit = 100}) {
    return _firestore
        .collection(_securityCollection)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(SecurityEvent.fromFirestore).toList());
  }

  Future<void> deleteSecurityEvent(String id) async {
    await _firestore.collection(_securityCollection).doc(id).delete();
  }

  // ---------------------------------------------------------------------------
  // Announcements
  // ---------------------------------------------------------------------------

  Future<void> createAnnouncement({
    required String title,
    required String body,
    required String status,
    required String audience,
    DateTime? publishAt,
    DateTime? expiresAt,
  }) async {
    await _firestore.collection(_announcementsCollection).add({
      'title': title,
      'body': body,
      'status': status,
      'audience': audience,
      'createdBy': _currentEmail,
      if (publishAt != null) 'publishAt': Timestamp.fromDate(publishAt),
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateAnnouncementStatus(String id, String status) async {
    await _firestore.collection(_announcementsCollection).doc(id).update({
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAnnouncement(String id) async {
    await _firestore.collection(_announcementsCollection).doc(id).delete();
  }

  Stream<List<AnnouncementModel>> streamAnnouncements({int limit = 200}) {
    return _firestore
        .collection(_announcementsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(AnnouncementModel.fromFirestore).toList());
  }

  // ---------------------------------------------------------------------------
  // Billing
  // ---------------------------------------------------------------------------

  Future<Invoice> createInvoice({
    required String companyId,
    required String companyName,
    required String description,
    required double amount,
    required String currency,
    required String status,
    DateTime? dueDate,
  }) async {
    final ref = _firestore.collection(_invoicesCollection).doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'companyId': companyId,
      'companyName': companyName,
      'description': description,
      'amount': amount,
      'currency': currency,
      'status': status,
      'issueDate': now,
      if (dueDate != null) 'dueDate': Timestamp.fromDate(dueDate),
      'createdAt': now,
    });
    final doc = await ref.get();
    return Invoice.fromFirestore(doc);
  }

  Future<void> markInvoicePaid(String invoiceId, {DateTime? paidAt}) async {
    await _firestore.collection(_invoicesCollection).doc(invoiceId).update({
      'status': 'paid',
      'paidAt': paidAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(paidAt),
    });
  }

  Future<void> deleteInvoice(String invoiceId) async {
    await _firestore.collection(_invoicesCollection).doc(invoiceId).delete();
  }

  Stream<List<Invoice>> streamInvoices({int limit = 100}) {
    return _firestore
        .collection(_invoicesCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Invoice.fromFirestore).toList());
  }

  Future<Payment> recordPayment({
    required String companyId,
    required String companyName,
    required double amount,
    required String currency,
    required String method,
    String? reference,
    String? invoiceId,
  }) async {
    final ref = _firestore.collection(_paymentsCollection).doc();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'companyId': companyId,
      'companyName': companyName,
      'amount': amount,
      'currency': currency,
      'method': method,
      if (reference != null) 'reference': reference,
      if (invoiceId != null) 'invoiceId': invoiceId,
      'paidAt': now,
      'createdAt': now,
    });
    final doc = await ref.get();
    return Payment.fromFirestore(doc);
  }

  Stream<List<Payment>> streamPayments({int limit = 100}) {
    return _firestore
        .collection(_paymentsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(Payment.fromFirestore).toList());
  }

  // ---------------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------------

  /// Fetches a page of `users` docs ordered by creation date (newest first)
  /// using a document cursor for cheap, indexed pagination.
  Future<List<PlatformUserRow>> getUsersPage({
    int pageSize = 25,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    try {
      var query = _firestore
          .collection(_usersCollection)
          .orderBy('createdAt', descending: true)
          .limit(pageSize);
      if (startAfter != null) query = query.startAfterDocument(startAfter);
      final snap = await query.get();
      return snap.docs.map(PlatformUserRow.fromFirestore).toList();
    } catch (_) {
      return const [];
    }
  }

  Stream<List<PlatformUserRow>> streamUsers({int limit = 100}) {
    return _firestore
        .collection(_usersCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(PlatformUserRow.fromFirestore).toList());
  }

  Future<void> setUserActive(String uid, {required bool isActive}) async {
    await _firestore.collection(_usersCollection).doc(uid).update({
      'isActive': isActive,
      'status': isActive ? 'active' : 'inactive',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteUserDoc(String uid) async {
    await _firestore.collection(_usersCollection).doc(uid).delete();
  }

  // ---------------------------------------------------------------------------
  // Platform settings
  // ---------------------------------------------------------------------------

  Stream<PlatformSettings> streamPlatformSettings() {
    return _firestore
        .collection('app_config')
        .doc('platform')
        .snapshots()
        .map((doc) => PlatformSettings.fromMap(doc.data() ?? const {}));
  }

  Future<PlatformSettings> getPlatformSettings() async {
    final doc = await _firestore.collection('app_config').doc('platform').get();
    return PlatformSettings.fromMap(doc.data() ?? const {});
  }

  Future<void> savePlatformSettings(Map<String, dynamic> updates) async {
    updates['updatedAt'] = FieldValue.serverTimestamp();
    await _firestore
        .collection('app_config')
        .doc('platform')
        .set(updates, SetOptions(merge: true));
  }
}
