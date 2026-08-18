import 'package:attendqr/control_plane/models/subscription.dart';
import 'package:attendqr/control_plane/models/workspace.dart';
import 'package:attendqr/control_plane/models/workspace_firebase_config.dart';
import 'package:attendqr/control_plane/models/workspace_status.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceFirebaseConfig sampleConfig(FirebaseConfigMethod method) {
  final isNpm = method == FirebaseConfigMethod.npm;
  final isCdn = method == FirebaseConfigMethod.cdn;
  return WorkspaceFirebaseConfig(
    apiKey: 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    appId: '1:123456789012:web:abcdef0123456789',
    projectId: 'green-hospital-firebase',
    messagingSenderId: '123456789012',
    storageBucket: 'green-hospital-firebase.appspot.com',
    authDomain: 'green-hospital-firebase.firebaseapp.com',
    configMethod: method,
    npmPackage: isNpm ? 'firebase' : '',
    sdkVersion: (isNpm || isCdn) ? '11.6.0' : '',
    cdnUrl: isCdn
        ? 'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js'
        : '',
  );
}

Workspace sampleWorkspace(FirebaseConfigMethod method) {
  return Workspace(
    workspaceId: 'ws-1',
    workspaceCode: 'green-hospital',
    companyName: 'Green Hospital',
    firebaseProjectId: 'green-hospital-firebase',
    firebaseConfig: sampleConfig(method),
    firebaseConfigured: true,
    status: WorkspaceStatus.active,
    onboardingStatus: WorkspaceOnboardingStatus.ready,
    subscription: const Subscription.empty(),
    supportEmail: 'admin@green-hospital.test',
  );
}

void main() {
  group('Workspace persistence — save then reload', () {
    test('config method + metadata survive the toMap/fromMap round-trip (NPM)',
        () {
      final workspace = sampleWorkspace(FirebaseConfigMethod.npm);
      final restored = Workspace.fromMap(workspace.toMap(), 'ws-1');
      expect(restored.firebaseConfig.configMethod, FirebaseConfigMethod.npm);
      expect(restored.firebaseConfig.npmPackage, 'firebase');
      expect(restored.firebaseConfig.sdkVersion, '11.6.0');
      expect(restored.firebaseConfig.cdnUrl, isEmpty);
      expect(restored.firebaseConfigured, isTrue);
    });

    test('config method + metadata survive the round-trip (CDN)', () {
      final workspace = sampleWorkspace(FirebaseConfigMethod.cdn);
      final restored = Workspace.fromMap(workspace.toMap(), 'ws-1');
      expect(restored.firebaseConfig.configMethod, FirebaseConfigMethod.cdn);
      expect(
        restored.firebaseConfig.cdnUrl,
        'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js',
      );
      expect(restored.firebaseConfig.sdkVersion, '11.6.0');
    });

    test('config method + metadata survive the round-trip (Config)', () {
      final workspace = sampleWorkspace(FirebaseConfigMethod.config);
      final restored = Workspace.fromMap(workspace.toMap(), 'ws-1');
      expect(restored.firebaseConfig.configMethod, FirebaseConfigMethod.config);
      expect(restored.firebaseConfig.npmPackage, isEmpty);
      expect(restored.firebaseConfig.cdnUrl, isEmpty);
    });

    test('identity, status and subscription fields survive the round-trip', () {
      final workspace = sampleWorkspace(FirebaseConfigMethod.config);
      final restored = Workspace.fromMap(workspace.toMap(), 'ws-1');
      expect(restored.workspaceId, 'ws-1');
      expect(restored.workspaceCode, 'green-hospital');
      expect(restored.companyName, 'Green Hospital');
      expect(restored.firebaseProjectId, 'green-hospital-firebase');
      expect(restored.status, WorkspaceStatus.active);
      expect(restored.onboardingStatus, WorkspaceOnboardingStatus.ready);
      expect(restored.supportEmail, 'admin@green-hospital.test');
    });

    test('reload preserves the tenant config and never fabricates credentials',
        () {
      final source = sampleWorkspace(FirebaseConfigMethod.npm);
      final restored = Workspace.fromMap(source.toMap(), 'ws-1');
      expect(restored.firebaseConfig.projectId, 'green-hospital-firebase');
      expect(restored.firebaseConfig.apiKey, isNotEmpty);
      expect(restored.firebaseConfig.appId, contains(':web:'));
      // The stored map is exactly the client config the Super Admin uploaded —
      // no server/admin fields are ever injected.
      final storedMap = restored.firebaseConfig.toMap();
      expect(storedMap.containsKey('private_key'), isFalse);
      expect(storedMap.containsKey('client_email'), isFalse);
      expect(storedMap['projectId'], 'green-hospital-firebase');
    });

    test('firebaseConfigured falls back to credential presence for legacy docs',
        () {
      final data = sampleWorkspace(FirebaseConfigMethod.config).toMap()
        ..remove('firebaseConfigured');
      final restored = Workspace.fromMap(data, 'ws-1');
      expect(restored.firebaseConfigured, isTrue);
    });

    test('legacy workspace without firebaseConfig stays unconfigured', () {
      final restored = Workspace.fromMap(
        {
          'workspaceId': 'ws-2',
          'workspaceCode': 'legacy',
          'companyName': 'Legacy Co',
          'firebaseProjectId': '',
          'status': 'active',
        },
        'ws-2',
      );
      expect(restored.firebaseConfigured, isFalse);
      expect(restored.firebaseConfig.configMethod, FirebaseConfigMethod.config);
    });
  });
}
