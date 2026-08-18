import 'package:attendqr/control_plane/models/workspace_firebase_config.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebaseConfigMethod', () {
    test('exposes the persisted value and display label', () {
      expect(FirebaseConfigMethod.npm.value, 'npm');
      expect(FirebaseConfigMethod.npm.label, 'NPM');
      expect(FirebaseConfigMethod.cdn.value, 'cdn');
      expect(FirebaseConfigMethod.cdn.label, 'CDN');
      expect(FirebaseConfigMethod.config.value, 'config');
      expect(FirebaseConfigMethod.config.label, 'Config');
    });

    test('fromValue resolves every stored string', () {
      expect(FirebaseConfigMethod.fromValue('npm'), FirebaseConfigMethod.npm);
      expect(FirebaseConfigMethod.fromValue('cdn'), FirebaseConfigMethod.cdn);
      expect(FirebaseConfigMethod.fromValue('config'), FirebaseConfigMethod.config);
    });

    test('fromValue defaults legacy/null/unknown records to config', () {
      expect(FirebaseConfigMethod.fromValue(null), FirebaseConfigMethod.config);
      expect(FirebaseConfigMethod.fromValue(''), FirebaseConfigMethod.config);
      expect(FirebaseConfigMethod.fromValue('yarn'), FirebaseConfigMethod.config);
    });

    test('npm package default is firebase', () {
      expect(FirebaseConfigMethod.npm.npmPackageName, 'firebase');
    });
  });

  const validFields = {
    'apiKey': 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    'appId': '1:123456789012:web:abcdef0123456789',
    'projectId': 'my-company-firebase',
    'messagingSenderId': '123456789012',
    'storageBucket': 'my-company-firebase.appspot.com',
    'authDomain': 'my-company-firebase.firebaseapp.com',
  };

  WorkspaceFirebaseConfig config({FirebaseConfigMethod method = FirebaseConfigMethod.config}) {
    return WorkspaceFirebaseConfig(
      apiKey: validFields['apiKey']!,
      appId: validFields['appId']!,
      projectId: validFields['projectId']!,
      messagingSenderId: validFields['messagingSenderId']!,
      storageBucket: validFields['storageBucket']!,
      authDomain: validFields['authDomain']!,
      measurementId: 'G-ABCDEFGH12',
      configMethod: method,
      npmPackage: method == FirebaseConfigMethod.npm ? 'firebase' : '',
      sdkVersion: '11.6.0',
      cdnUrl: 'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js',
    );
  }

  group('WorkspaceFirebaseConfig serialization round-trip', () {
    test('config method persists through toMap/fromMap', () {
      for (final method in FirebaseConfigMethod.values) {
        final original = config(method: method);
        final restored = WorkspaceFirebaseConfig.fromMap(original.toMap());
        expect(restored.configMethod, method,
            reason: 'configMethod must survive serialization for $method');
        expect(restored.apiKey, original.apiKey);
        expect(restored.appId, original.appId);
        expect(restored.projectId, original.projectId);
        expect(restored.messagingSenderId, original.messagingSenderId);
        expect(restored.storageBucket, original.storageBucket);
        expect(restored.authDomain, original.authDomain);
        expect(restored.measurementId, original.measurementId);
      }
    });

    test('NPM metadata persists through toMap/fromMap', () {
      final original = config(method: FirebaseConfigMethod.npm);
      final restored = WorkspaceFirebaseConfig.fromMap(original.toMap());
      expect(restored.configMethod, FirebaseConfigMethod.npm);
      expect(restored.npmPackage, 'firebase');
      expect(restored.sdkVersion, '11.6.0');
    });

    test('CDN metadata persists through toMap/fromMap', () {
      final original = config(method: FirebaseConfigMethod.cdn);
      final restored = WorkspaceFirebaseConfig.fromMap(original.toMap());
      expect(restored.configMethod, FirebaseConfigMethod.cdn);
      expect(restored.sdkVersion, '11.6.0');
      expect(
        restored.cdnUrl,
        'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js',
      );
    });

    test('empty method metadata is omitted from the stored map', () {
      final map = WorkspaceFirebaseConfig.fromMap(validFields).toMap();
      expect(map.containsKey('npmPackage'), isFalse);
      expect(map.containsKey('sdkVersion'), isFalse);
      expect(map.containsKey('cdnUrl'), isFalse);
      expect(map['configMethod'], 'config');
    });

    test('legacy records without method metadata restore as config', () {
      final restored = WorkspaceFirebaseConfig.fromMap(validFields);
      expect(restored.configMethod, FirebaseConfigMethod.config);
      expect(restored.npmPackage, '');
      expect(restored.sdkVersion, '');
      expect(restored.cdnUrl, '');
    });
  });

  group('WorkspaceFirebaseConfig validity', () {
    test('isValid requires the four core credentials', () {
      expect(WorkspaceFirebaseConfig.fromMap(validFields).isValid, isTrue);
      expect(
        WorkspaceFirebaseConfig.fromMap({...validFields, 'apiKey': ''}).isValid,
        isFalse,
      );
      expect(
        WorkspaceFirebaseConfig.fromMap({...validFields, 'appId': ''}).isValid,
        isFalse,
      );
      expect(
        WorkspaceFirebaseConfig.fromMap({...validFields, 'projectId': ''})
            .isValid,
        isFalse,
      );
      expect(
        WorkspaceFirebaseConfig.fromMap({...validFields, 'messagingSenderId': ''})
            .isValid,
        isFalse,
      );
    });
  });

  group('WorkspaceFirebaseConfig helpers', () {
    test('npmInstallCommand uses the default firebase package', () {
      expect(config(method: FirebaseConfigMethod.npm).npmInstallCommand,
          'npm install firebase@11.6.0');
      final noVersion = config(method: FirebaseConfigMethod.npm).withMethod(
        FirebaseConfigMethod.npm,
        sdkVersion: '',
      );
      expect(noVersion.npmInstallCommand, 'npm install firebase');
      final custom = noVersion.withMethod(
        FirebaseConfigMethod.npm,
        npmPackage: '@firebase/app',
      );
      expect(custom.npmInstallCommand, 'npm install @firebase/app');
    });

    test('cdnScriptTag uses the stored URL when present', () {
      final cdn = config(method: FirebaseConfigMethod.cdn);
      expect(
        cdn.cdnScriptTag,
        '<script src="https://www.gstatic.com/firebasejs/11.6.0/'
        'firebase-app-compat.js"></script>',
      );
    });

    test('cdnScriptTag falls back to a version-aware default script', () {
      final noUrl = config(method: FirebaseConfigMethod.cdn)
          .withMethod(FirebaseConfigMethod.cdn, cdnUrl: '');
      expect(
        noUrl.cdnScriptTag,
        '<script src="https://www.gstatic.com/firebasejs/11.6.0/'
        'firebase-app-compat.js"></script>',
      );
      final noVersion = noUrl.withMethod(
        FirebaseConfigMethod.cdn,
        sdkVersion: '',
      );
      expect(
        noVersion.cdnScriptTag,
        '<script src="https://www.gstatic.com/firebasejs/10.14.1/'
        'firebase-app-compat.js"></script>',
      );
    });

    test('toFirebaseOptions bridges every credential field', () {
      final options = config().toFirebaseOptions();
      expect(options, isA<FirebaseOptions>());
      expect(options.apiKey, validFields['apiKey']);
      expect(options.appId, validFields['appId']);
      expect(options.projectId, validFields['projectId']);
      expect(options.messagingSenderId, validFields['messagingSenderId']);
      expect(options.storageBucket, validFields['storageBucket']);
      expect(options.authDomain, validFields['authDomain']);
      expect(options.measurementId, 'G-ABCDEFGH12');
    });

    test('withMethod swaps the method and metadata', () {
      final base = config(method: FirebaseConfigMethod.config);
      final npm = base.withMethod(FirebaseConfigMethod.npm,
          npmPackage: 'firebase', sdkVersion: '12.0.0');
      expect(npm.configMethod, FirebaseConfigMethod.npm);
      expect(npm.npmPackage, 'firebase');
      expect(npm.sdkVersion, '12.0.0');
      expect(npm.apiKey, base.apiKey);
      final cdn = base.withMethod(FirebaseConfigMethod.cdn,
          sdkVersion: '12.0.0',
          cdnUrl: 'https://www.gstatic.com/firebasejs/12.0.0/'
              'firebase-app-compat.js');
      expect(cdn.configMethod, FirebaseConfigMethod.cdn);
      expect(cdn.cdnScriptTag,
          contains('https://www.gstatic.com/firebasejs/12.0.0/'));
    });
  });
}
