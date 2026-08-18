import 'package:firebase_core/firebase_core.dart';

/// How a workspace's Firebase configuration was provided during onboarding.
///
/// All three methods describe the SAME underlying client-side configuration
/// object; they differ only in how the consuming web app initializes the SDK:
///
/// 1. [npm] — `npm install firebase` + `initializeApp(firebaseConfig)`.
/// 2. [cdn] — Firebase CDN `<script>` tags + `firebase.initializeApp(...)`.
/// 3. [config] — the plain configuration object pasted/entered directly.
///
/// Stored on the workspace registry entry so the UI can re-present the exact
/// method the Super Admin used and never loses the SDK wiring metadata.
enum FirebaseConfigMethod {
  npm('npm', 'NPM'),
  cdn('cdn', 'CDN'),
  config('config', 'Config');

  const FirebaseConfigMethod(this.value, this.label);

  /// The persisted string value (written to Firestore).
  final String value;

  /// Human-readable label shown in the onboarding UI.
  final String label;

  /// The npm package that hosts the Firebase JS SDK, defaulting to `firebase`.
  String get npmPackageName => 'firebase';

  /// Resolves a stored string back to a [FirebaseConfigMethod], defaulting to
  /// [config] for legacy records written before the method field existed.
  static FirebaseConfigMethod fromValue(String? value) {
    switch (value) {
      case 'npm':
        return FirebaseConfigMethod.npm;
      case 'cdn':
        return FirebaseConfigMethod.cdn;
      default:
        return FirebaseConfigMethod.config;
    }
  }
}

/// Firebase project configuration for a workspace's tenant (data plane)
/// Firebase project.
///
/// Stored in the Master Firebase control plane inside the
/// `workspaces/{workspaceId}` registry document as an embedded
/// `firebaseConfig` map. The field set mirrors [FirebaseOptions] so a tenant
/// app can be initialized dynamically via [toFirebaseOptions].
class WorkspaceFirebaseConfig {
  final String apiKey;
  final String appId;
  final String projectId;
  final String messagingSenderId;
  final String storageBucket;
  final String authDomain;

  /// Analytics measurement id (web), optional.
  final String? measurementId;

  /// iOS-specific, optional.
  final String? iosBundleId;
  final String? iosClientId;

  /// Android-specific, optional.
  final String? androidClientId;

  /// How this configuration was provided (NPM / CDN / Config). Pure metadata —
  /// the tenant app initializes from the same fields regardless of method.
  final FirebaseConfigMethod configMethod;

  /// NPM package name used by the web app (e.g. `firebase`). Only meaningful
  /// when [configMethod] is [FirebaseConfigMethod.npm].
  final String npmPackage;

  /// Firebase JS SDK version (e.g. `11.6.0`). Meaningful for
  /// [FirebaseConfigMethod.npm] and [FirebaseConfigMethod.cdn].
  final String sdkVersion;

  /// The CDN `<script>` src used by the web app (e.g.
  /// `https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js`).
  /// Only meaningful when [configMethod] is [FirebaseConfigMethod.cdn].
  final String cdnUrl;

  const WorkspaceFirebaseConfig({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.messagingSenderId,
    required this.storageBucket,
    required this.authDomain,
    this.measurementId,
    this.iosBundleId,
    this.iosClientId,
    this.androidClientId,
    this.configMethod = FirebaseConfigMethod.config,
    this.npmPackage = '',
    this.sdkVersion = '',
    this.cdnUrl = '',
  });

  factory WorkspaceFirebaseConfig.fromMap(Map<String, dynamic> data) {
    return WorkspaceFirebaseConfig(
      apiKey: data['apiKey'] as String? ?? '',
      appId: data['appId'] as String? ?? '',
      projectId: data['projectId'] as String? ?? '',
      messagingSenderId: data['messagingSenderId'] as String? ?? '',
      storageBucket: data['storageBucket'] as String? ?? '',
      authDomain: data['authDomain'] as String? ?? '',
      measurementId: data['measurementId'] as String?,
      iosBundleId: data['iosBundleId'] as String?,
      iosClientId: data['iosClientId'] as String?,
      androidClientId: data['androidClientId'] as String?,
      configMethod:
          FirebaseConfigMethod.fromValue(data['configMethod'] as String?),
      npmPackage: data['npmPackage'] as String? ?? '',
      sdkVersion: data['sdkVersion'] as String? ?? '',
      cdnUrl: data['cdnUrl'] as String? ?? '',
    );
  }

