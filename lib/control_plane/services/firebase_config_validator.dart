import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/workspace_firebase_config.dart';

/// A single field-level validation failure from
/// [FirebaseConfigValidator.validateStructure].
class FirebaseConfigFieldError {
  const FirebaseConfigFieldError(this.field, this.message);

  /// The form field key (e.g. `apiKey`, `projectId`, `cdnUrl`).
  final String field;

  /// Human-readable message safe to show under the field.
  final String message;
}

/// Thrown (or returned as a list) when manually-entered Firebase configuration
/// fields fail structural validation.
class FirebaseConfigValidationException implements Exception {
  const FirebaseConfigValidationException(this.errors);

  /// Every field that failed validation.
  final List<FirebaseConfigFieldError> errors;

  /// One combined message for snack-bar/alert display.
  String get message => errors.map((e) => e.message).join('\n');

  /// Field key → message map for inline form highlighting.
  Map<String, String> get fieldErrors => {
        for (final e in errors) e.field: e.message,
      };

  @override
  String toString() => message;
}

/// The outcome of a live "Test Connection" run against the workspace's own
/// Firebase project.
class FirebaseConfigConnectionResult {
  const FirebaseConfigConnectionResult.success({
    required this.message,
    this.projectId,
  }) : success = true;

  const FirebaseConfigConnectionResult.failure({required this.message})
      : success = false,
        projectId = null;

  /// Whether the configuration connected to a live, valid Firebase project.
  final bool success;

  /// Human-readable success or failure message.
  final String message;

  /// The project the connection test reached (only when [success]).
  final String? projectId;
}

/// Validates Firebase client-side configuration entered through the Create
/// Workspace form (NPM / CDN / Config methods).
///
/// Two independent layers:
///
/// 1. [validateStructure] — fast, offline, field-level checks (required
///    fields, shape/format) so the operator never waits on the network for
///    obvious mistakes.
/// 2. [testConnection] — a live connectivity test that initializes a throwaway
///    named [FirebaseApp] from the exact same options the tenant app will use
///    ([WorkspaceFirebaseConfig.toFirebaseOptions]) and performs a lightweight
///    auth round-trip. This proves the apiKey/project/authDomain work against
///    the real project before anything is saved.
///
/// The validator never mutates the Master TRAKR project — the temp app is
/// deleted as soon as the test completes.
class FirebaseConfigValidator {
  const FirebaseConfigValidator._();

