import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';
import '../firebase/firebase_context.dart';

class _NotificationDisplay {
  final String title;
  final String body;

  const _NotificationDisplay({
    required this.title,
    required this.body,
  });
}

/// Top-level background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await NotificationService.showBackgroundNotification(message);
  debugPrint('Handling a background message: ${message.messageId}');
}

@pragma('vm:entry-point')
void _notificationActionBackgroundHandler(NotificationResponse response) {
  unawaited(NotificationService.handleNotificationActionResponse(response));
}

class NotificationService {
  // Singleton pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initializationFuture;

  FirebaseFirestore _firestore = FirebaseFirestore.instance;
  FirebaseAuth _auth = FirebaseAuth.instance;

  /// Re-binds this singleton to the active Firebase context so Firestore and
  /// Auth reads/writes follow the workspace project. `main()` registers this
  /// as the [FirebaseManager] context applier, so it is invoked automatically
  /// whenever the active Firebase project changes.
  void configure(FirebaseContext context) {
    _firestore = context.firestore;
    _auth = context.auth;
  }

  static const String channelId = 'high_importance_channel';
  static const String channelName = 'High Importance Notifications';
  static const String channelDescription =
      'This channel is used for important attendance alerts.';
  static const String actionApprove = 'approve';
  static const String actionReject = 'reject';
  static const String actionView = 'view';
  static const String brand = 'TЯAKR';

  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    if (kIsWeb || message.notification != null) return;

    final display = _displayFromMessage(message);
    if (display == null) return;

    final plugin = FlutterLocalNotificationsPlugin();
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await plugin.initialize(
      initSettings,
      onDidReceiveBackgroundNotificationResponse:
          _notificationActionBackgroundHandler,
    );
    await _ensureAndroidChannel(plugin);

    await plugin.show(
      _notificationId(message),
      display.title,
      display.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          actions: _androidActionsFromData(message.data),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static Future<void> _ensureAndroidChannel(
    FlutterLocalNotificationsPlugin plugin,
  ) {
    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
    );

    return plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(channel) ??
        Future.value();
  }

  static _NotificationDisplay? _displayFromMessage(RemoteMessage message) {
    final data = message.data;
    final rawBody = _firstNonEmpty([
      message.notification?.body,
      data['body'],
      data['content'],
      data['message'],
    ]);
    if (rawBody == null) return null;

    final isDynamic =
        data['notificationFormat']?.toString().trim().toLowerCase() ==
            'dynamic';
    final body = isDynamic
        ? cleanNotificationDynamicText(rawBody)
        : cleanNotificationText(rawBody);
    final rawTitle = _firstNonEmpty([
      message.notification?.title,
      data['title'],
      data['notificationTitle'],
      data['type'],
      'Attendance System',
    ]);
    final title = isDynamic
        ? cleanNotificationDynamicTitle(rawTitle ?? 'Attendance System')
        : cleanNotificationTitle(rawTitle ?? 'Attendance System', body);
    return _NotificationDisplay(title: title, body: body);
  }