  /// Captures an existing [FirebaseOptions] object (e.g. the default project's
  /// options) so it can be persisted in the registry.
  factory WorkspaceFirebaseConfig.fromFirebaseOptions(FirebaseOptions options) {
    return WorkspaceFirebaseConfig(
      apiKey: options.apiKey,
      appId: options.appId,
      projectId: options.projectId,
      messagingSenderId: options.messagingSenderId,
      storageBucket: options.storageBucket ?? '',
      authDomain: options.authDomain ?? '',
      measurementId: options.measurementId,
      iosBundleId: options.iosBundleId,
      iosClientId: options.iosClientId,
      androidClientId: options.androidClientId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'apiKey': apiKey,
      'appId': appId,
      'projectId': projectId,
      'messagingSenderId': messagingSenderId,
      'storageBucket': storageBucket,
      'authDomain': authDomain,
      'configMethod': configMethod.value,
      if (measurementId != null) 'measurementId': measurementId,
      if (iosBundleId != null) 'iosBundleId': iosBundleId,
      if (iosClientId != null) 'iosClientId': iosClientId,
      if (androidClientId != null) 'androidClientId': androidClientId,
      if (npmPackage.isNotEmpty) 'npmPackage': npmPackage,
      if (sdkVersion.isNotEmpty) 'sdkVersion': sdkVersion,
      if (cdnUrl.isNotEmpty) 'cdnUrl': cdnUrl,
    };
  }

  /// Whether this configuration carries enough credentials to initialize a
  /// Firebase app. A workspace whose config is missing required values has not
  /// been provisioned yet and cannot be bootstrapped.
  bool get isValid =>
      apiKey.isNotEmpty &&
      appId.isNotEmpty &&
      projectId.isNotEmpty &&
      messagingSenderId.isNotEmpty;

  /// Bridges this configuration to [FirebaseOptions] so the tenant app can be
  /// initialized with `FirebaseManager.initializeTenantApp()`.
  FirebaseOptions toFirebaseOptions() {
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
      storageBucket: storageBucket,
      authDomain: authDomain,
      measurementId: measurementId,
      iosBundleId: iosBundleId,
      iosClientId: iosClientId,
      androidClientId: androidClientId,
    );
  }

  /// The `npm install` command generated for an NPM-method config.
  String get npmInstallCommand {
    final package = npmPackage.trim().isEmpty ? 'firebase' : npmPackage.trim();
    final version = sdkVersion.trim();
    return 'npm install $package${version.isEmpty ? '' : '@$version'}';
  }

  /// The Firebase CDN `<script>` tag generated for a CDN-method config.
  ///
  /// Falls back to a version-aware default `firebase-app-compat` script when
  /// no explicit [cdnUrl] was stored.
  String get cdnScriptTag {
    if (cdnUrl.trim().isNotEmpty) return '<script src="${cdnUrl.trim()}"></script>';
    final version = sdkVersion.trim();
    return '<script src="https://www.gstatic.com/firebasejs/'
        '${version.isEmpty ? '10.14.1' : version}/firebase-app-compat.js"></script>';
  }

  /// A copy of this config with [configMethod] (and any method metadata)
  /// updated.
  WorkspaceFirebaseConfig withMethod(
    FirebaseConfigMethod method, {
    String? npmPackage,
    String? sdkVersion,
    String? cdnUrl,
  }) {
    return WorkspaceFirebaseConfig(
      apiKey: apiKey,
      appId: appId,
      projectId: projectId,
      messagingSenderId: messagingSenderId,
      storageBucket: storageBucket,
      authDomain: authDomain,
      measurementId: measurementId,
      iosBundleId: iosBundleId,
      iosClientId: iosClientId,
      androidClientId: androidClientId,
      configMethod: method,
      npmPackage: npmPackage ?? this.npmPackage,
      sdkVersion: sdkVersion ?? this.sdkVersion,
      cdnUrl: cdnUrl ?? this.cdnUrl,
    );
  }
}
