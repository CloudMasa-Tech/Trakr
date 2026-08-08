import 'package:firebase_core/firebase_core.dart';

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
      if (measurementId != null) 'measurementId': measurementId,
      if (iosBundleId != null) 'iosBundleId': iosBundleId,
      if (iosClientId != null) 'iosClientId': iosClientId,
      if (androidClientId != null) 'androidClientId': androidClientId,
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
}