  static final RegExp _projectIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');
  static final RegExp _domainPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]*\.[a-zA-Z]{2,}$');
  static final RegExp _gUrlPattern = RegExp(r'^https://.*firebasejs.*');
  static final RegExp _measurementIdPattern = RegExp(r'^G-[A-Za-z0-9_-]{3,}$');

  /// Field-level structural validation for a manually-entered config.
  ///
  /// [method] drives which extra fields are required (NPM package/version,
  /// CDN script URL/version). Returns an empty list when every field passes.
  static List<FirebaseConfigFieldError> validateStructure({
    required FirebaseConfigMethod method,
    required String apiKey,
    required String appId,
    required String projectId,
    required String messagingSenderId,
    required String authDomain,
    required String storageBucket,
    String? measurementId,
    String npmPackage = '',
    String sdkVersion = '',
    String cdnUrl = '',
  }) {
    final errors = <FirebaseConfigFieldError>[];

    final apiKeyTrimmed = apiKey.trim();
    if (apiKeyTrimmed.isEmpty) {
      errors.add(const FirebaseConfigFieldError('apiKey', 'API key is required.'));
    } else if (apiKeyTrimmed.length < 20) {
      errors.add(const FirebaseConfigFieldError(
          'apiKey', 'API key looks too short to be a real Firebase web API key.'));
    }

    final appIdTrimmed = appId.trim();
    if (appIdTrimmed.isEmpty) {
      errors.add(const FirebaseConfigFieldError('appId', 'App ID is required.'));
    } else if (!appIdTrimmed.contains(':')) {
      errors.add(const FirebaseConfigFieldError(
          'appId', 'App ID should look like 1:1234567890:web:abcdef….'));
    }

    final projectIdTrimmed = projectId.trim();
    if (projectIdTrimmed.isEmpty) {
      errors.add(
          const FirebaseConfigFieldError('projectId', 'Project ID is required.'));
    } else if (!_projectIdPattern.hasMatch(projectIdTrimmed)) {
      errors.add(const FirebaseConfigFieldError(
          'projectId', 'Project ID can only contain lowercase letters, digits and hyphens.'));
    }

    final senderIdTrimmed = messagingSenderId.trim();
    if (senderIdTrimmed.isEmpty) {
      errors.add(const FirebaseConfigFieldError(
          'messagingSenderId', 'Messaging sender ID is required.'));
    } else if (!RegExp(r'^\d{4,}$').hasMatch(senderIdTrimmed)) {
      errors.add(const FirebaseConfigFieldError(
          'messagingSenderId', 'Messaging sender ID must be a numeric project number.'));
    }

    final authDomainTrimmed = authDomain.trim();
    if (authDomainTrimmed.isEmpty) {
      errors.add(const FirebaseConfigFieldError(
          'authDomain', 'Auth domain is required (e.g. project-id.firebaseapp.com).'));
    } else if (!_domainPattern.hasMatch(authDomainTrimmed)) {
      errors.add(const FirebaseConfigFieldError(
          'authDomain', 'Auth domain does not look like a valid domain.'));
    }

    final bucketTrimmed = storageBucket.trim();
    if (bucketTrimmed.isEmpty) {
      errors.add(const FirebaseConfigFieldError(
          'storageBucket', 'Storage bucket is required (e.g. project-id.appspot.com).'));
    } else if (!_domainPattern.hasMatch(bucketTrimmed)) {
      errors.add(const FirebaseConfigFieldError(
          'storageBucket', 'Storage bucket does not look like a valid bucket domain.'));
    }

    final measurementTrimmed = measurementId?.trim() ?? '';
    if (measurementTrimmed.isNotEmpty &&
        !_measurementIdPattern.hasMatch(measurementTrimmed)) {
      errors.add(const FirebaseConfigFieldError(
          'measurementId', 'Measurement ID should look like G-XXXXXXXXXX.'));
    }

    switch (method) {
      case FirebaseConfigMethod.npm:
        final package = npmPackage.trim();
        if (package.isNotEmpty && !RegExp(r'^[a-z0-9@./_-]+$').hasMatch(package)) {
          errors.add(const FirebaseConfigFieldError(
              'npmPackage', 'Package name contains invalid characters.'));
        }
        final version = sdkVersion.trim();
        if (version.isNotEmpty && !RegExp(r'^\d+(\.\d+)*(-\S+)?$').hasMatch(version)) {
          errors.add(const FirebaseConfigFieldError(
              'sdkVersion', 'SDK version should look like 11.6.0.'));
        }
      case FirebaseConfigMethod.cdn:
        final version = sdkVersion.trim();
        if (version.isNotEmpty && !RegExp(r'^\d+(\.\d+)*(-\S+)?$').hasMatch(version)) {
          errors.add(const FirebaseConfigFieldError(
              'sdkVersion', 'SDK version should look like 11.6.0.'));
        }
        final url = cdnUrl.trim();
        if (url.isNotEmpty && !_gUrlPattern.hasMatch(url)) {
          errors.add(const FirebaseConfigFieldError(
              'cdnUrl', 'CDN script URL must be an https:// gstatic firebasejs URL.'));
        }
        if (url.isEmpty && version.isEmpty) {
          errors.add(const FirebaseConfigFieldError(
              'cdnUrl', 'Enter the CDN script URL or an SDK version.'));
        }
      case FirebaseConfigMethod.config:
        break;
    }

    return errors;
  }

  /// Whether [projectId] is the shared TRAKR platform (Master) project — the
  /// one the app itself runs on. In single-project (Spark plan) mode workspaces
  /// may intentionally share it; the onboarding UI shows a note rather than
  /// blocking.
  static bool isPlatformProject(String projectId) {
    if (Firebase.apps.isEmpty) return false;
    try {
      return Firebase.app().options.projectId == projectId;
    } catch (_) {
      return false;
    }
  }

  /// Live connectivity test against the workspace's own Firebase project.
  ///
  /// Initializes a throwaway named [FirebaseApp] from the exact
  /// [WorkspaceFirebaseConfig.toFirebaseOptions] the tenant app will use and
  /// performs a lightweight Auth round-trip. Any response (even "no account for
  /// this email") proves the apiKey + project are valid; only real credential /
  /// project / network failures are reported. The temp app is always deleted.
  ///
  /// Never affects the Master TRAKR project — no data is written anywhere.
  static Future<FirebaseConfigConnectionResult> testConnection(
    WorkspaceFirebaseConfig config,
  ) async {
    final stopwatch = Stopwatch()..start();
    final appName =
        'trakr-config-test-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(0xFFFF)}';
    FirebaseApp? app;
    try {
      app = await Firebase.initializeApp(
        name: appName,
        options: config.toFirebaseOptions(),
      );
      final auth = FirebaseAuth.instanceFor(app: app);
      // A lightweight auth round-trip proves the apiKey + project are valid:
      // a registered email would yield `wrong-password`, an unregistered one a
      // generic `invalid-credential`/`user-not-found` — all of which confirm the
      // project is reachable. It only throws for genuinely broken
      // apiKey/project/auth configuration.
      await auth
          .signInWithEmailAndPassword(
            email: 'validate@trakr.test',
            password: 'not-the-real-password',
          )
          .timeout(const Duration(seconds: 15));
      stopwatch.stop();
      return FirebaseConfigConnectionResult.success(
        projectId: config.projectId,
        message: 'Connected to Firebase project "${config.projectId}" in '
            '${_formatElapsed(stopwatch.elapsedMilliseconds)}. '
            'The configuration is valid.',
      );
    } on FirebaseAuthException catch (e) {
      return classifyAuthFailure(e, config.projectId);
    } on TimeoutException {
      return const FirebaseConfigConnectionResult.failure(
        message: 'Connection timed out. The Firebase project could not be '
            'reached from this network. Check the configuration and try again.',
      );
    } catch (e) {
      return classifyGenericFailure(e, config.projectId);
    } finally {
      if (app != null) {
        try {
          await app.delete();
        } catch (_) {
          // Best-effort cleanup; a failed delete must not mask the result.
        }
      }
    }
  }

  /// Maps an auth round-trip exception to the definitive connection result.
  ///
  /// Auth error codes such as `invalid-credential` / `user-not-found` /
  /// `wrong-password` are treated as a SUCCESSFUL connection — they prove the
  /// apiKey + project responded; only the throwaway probe credentials were
  /// rejected. Genuinely broken configuration (bad apiKey, unknown project,
  /// auth disabled, network failure) maps to a specific failure message.
  static FirebaseConfigConnectionResult classifyAuthFailure(
    FirebaseAuthException e,
    String projectId,
  ) {
    final message = (e.message ?? e.code).trim();
    switch (e.code) {
      // These responses prove the API key + project are valid and reachable —
      // the probe email/password simply does not match a real account.
      case 'invalid-credential':
      case 'invalid-login-credentials':
      case 'user-not-found':
      case 'wrong-password':
      case 'email-already-in-use':
        return FirebaseConfigConnectionResult.success(
          projectId: projectId,
          message: 'Connected to Firebase project "$projectId". '
              'The configuration is valid.',
        );
      case 'api-key-not-valid':
      case 'invalid-api-key':
      case 'api-key-expired':
      case 'invalid-apns-credentials':
        return const FirebaseConfigConnectionResult.failure(
          message: 'The API key is not valid for this project. Verify the '
              'apiKey copied from Firebase Console → Project settings → Your apps.',
        );
      case 'invalid-project-id':
      case 'project-not-found':
        return FirebaseConfigConnectionResult.failure(
          message: 'Firebase project "$projectId" was not found or the API key '
              'does not belong to it. Verify the projectId.',
        );
      case 'operation-not-allowed':
      case 'admin-restricted-operation':
        return const FirebaseConfigConnectionResult.failure(
          message: 'The project connected, but Email/Password sign-in is not '
              'enabled in Firebase Authentication. Enable it before provisioning.',
        );
      case 'network-request-failed':
        return const FirebaseConfigConnectionResult.failure(
          message: 'Network error while contacting Firebase. Check your '
              'connection and try again.',
        );
      default:
        return FirebaseConfigConnectionResult.failure(
          message: message.isEmpty
              ? 'Connection failed (${e.code}). Verify the configuration.'
              : message,
        );
    }
  }

  /// Maps a non-auth error from [testConnection] to a connection result.
  ///
  /// A "already exists" error means the config matched an app initialized
  /// earlier in the same session — a valid, reachable project.
  ///
  /// Raw HTTP 400 responses from the Identity Toolkit API (e.g.
  /// `EMAIL_NOT_FOUND`, `INVALID_LOGIN_CREDENTIALS`, `INVALID_PASSWORD`) are
  /// also treated as success because they prove the API key + project are
  /// reachable — only the throwaway probe credentials were rejected.
  static FirebaseConfigConnectionResult classifyGenericFailure(
    Object e,
    String projectId,
  ) {
    final raw = e.toString().replaceFirst('Exception: ', '');
    final lower = raw.toLowerCase();
    if (lower.contains('already exists')) {
      // The config matched an app already initialized in this session. That is
      // effectively a valid, reachable project.
      return FirebaseConfigConnectionResult.success(
        projectId: projectId,
        message: 'Connected to Firebase project "$projectId". '
            'The configuration is valid.',
      );
    }
    // Raw HTTP 400 from Identity Toolkit — proves the API key + project are
    // reachable; only the throwaway probe credentials were rejected.
    const authProbeSuccessPatterns = [
      'email_not_found',
      'invalid_login_credentials',
      'invalid_password',
      'invalid_email',
      'user_not_found',
      'wrong_password',
      'too_many_requests',
    ];
    if (authProbeSuccessPatterns.any(lower.contains)) {
      return FirebaseConfigConnectionResult.success(
        projectId: projectId,
        message: 'Connected to Firebase project "$projectId". '
            'The configuration is valid.',
      );
    }
    return FirebaseConfigConnectionResult.failure(
      message: raw.length > 400
          ? '${raw.substring(0, 400)}…'
          : 'Connection failed: $raw',
    );
  }

  static String _formatElapsed(int millis) {
    if (millis < 1000) return '$millis ms';
    return '${(millis / 1000).toStringAsFixed(1)} s';
  }

  static void debug(Object message) {
    debugPrint('[FirebaseConfigValidator] $message');
  }
}