  static String? _firstNonEmpty(Iterable<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  static int _notificationId(RemoteMessage message) {
    final stableId = _firstNonEmpty([
      message.messageId,
      message.data['notificationId'],
      message.data['requestId'],
    ]);
    return stableId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  static List<AndroidNotificationAction> _androidActionsFromData(
    Map<String, dynamic> data,
  ) {
    final actionType = data['actionType']?.toString().trim();
    final requestId = data['requestId']?.toString().trim();
    if (requestId == null || requestId.isEmpty) {
      return const <AndroidNotificationAction>[];
    }
    if (actionType != 'leave_request' &&
        actionType != 'permission_request' &&
        actionType != 'checkout_request') {
      return const <AndroidNotificationAction>[];
    }

    final primaryAction =
        data['primaryAction']?.toString().trim() ?? actionApprove;
    final primaryLabel =
        data['primaryActionLabel']?.toString().trim() ?? 'Approve';
    final actions = <AndroidNotificationAction>[
      AndroidNotificationAction(
        primaryAction,
        primaryLabel.isEmpty ? 'Approve' : primaryLabel,
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ];

    if (actionType != 'checkout_request') {
      final secondaryAction = data['secondaryAction']?.toString().trim();
      if (secondaryAction != null && secondaryAction.isNotEmpty) {
        final secondaryLabel =
            data['secondaryActionLabel']?.toString().trim() ?? 'Reject';
        actions.add(
          AndroidNotificationAction(
            secondaryAction,
            secondaryLabel.isEmpty ? 'Reject' : secondaryLabel,
            showsUserInterface: false,
            cancelNotification: true,
          ),
        );
      }
    }

    return actions;
  }

  static String _removeBrandPrefix(String value) {
    return value
        .replaceFirst(RegExp(r'^T[ЯR]AKR\s*•\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^T[ЯR]AKA\s*•\s*', caseSensitive: false), '')
        .trim();
  }

  static String _removeBrandText(String value) {
    return value
        .replaceAll(RegExp(r'\bT[ЯR]AKA\b\s*•?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bT[ЯR]AKR\b\s*•?\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+•\s+'), ' • ')
        .trim();
  }

  static String cleanNotificationText(String value) {
    var cleaned = _removeBrandText(value)
        .replaceAll(
          RegExp(
            r'\bstaff\s+check[\s\u2010-\u2015-]*out\s+recorded\b',
            caseSensitive: false,
          ),
          'Work Session Closed',
        )
        .replaceAll(
          RegExp(
            r'\bstaff\s+check[\s\u2010-\u2015-]*in\s+recorded\b',
            caseSensitive: false,
          ),
          'Secure Check-In',
        );

    cleaned = cleaned.replaceAllMapped(
      RegExp(
        r'^(?:(?:📍|⚠️)\s*)?(?:staff members?\s+)?(.+?)\s+(?:has\s+)?checked\s+in(?:\s+successfully)?\.\s*status:\s*late\.?$',
        caseSensitive: false,
      ),
      (match) => '⚠️ ${match.group(1)} checked in late',
    );

    cleaned = cleaned.replaceAllMapped(
      RegExp(
        r'^(?:👋\s*)?(?:staff members?\s+)?(.+?)\s+(?:has\s+)?checked\s+out(?:\s+successfully|\.\s*status:\s*[^.]+)?\.?$',
        caseSensitive: false,
      ),
      (match) => '👋 ${match.group(1)} checked out',
    );

    return cleaned
        .replaceAll(
            RegExp(r'\bstaff members?\b', caseSensitive: false), 'employee')
        .replaceAll(RegExp(r'\bstaff\b', caseSensitive: false), 'employee')
        .trim();
  }

  static String cleanNotificationDynamicText(String value) {
    return _removeBrandText(value).trim();
  }

  static String cleanNotificationDynamicTitle(String value) {
    return _removeBrandPrefix(_removeBrandText(value)).trim();
  }

  static String cleanNotificationTitle(String title, String body) {
    final cleanedTitle = _removeBrandText(
      _removeBrandPrefix(cleanNotificationText(title)),
    );
    final cleanedBody = cleanNotificationText(body);
    if (RegExp(r'early\s+check[\s\u2010-\u2015-]*out', caseSensitive: false)
            .hasMatch(cleanedTitle) ||
        RegExp(r'early\s+check[\s\u2010-\u2015-]*out', caseSensitive: false)
            .hasMatch(cleanedBody)) {
      return 'Early Check-out Recorded';
    }
    if (RegExp(r'\bchecked\s+out\b', caseSensitive: false)
        .hasMatch(cleanedBody)) {
      return 'Work Session Closed';
    }
    if (RegExp(r'\bchecked\s+in\b', caseSensitive: false)
        .hasMatch(cleanedBody)) {
      return RegExp(r'\blate\b', caseSensitive: false).hasMatch(cleanedBody)
          ? 'Late Check-In Recorded'
          : 'Secure Check-In';
    }
    if (RegExp(r'\babsent\b', caseSensitive: false).hasMatch(cleanedTitle) ||
        RegExp(r'\bno check[\s\u2010-\u2015-]*in\b', caseSensitive: false)
            .hasMatch(cleanedBody)) {
      return 'Absent Marked';
    }
    if (RegExp(r'\bchecked in late\b', caseSensitive: false)
        .hasMatch(cleanedBody)) {
      return 'Late Check-In Recorded';
    }
    return cleanedTitle;
  }

  static bool _isActionablePayload(Map<String, dynamic> data) {
    final type = data['actionType']?.toString();
    final requestId = data['requestId']?.toString();
    final collection = data['requestCollection']?.toString();
    final isActionableType = type == 'leave_request' ||
        type == 'permission_request' ||
        type == 'checkout_request';
    return isActionableType &&
        requestId != null &&
        requestId.isNotEmpty &&
        collection != null &&
        collection.isNotEmpty;
  }

  Future<void> initialize() async {
    _initializationFuture ??= _initializeInternal();
    return _initializationFuture!;
  }

  Future<void> _initializeInternal() async {
    if (kIsWeb) {
      await _initializeWebMessaging();
      return;
    }

    // 1. Setup Background Handler (Mobile only)
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Setup Foreground Notification Channel (Android)
    await _ensureAndroidChannel(_localNotifications);

    // 3. Initialize Local Notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        unawaited(handleNotificationActionResponse(details));
      },
      onDidReceiveBackgroundNotificationResponse:
          _notificationActionBackgroundHandler,
    );

    // 4. Request Permissions (Android 13+ and iOS)
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      debugPrint('User granted provisional permission');
    } else {
      debugPrint('User declined or has not accepted permission');
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 5. Setup Foreground Listeners
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AndroidNotification? android = message.notification?.android;
      final display = _displayFromMessage(message);

      if (display != null) {
        _localNotifications.show(
          _notificationId(message),
          display.title,
          display.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: channelDescription,
              icon: android?.smallIcon,
              importance: Importance.max,
              priority: Priority.high,
              ticker: 'ticker',
              actions: _androidActionsFromData(message.data),
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
            macOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    });

    // 6. Handle interaction when the app is backgrounded or terminated.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      unawaited(_handleRemoteMessageOpened(message));
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      unawaited(
        _handleRemoteMessageOpened(initialMessage, fromTerminated: true),
      );
    }

    // 7. Initial Token Update
    await updateTokenInFirestore();

    _messaging.onTokenRefresh.listen((token) {
      unawaited(updateTokenInFirestore(tokenOverride: token));
    });
  }

