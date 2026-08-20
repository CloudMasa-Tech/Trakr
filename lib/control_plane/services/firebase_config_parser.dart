import 'dart:convert';

import '../models/workspace_firebase_config.dart';

/// Why a pasted/uploaded Firebase config could not be used.
enum FirebaseConfigParseError {
  /// Nothing was provided.
  empty('Paste a Firebase client configuration or upload a JSON file.'),

  /// The text is not valid JSON.
  notJson('That is not valid JSON. Paste the raw configuration text.'),

  /// The JSON root is not an object.
  notObject('The JSON must be an object, not an array or scalar.'),

  /// The file is an Admin SDK service-account key, which must never be stored
  /// on a workspace.
  serviceAccountKey(
    'This is a serviceAccountKey.json / Admin SDK private key. Upload the '
    'client-side configuration instead: Firebase Console → Project settings → '
    'Your apps → (web app) → SDK setup and configuration.',
  ),

  /// No `projectId` could be detected in any supported shape.
  missingProjectId(
    'No project id was found in the configuration. Verify the file is a '
    'client-side Firebase config for the project you created.',
  ),

  /// The required credential fields are missing or incomplete.
  incomplete(
    'The configuration is missing required fields. It must include the '
    'apiKey, appId, projectId and messagingSenderId.',
  );

  const FirebaseConfigParseError(this.message);

  /// Human-readable message safe to show in the onboarding UI.
  final String message;
}

/// Where a successfully parsed config came from, for UI labeling.
enum FirebaseConfigSource {
  /// Flat web-app config object (`apiKey`, `appId`, `projectId`, …).
  web('Web app config'),

  /// Nested Android `google-services.json` shape.
  googleServices('google-services.json'),

  /// iOS `GoogleService-Info.plist` converted to JSON.
  iOSPlist('GoogleService-Info.plist');

  const FirebaseConfigSource(this.label);

  final String label;
}

/// The outcome of parsing Firebase client configuration.
class FirebaseConfigParseResult {
  const FirebaseConfigParseResult._({
    this.config,
    this.error,
    this.source,
  });

  /// The fully-validated client config, or `null` when [error] is set.
  final WorkspaceFirebaseConfig? config;

  /// The fatal parse error, or `null` when the config parsed successfully.
  final FirebaseConfigParseError? error;

  /// Which input shape the config was parsed from (only when successful).
  final FirebaseConfigSource? source;

  bool get isValid => config != null && error == null;

  /// The detected Google Cloud project id, when known.
  String? get projectId => config?.projectId;

  String? get errorMessage => error?.message;
}

/// Parses and validates Firebase **client-side** configuration pasted into the
/// Create Workspace flow.
///
/// Accepts three JSON shapes:
///
/// 1. The flat web-app config object from Firebase Console → Project settings →
///    Your apps → web app (fields like `apiKey`, `appId`, `projectId`,
///    `messagingSenderId`).
/// 2. Android `google-services.json` (nested under `project_info`/`client`).
/// 3. An iOS `GoogleService-Info.plist` converted to JSON (upper-case keys).
///
/// It deliberately **rejects** Admin SDK `serviceAccountKey.json` payloads and
/// any payload carrying a `private_key`, because workspace documents must only
/// ever store public client-side credentials.
class FirebaseConfigParser {
  const FirebaseConfigParser._();

  /// Parses [raw] into a [WorkspaceFirebaseConfig].
  ///
  /// Never throws — all failures are captured in the returned result so the UI
  /// can render typed, human-readable messages.
  static FirebaseConfigParseResult parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.empty,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.notJson,
      );
    }

    if (decoded is! Map) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.notObject,
      );
    }
    final map = Map<String, dynamic>.from(decoded);

    if (_isServiceAccount(map)) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.serviceAccountKey,
      );
    }

    if (map.containsKey('project_info') && map['project_info'] is Map) {
      return _parseGoogleServices(map);
    }
    if (map.containsKey('PROJECT_ID')) {
      return _parseIOSPlist(map);
    }
    if (map.containsKey('projectId')) {
      return _parseWebConfig(map);
    }

    return const FirebaseConfigParseResult._(
      error: FirebaseConfigParseError.missingProjectId,
    );
  }

  static FirebaseConfigParseResult _parseWebConfig(Map<String, dynamic> map) {
    final projectId = _string(map['projectId']);
    final config = WorkspaceFirebaseConfig(
      apiKey: _string(map['apiKey']),
      appId: _string(map['appId']),
      projectId: projectId,
      messagingSenderId: _string(map['messagingSenderId']),
      storageBucket: _string(map['storageBucket']),
      authDomain: _string(map['authDomain']),
      measurementId: _nullableString(map['measurementId']),
    );

    if (config.projectId.isEmpty) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.missingProjectId,
      );
    }
    if (!config.isValid) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.incomplete,
      );
    }
    return FirebaseConfigParseResult._(
      config: config,
      source: FirebaseConfigSource.web,
    );
  }

  static FirebaseConfigParseResult _parseGoogleServices(
    Map<String, dynamic> map,
  ) {
    final projectInfo = Map<String, dynamic>.from(map['project_info'] as Map);
    final projectId = _string(projectInfo['project_id']);
    final projectNumber = _string(projectInfo['project_number']);
    final storageBucket = _string(projectInfo['storage_bucket']);

    final client = map['client'];
    Map<String, dynamic> clientMap = const {};
    if (client is List && client.isNotEmpty && client.first is Map) {
      clientMap = Map<String, dynamic>.from(client.first as Map);
    }
    final clientInfo = Map<String, dynamic>.from(
      (clientMap['client_info'] as Map?) ?? const <String, dynamic>{},
    );
    final apiKeys = clientMap['api_key'];
    String apiKey = '';
    if (apiKeys is List && apiKeys.isNotEmpty && apiKeys.first is Map) {
      apiKey =
          _string(Map<String, dynamic>.from(apiKeys.first as Map)['current_key']);
    }

    final config = WorkspaceFirebaseConfig(
      apiKey: apiKey,
      appId: _string(clientInfo['mobilesdk_app_id']),
      projectId: projectId,
      messagingSenderId: projectNumber,
      storageBucket: storageBucket,
      authDomain: projectId.isEmpty
          ? ''
          : '$projectId.firebaseapp.com',
    );

    if (config.projectId.isEmpty) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.missingProjectId,
      );
    }
    if (!config.isValid) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.incomplete,
      );
    }
    return FirebaseConfigParseResult._(
      config: config,
      source: FirebaseConfigSource.googleServices,
    );
  }

  static FirebaseConfigParseResult _parseIOSPlist(
    Map<String, dynamic> map,
  ) {
    final projectId = _string(map['PROJECT_ID']);
    final appId = _string(map['GOOGLE_APP_ID']);
    final apiKey = _string(map['API_KEY']);
    final messagingSenderId = _string(
      map['GCM_SENDER_ID'] ?? map['MESSAGING_SENDER_ID'] ?? '',
    );
    final storageBucket = _string(map['STORAGE_BUCKET']);

    final config = WorkspaceFirebaseConfig(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
      storageBucket: storageBucket,
      authDomain: projectId.isEmpty
          ? ''
          : '$projectId.firebaseapp.com',
      iosBundleId: _nullableString(map['BUNDLE_ID']),
      iosClientId: _nullableString(map['CLIENT_ID']),
    );

    if (config.projectId.isEmpty) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.missingProjectId,
      );
    }
    if (!config.isValid) {
      return const FirebaseConfigParseResult._(
        error: FirebaseConfigParseError.incomplete,
      );
    }
    return FirebaseConfigParseResult._(
      config: config,
      source: FirebaseConfigSource.iOSPlist,
    );
  }

  /// True when the payload is an Admin SDK service-account key rather than a
  /// client-side config.
  ///
  /// Any single service-account fingerprint is enough to reject the payload:
  /// `type == service_account`, `private_key`, `private_key_id`, `client_email`
  /// (alone or with `client_x509_cert_url`), or the OAuth endpoints
  /// (`auth_uri`/`token_uri`). Workspace documents must only ever store public
  /// client-side configuration.
  static bool _isServiceAccount(Map<String, dynamic> map) {
    if (map['type'] == 'service_account') return true;
    if (map.containsKey('private_key')) return true;
    if (map.containsKey('private_key_id')) return true;
    if (map.containsKey('client_email')) return true;
    if (map.containsKey('client_x509_cert_url')) return true;
    if (map.containsKey('auth_uri') && map.containsKey('token_uri')) return true;
    return false;
  }

  static String _string(dynamic value) {
    final v = value;
    if (v is String) return v.trim();
    if (v is num) return v.toString();
    return '';
  }

  static String? _nullableString(dynamic value) {
    final v = _string(value);
    return v.isEmpty ? null : v;
  }
}