  Future<String?> getToken() async {
    try {
      if (kIsWeb) {
        final settings = await _messaging.getNotificationSettings();
        if (!_hasNotificationAuthorization(settings)) {
          return null;
        }

        const vapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');
        if (vapidKey.isEmpty) {
          debugPrint(
            'Web push token skipped: build with --dart-define=FIREBASE_WEB_VAPID_KEY=your_key.',
          );
          return null;
        }
        return await _messaging.getToken(vapidKey: vapidKey);
      }
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('Error getting FCM token: $e');
      return null;
    }
  }

  Future<void> _initializeWebMessaging() async {
    final settings = await _messaging.getNotificationSettings();
    if (_hasNotificationAuthorization(settings)) {
      await updateTokenInFirestore();
      _messaging.onTokenRefresh.listen((token) {
        unawaited(updateTokenInFirestore(tokenOverride: token));
      });
    }
  }

  bool _hasNotificationAuthorization(NotificationSettings settings) {
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<void> _handleRemoteMessageOpened(
    RemoteMessage message, {
    bool fromTerminated = false,
  }) async {
    final data = Map<String, dynamic>.from(message.data);
    debugPrint(
      'Notification opened from ${fromTerminated ? 'terminated' : 'background'} state: ${message.messageId}',
    );
    if (data.isEmpty || !_isActionablePayload(data)) return;
  }

  Future<void> updateTokenInFirestore({String? tokenOverride}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final token = tokenOverride ?? await getToken();
    if (token == null) return;

    try {
      final firestore = _firestore;
      final email = user.email?.trim();
      final authProfileRef = firestore.collection('users').doc(user.uid);
      await _removeTokenFromAllProfiles(firestore, token);
      final updates = {
        'fcmToken': token,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      };

      // Always keep the auth user profile token current.
      await authProfileRef.set(updates, SetOptions(merge: true));

      // Try updating in 'users' collection (Staff)
      final userDoc = await authProfileRef.get();
      if (userDoc.exists) {
        debugPrint('FCM Token updated for Staff: ${user.uid}');
      }

      // Try updating in 'admins' collection
      final adminDoc = await firestore.collection('admins').doc(user.uid).get();
      if (adminDoc.exists) {
        await adminDoc.reference.set(updates, SetOptions(merge: true));
        debugPrint('FCM Token updated for Admin: ${user.uid}');
      }

      // Try updating in 'managers' collection
      final managerDoc =
          await firestore.collection('managers').doc(user.uid).get();
      if (managerDoc.exists) {
        await managerDoc.reference.set(updates, SetOptions(merge: true));
        debugPrint('FCM Token updated for Manager: ${user.uid}');
      }

      if (email != null && email.isNotEmpty) {
        final emailCandidates = {
          email,
          email.toLowerCase(),
        };
        for (final collection in const ['staff', 'managers', 'admins']) {
          for (final emailCandidate in emailCandidates) {
            final snap = await firestore
                .collection(collection)
                .where('email', isEqualTo: emailCandidate)
                .get();
            for (final doc in snap.docs) {
              await doc.reference.set(updates, SetOptions(merge: true));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating FCM token: $e');
    }
  }

  Future<void> _removeTokenFromAllProfiles(
    FirebaseFirestore firestore,
    String token,
  ) async {
    final updatesByPath = <String,
        MapEntry<DocumentReference<Map<String, dynamic>>,
            Map<String, dynamic>>>{};

    void queueRemoval(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
      final data = doc.data();
      final update = <String, dynamic>{
        'fcmTokens': FieldValue.arrayRemove([token]),
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      };
      if (data['fcmToken'] == token) {
        update['fcmToken'] = FieldValue.delete();
      }
      updatesByPath[doc.reference.path] = MapEntry(doc.reference, update);
    }

    for (final collection in const ['users', 'staff', 'managers', 'admins']) {
      final byArray = await firestore
          .collection(collection)
          .where('fcmTokens', arrayContains: token)
          .get();
      for (final doc in byArray.docs) {
        queueRemoval(doc);
      }

      final byPrimary = await firestore
          .collection(collection)
          .where('fcmToken', isEqualTo: token)
          .get();
      for (final doc in byPrimary.docs) {
        queueRemoval(doc);
      }
    }

    if (updatesByPath.isEmpty) return;

    var batch = firestore.batch();
    var count = 0;
    for (final entry in updatesByPath.values) {
      batch.set(entry.key, entry.value, SetOptions(merge: true));
      count += 1;
      if (count == 450) {
        await batch.commit();
        batch = firestore.batch();
        count = 0;
      }
    }
    if (count > 0) {
      await batch.commit();
    }
  }

  Future<void> deleteToken() async {
    await _messaging.deleteToken();
  }

  static Future<void> handleNotificationActionResponse(
    NotificationResponse response,
  ) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    final payload = response.payload;
    debugPrint('Notification clicked: $payload action=${response.actionId}');
    if (payload == null || payload.trim().isEmpty) return;
    if (response.actionId == null || response.actionId!.isEmpty) return;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      if (!_isActionablePayload(data)) return;

      final actionId = response.actionId;
      if (actionId != actionApprove && actionId != actionReject) return;
      if (data['actionType'] == 'checkout_request' &&
          actionId != actionApprove) {
        return;
      }

      await _sendNotificationActionToVercel({
        'actionId': actionId,
        'actionType': data['actionType'],
        'requestId': data['requestId'],
        'requestCollection': data['requestCollection'],
        'employeeId': data['employeeId'],
        'managerName': data['managerName'],
      });
    } catch (e) {
      debugPrint('Error handling notification action: $e');
    }
  }

  static Future<void> _sendNotificationActionToVercel(
    Map<String, dynamic> payload,
  ) async {
    // Legacy Vercel notification-action endpoint is no longer deployed. No-op
    // so action handling doesn't make a failing network request.
  }

  /// Trigger a push notification via the Vercel serverless backend
  Future<bool> sendPushNotificationByPhone(
    String phone,
    String title,
    String body, {
    Map<String, dynamic>? data,
  }) async {
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) return false;

    return _sendPushRequest(
      phone: normalizedPhone,
      title: title,
      body: body,
      data: data,
    );
  }

  Future<bool> _sendPushRequest({
    String? phone,
    String? identifier,
    String? role,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    // Push notifications are delivered by the legacy Vercel backend, which is
    // no longer deployed (it returns HTTP 500 on every call). Email is the
    // primary channel, so this secondary push path is disabled to avoid the
    // failing network requests. Re-enable once a working push endpoint exists.
    return false;
  }

  /// Trigger a platform-wide broadcast push via the Vercel serverless backend
  Future<bool> sendBroadcastNotification({
    required String title,
    required String body,
    String recipient = 'admin',
  }) async {
    // Legacy Vercel broadcast endpoint is no longer deployed (returns HTTP
    // 500). Kept as a no-op so callers keep working until a replacement push
    // backend exists.
    return false;
  }

  /// Find a user's phone number by UID, email, name, or employeeId in the admins, managers, and staff collections,
  /// then trigger a physical push notification.
  Future<bool> sendNotificationToUser({
    required String identifier,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final cleanId = identifier.trim();
    if (cleanId.isEmpty) return false;

    // Check if the identifier is "Admin"
    if (cleanId.toLowerCase() == 'admin') {
      return await sendNotificationToRole(
          role: 'admin', title: title, body: body, data: data);
    }

    final sentByIdentifier = await _sendPushRequest(
      identifier: cleanId,
      title: title,
      body: body,
      data: data,
    );
    if (sentByIdentifier) return true;

    // Try finding the user's phone number in various directories.
    final firestore = _firestore;

    // Helper to extract phone number
    String? extractPhone(Map<String, dynamic>? data) {
      final phone = data?['phone']?.toString().trim();
      return (phone != null && phone.isNotEmpty) ? phone : null;
    }

    // 1. Check in 'users' collection (auth profile)
    try {
      final userDoc = await firestore.collection('users').doc(cleanId).get();
      if (userDoc.exists) {
        final phone = extractPhone(userDoc.data());
        if (phone != null) {
          return await sendPushNotificationByPhone(phone, title, body,
              data: data);
        }
      }
    } catch (_) {}

    // 2. Check in 'staff' collection by doc ID or employeeId or email or name
    try {
      final staffDoc = await firestore.collection('staff').doc(cleanId).get();
      if (staffDoc.exists) {
        final phone = extractPhone(staffDoc.data());
        if (phone != null) {
          return await sendPushNotificationByPhone(phone, title, body,
              data: data);
        }
      }

      final queryFields = ['employeeId', 'email', 'name'];
      for (final field in queryFields) {
        final snap = await firestore
            .collection('staff')
            .where(field, isEqualTo: cleanId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final phone = extractPhone(snap.docs.first.data());
          if (phone != null) {
            return await sendPushNotificationByPhone(phone, title, body,
                data: data);
          }
        }
      }
    } catch (_) {}

    // 3. Check in 'managers' collection by doc ID or email or name
    try {
      final managerDoc =
          await firestore.collection('managers').doc(cleanId).get();
      if (managerDoc.exists) {
        final phone = extractPhone(managerDoc.data());
        if (phone != null) {
          return await sendPushNotificationByPhone(phone, title, body,
              data: data);
        }
      }

      final queryFields = ['email', 'name', 'employeeId'];
      for (final field in queryFields) {
        final snap = await firestore
            .collection('managers')
            .where(field, isEqualTo: cleanId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final phone = extractPhone(snap.docs.first.data());
          if (phone != null) {
            return await sendPushNotificationByPhone(phone, title, body,
                data: data);
          }
        }
      }
    } catch (_) {}

    // 4. Check in 'admins' collection by doc ID or email or name
    try {
      final adminDoc = await firestore.collection('admins').doc(cleanId).get();
      if (adminDoc.exists) {
        final phone = extractPhone(adminDoc.data());
        if (phone != null) {
          return await sendPushNotificationByPhone(phone, title, body,
              data: data);
        }
      }

      final queryFields = ['email', 'name'];
      for (final field in queryFields) {
        final snap = await firestore
            .collection('admins')
            .where(field, isEqualTo: cleanId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final phone = extractPhone(snap.docs.first.data());
          if (phone != null) {
            return await sendPushNotificationByPhone(phone, title, body,
                data: data);
          }
        }
      }
    } catch (_) {}

    debugPrint(
        '⚠️ WARNING: Could not find phone number for user "$cleanId". Push notification not sent.');
    return false;
  }

  /// Send a push notification to all users in a specific role (e.g. 'admin').
  Future<bool> sendNotificationToRole({
    required String role,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final sentByRole = await _sendPushRequest(
      role: role,
      title: title,
      body: body,
      data: data,
    );
    if (sentByRole) return true;

    final firestore = _firestore;
    final collection = role.toLowerCase() == 'admin' ? 'admins' : 'managers';

    try {
      final snap = await firestore.collection(collection).get();
      bool anySent = false;
      final sentPhoneKeys = <String>{};
      for (final doc in snap.docs) {
        final phone = doc.data()['phone']?.toString().trim();
        if (phone != null && phone.isNotEmpty) {
          final phoneKey = _phoneDedupeKey(phone);
          if (phoneKey.isNotEmpty && !sentPhoneKeys.add(phoneKey)) {
            continue;
          }
          final ok =
              await sendPushNotificationByPhone(phone, title, body, data: data);
          if (ok) anySent = true;
        }
      }
      return anySent;
    } catch (e) {
      debugPrint('Error sending notification to role $role: $e');
      return false;
    }
  }

  String _phoneDedupeKey(String phone) {
    return phone.trim().replaceAll(RegExp(r'[^0-9+]'), '');
  }

  Future<void> _recordNotification({
    required String recipient,
    required String type,
    required String title,
    required String content,
    required Map<String, dynamic> data,
    bool suppressFirestorePush = true,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'recipient': recipient,
        'type': type,
        'title': cleanNotificationDynamicTitle(title),
        'content': cleanNotificationDynamicText(content),
        'status': 'Sent',
        'suppressFirestorePush': suppressFirestorePush,
        'allowFirestorePush': false,
        'timestamp': FieldValue.serverTimestamp(),
        ...data,
      });
    } catch (e) {
      debugPrint('Error recording notification: $e');
    }
  }

  Future<void> recordDashboardNotification({
    required String recipient,
    required String type,
    required String title,
    required String content,
    Map<String, dynamic>? data,
  }) {
    return _recordNotification(
      recipient: recipient,
      type: type,
      title: title,
      content: content,
      data: data ?? const <String, dynamic>{},
    );
  }

  Future<bool> sendLeaveRequestNotification({
    required String recipient,
    required String requestId,
    required String employeeId,
    required String employeeName,
    required String leaveType,
    required String startsOn,
    String? leaveDuration,
    required bool toAdmin,
  }) async {
    const title = 'Leave Request Submitted';
    final dayText = leaveDuration?.trim().isNotEmpty == true
        ? leaveDuration!.trim()
        : 'Full Day';
    final body =
        '📄 $employeeName requested $leaveType\n📅 $startsOn • $dayText';
    final data = {
      'actionType': 'leave_request',
      'notificationFormat': 'manager_leave_approval',
      'requestCollection': 'leave_requests',
      'requestId': requestId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'managerName': recipient,
      'leaveType': leaveType,
      'leaveDate': startsOn,
      'leaveDuration': dayText,
      'primaryAction': actionApprove,
      'secondaryAction': actionReject,
      'primaryActionLabel': 'Accept',
      'secondaryActionLabel': 'Reject',
    };

    await _recordNotification(
      recipient: recipient,
      type: 'Leave Request',
      title: title,
      content: body,
      data: data,
    );

    return sendNotificationToUser(
      identifier: recipient,
      title: title,
      body: body,
      data: data,
    );
  }

  Future<bool> sendPermissionRequestNotification({
    required String recipient,
    required String requestId,
    required String employeeId,
    required String employeeName,
    required String permissionType,
    DateTime? fromTime,
    DateTime? toTime,
    required bool toAdmin,
  }) async {
    final title = permissionType.toLowerCase().contains('late')
        ? 'Late Entry Request'
        : 'Permission Request';
    final window = _permissionWindow(fromTime, toTime);
    final body = permissionType.toLowerCase().contains('late')
        ? '🚗 $employeeName requested delayed check-in${window.isEmpty ? '' : '\n⏰ $window'}'
        : '🕒 $employeeName requested permission${window.isEmpty ? '' : '\n⏰ $window'}';
    final data = {
      'actionType': 'permission_request',
      'requestCollection': 'permission_requests',
      'requestId': requestId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'managerName': recipient,
      'permissionType': permissionType,
      'primaryAction': actionApprove,
      'secondaryAction': actionReject,
      'primaryActionLabel': 'Accept',
      'secondaryActionLabel': 'Reject',
      if (fromTime != null) 'fromTime': Timestamp.fromDate(fromTime),
      if (toTime != null) 'toTime': Timestamp.fromDate(toTime),
    };

    await _recordNotification(
      recipient: recipient,
      type: 'Permission Request',
      title: title,
      content: body,
      data: data,
    );

    return sendNotificationToUser(
      identifier: recipient,
      title: title,
      body: body,
      data: data,
    );
  }

  Future<bool> sendCheckoutApprovalNotificationToAdmins({
    required String requestId,
    required String employeeId,
    required String employeeName,
    required String dateKey,
    required String checkoutEndLabel,
    required String graceEndLabel,
  }) async {
    const title = 'Missed Check-Out';
    final body = '⏰ $employeeName missed check-out.';
    final notificationTag = 'checkout_$requestId';
    final data = {
      'actionType': 'checkout_request',
      'notificationFormat': 'dynamic',
      'notificationTitle': title,
      'notificationBody': body,
      'notificationTag': notificationTag,
      'requestCollection': 'checkout_requests',
      'requestId': requestId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'dateKey': dateKey,
      'checkoutEndLabel': checkoutEndLabel,
      'graceEndLabel': graceEndLabel,
      'primaryAction': actionApprove,
      'primaryActionLabel': 'Approve',
    };

    await _recordNotification(
      recipient: 'Admin',
      type: 'Checkout Request',
      title: title,
      content: body,
      data: data,
    );

    return sendNotificationToRole(
      role: 'admin',
      title: title,
      body: body,
      data: data,
    );
  }

  Future<bool> sendCheckoutReminderNotificationToEmployee({
    required String employeeId,
    required String employeeName,
    required String requestId,
    required String dateKey,
    required String checkoutEndLabel,
    required String graceEndLabel,
  }) async {
    const title = 'Check-Out Reminder';
    const body = '⏰ You missed check-out.';
    final notificationTag = 'checkout_$requestId';
    final data = {
      'actionType': 'checkout_reminder',
      'notificationFormat': 'dynamic',
      'notificationTitle': title,
      'notificationBody': body,
      'notificationTag': notificationTag,
      'requestCollection': 'checkout_requests',
      'requestId': requestId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'dateKey': dateKey,
      'checkoutEndLabel': checkoutEndLabel,
      'graceEndLabel': graceEndLabel,
    };

    await _recordNotification(
      recipient: employeeId,
      type: 'Checkout Reminder',
      title: title,
      content: body,
      data: data,
    );

    return sendNotificationToUser(
      identifier: employeeId,
      title: title,
      body: body,
      data: data,
    );
  }

  Future<bool> sendCheckoutReminderNotificationToManager({
    required String managerName,
    required String employeeId,
    required String employeeName,
    required String requestId,
    required String dateKey,
    required String checkoutEndLabel,
    required String graceEndLabel,
  }) async {
    const title = 'Team Missed Check-Out';
    final body = '⏰ $employeeName missed check-out.';
    final notificationTag = 'checkout_$requestId';
    final data = {
      'actionType': 'team_checkout_reminder',
      'notificationFormat': 'dynamic',
      'notificationTitle': title,
      'notificationBody': body,
      'notificationTag': notificationTag,
      'requestCollection': 'checkout_requests',
      'requestId': requestId,
      'employeeId': employeeId,
      'employeeName': employeeName,
      'dateKey': dateKey,
      'checkoutEndLabel': checkoutEndLabel,
      'graceEndLabel': graceEndLabel,
    };

    await _recordNotification(
      recipient: managerName,
      type: 'Checkout Reminder',
      title: title,
      content: body,
      data: data,
    );

    return sendNotificationToUser(
      identifier: managerName,
      title: title,
      body: body,
      data: data,
    );
  }

  Future<bool> sendLeaveDecisionNotification({
    required String identifier,
    required bool approved,
    String? requestId,
    String? employeeName,
    String? managerName,
  }) {
    final title = approved ? 'Leave Approved' : 'Leave Rejected';
    return sendNotificationToUser(
      identifier: identifier,
      title: title,
      body: approved
          ? 'Your leave request has been approved by ${managerName?.trim().isNotEmpty == true ? managerName!.trim() : 'your manager'}.'
          : 'Your leave request has been rejected by ${managerName?.trim().isNotEmpty == true ? managerName!.trim() : 'your manager'}.',
      data: {
        'actionType': 'leave_decision',
        'notificationFormat': 'employee_leave_response',
        'requestCollection': 'leave_requests',
        if (requestId?.trim().isNotEmpty == true) 'requestId': requestId,
        if (employeeName?.trim().isNotEmpty == true)
          'employeeName': employeeName,
        if (managerName?.trim().isNotEmpty == true) 'managerName': managerName,
        'status': approved ? 'approved' : 'rejected',
      },
    );
  }

  Future<bool> sendPermissionApprovedNotification({
    required String identifier,
  }) {
    return sendNotificationToUser(
      identifier: identifier,
      title: 'Permission Approved',
      body: '✅ Your permission request was approved',
      data: {'actionType': 'permission_decision', 'status': 'approved'},
    );
  }

  Future<bool> sendPermissionDecisionNotification({
    required String identifier,
    required bool approved,
    DateTime? returnTime,
  }) {
    final returnTimeText =
        returnTime == null ? '' : ' until ${_formatIndianTime(returnTime)}';
    return sendNotificationToUser(
      identifier: identifier,
      title: approved ? 'Permission Approved' : 'Permission Update',
      body: approved
          ? '✅ Your permission request was approved$returnTimeText.'
          : '❌ Your permission request has been rejected.',
      data: {
        'actionType': 'permission_decision',
        'status': approved ? 'approved' : 'rejected',
        if (returnTime != null) 'returnTime': Timestamp.fromDate(returnTime),
        if (returnTime != null)
          'returnTimeLabel': _formatIndianTime(returnTime),
      },
    );
  }

  String _permissionWindow(DateTime? fromTime, DateTime? toTime) {
    if (fromTime == null || toTime == null) return '';
    final minutes = toTime.difference(fromTime).inMinutes;
    final hours =
        minutes <= 0 ? '' : ' (${_formatPermissionDuration(minutes)})';
    return '${_formatIndianTime(fromTime)} → ${_formatIndianTime(toTime)}$hours';
  }

  String _formatPermissionDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h hrs $m min';
    if (h > 0) return '$h hrs';
    return '$m min';
  }

  String _formatIndianTime(DateTime value) {
    final ist = value.toUtc().add(const Duration(hours: 5, minutes: 30));
    final period = ist.hour >= 12 ? 'PM' : 'AM';
    final hour = ist.hour % 12 == 0 ? 12 : ist.hour % 12;
    return '${hour.toString().padLeft(2, '0')}:'
        '${ist.minute.toString().padLeft(2, '0')} $period';
  }
}
