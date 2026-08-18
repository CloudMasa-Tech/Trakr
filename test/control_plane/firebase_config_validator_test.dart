import 'package:attendqr/control_plane/models/workspace_firebase_config.dart';
import 'package:attendqr/control_plane/services/firebase_config_validator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

const validFields = {
  'apiKey': 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  'appId': '1:123456789012:web:abcdef0123456789',
  'projectId': 'my-company-firebase',
  'messagingSenderId': '123456789012',
  'storageBucket': 'my-company-firebase.appspot.com',
  'authDomain': 'my-company-firebase.firebaseapp.com',
};

List<FirebaseConfigFieldError> validate({
  FirebaseConfigMethod method = FirebaseConfigMethod.config,
  Map<String, String> overrides = const {},
  String npmPackage = '',
  String sdkVersion = '',
  String cdnUrl = '',
  String? measurementId,
}) {
  final fields = {...validFields, ...overrides};
  return FirebaseConfigValidator.validateStructure(
    method: method,
    apiKey: fields['apiKey']!,
    appId: fields['appId']!,
    projectId: fields['projectId']!,
    messagingSenderId: fields['messagingSenderId']!,
    authDomain: fields['authDomain']!,
    storageBucket: fields['storageBucket']!,
    measurementId: measurementId,
    npmPackage: npmPackage,
    sdkVersion: sdkVersion,
    cdnUrl: cdnUrl,
  );
}

Matcher hasErrorFor(String field) =>
    contains(predicate<FirebaseConfigFieldError>((e) => e.field == field));

void main() {
  group('validateStructure — Config method', () {
    test('accepts a fully valid config', () {
      expect(validate(), isEmpty);
    });

    test('rejects every missing required field', () {
      for (final key in [
        'apiKey',
        'appId',
        'projectId',
        'messagingSenderId',
        'storageBucket',
        'authDomain',
      ]) {
        final errors = validate(overrides: {key: ''});
        expect(errors, hasErrorFor(key),
            reason: 'empty "$key" must fail validation');
      }
    });

    test('rejects a too-short API key', () {
      final errors = validate(overrides: {'apiKey': 'short'});
      expect(errors, hasErrorFor('apiKey'));
    });

    test('rejects an App ID without the number:platform:hash shape', () {
      final errors = validate(overrides: {'appId': 'not-an-app-id'});
      expect(errors, hasErrorFor('appId'));
    });

    test('rejects project ids with uppercase or special characters', () {
      for (final bad in ['My-Project', 'my project', 'my_project']) {
        final errors = validate(overrides: {'projectId': bad});
        expect(errors, hasErrorFor('projectId'), reason: '"$bad" must fail');
      }
    });

    test('rejects non-numeric messaging sender ids', () {
      final errors = validate(overrides: {'messagingSenderId': 'abc'});
      expect(errors, hasErrorFor('messagingSenderId'));
    });

    test('rejects malformed auth domains and storage buckets', () {
      expect(
        validate(overrides: {'authDomain': 'not a domain'}),
        hasErrorFor('authDomain'),
      );
      expect(
        validate(overrides: {'storageBucket': 'nope'}),
        hasErrorFor('storageBucket'),
      );
    });

    test('rejects a malformed measurement id when provided', () {
      final errors = validate(measurementId: 'X-123');
      expect(errors, hasErrorFor('measurementId'));
      expect(validate(measurementId: 'G-ABCDEF12'), isEmpty);
    });

    test('Config method never requires SDK fields', () {
      expect(validate(method: FirebaseConfigMethod.config), isEmpty);
    });
  });

  group('validateStructure — NPM method', () {
    test('accepts package + version', () {
      expect(
        validate(
          method: FirebaseConfigMethod.npm,
          npmPackage: 'firebase',
          sdkVersion: '11.6.0',
        ),
        isEmpty,
      );
    });

    test('accepts an empty package (falls back to firebase)', () {
      expect(validate(method: FirebaseConfigMethod.npm), isEmpty);
    });

    test('rejects a package name with invalid characters', () {
      final errors = validate(
        method: FirebaseConfigMethod.npm,
        npmPackage: 'firebase ; rm -rf',
      );
      expect(errors, hasErrorFor('npmPackage'));
    });

    test('rejects a malformed SDK version', () {
      final errors = validate(
        method: FirebaseConfigMethod.npm,
        sdkVersion: 'v11',
      );
      expect(errors, hasErrorFor('sdkVersion'));
    });
  });

  group('validateStructure — CDN method', () {
    test('accepts a script URL', () {
      expect(
        validate(
          method: FirebaseConfigMethod.cdn,
          cdnUrl:
              'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js',
        ),
        isEmpty,
      );
    });

    test('accepts a version alone (default script is derived)', () {
      expect(
        validate(method: FirebaseConfigMethod.cdn, sdkVersion: '11.6.0'),
        isEmpty,
      );
    });

    test('requires a URL or a version', () {
      final errors = validate(method: FirebaseConfigMethod.cdn);
      expect(errors, hasErrorFor('cdnUrl'));
    });

    test('rejects a non-gstatic, non-https script URL', () {
      final errors = validate(
        method: FirebaseConfigMethod.cdn,
        cdnUrl: 'http://evil.example/firebase.js',
      );
      expect(errors, hasErrorFor('cdnUrl'));
    });

    test('rejects a malformed SDK version', () {
      final errors = validate(
        method: FirebaseConfigMethod.cdn,
        sdkVersion: 'latest',
      );
      expect(errors, hasErrorFor('sdkVersion'));
    });
  });

  group('isPlatformProject', () {
    test('returns false when no Firebase app is initialized', () {
      // In a bare test environment there is no default app; a platform-project
      // check must degrade to "not the platform project" instead of throwing.
      expect(FirebaseConfigValidator.isPlatformProject('anything'), isFalse);
    });
  });

  group('classifyAuthFailure — connection test decision matrix', () {
    FirebaseConfigConnectionResult classify(String code, [String message = '']) {
      return FirebaseConfigValidator.classifyAuthFailure(
        FirebaseAuthException(code: code, message: message),
        'my-company-firebase',
      );
    }

    test('credential rejection codes prove a valid, reachable project', () {
      for (final code in [
        'invalid-credential',
        'invalid-login-credentials',
        'user-not-found',
        'wrong-password',
        'email-already-in-use',
      ]) {
        final result = classify(code);
        expect(result.success, isTrue, reason: '"$code" must mean connected');
        expect(result.projectId, 'my-company-firebase');
      }
    });

    test('invalid API key codes produce a specific failure', () {
      for (final code in [
        'api-key-not-valid',
        'invalid-api-key',
        'api-key-expired',
      ]) {
        final result = classify(code);
        expect(result.success, isFalse);
        expect(result.message.toLowerCase(), contains('api key'));
      }
    });

    test('unknown project codes produce a specific failure', () {
      for (final code in ['invalid-project-id', 'project-not-found']) {
        final result = classify(code);
        expect(result.success, isFalse);
        expect(result.message, contains('my-company-firebase'));
      }
    });

    test('auth-disabled codes produce a specific failure', () {
      for (final code in ['operation-not-allowed', 'admin-restricted-operation']) {
        final result = classify(code);
        expect(result.success, isFalse);
        expect(result.message.toLowerCase(), contains('sign-in'));
      }
    });

    test('network failures produce a specific failure', () {
      final result = classify('network-request-failed');
      expect(result.success, isFalse);
      expect(result.message.toLowerCase(), contains('network'));
    });

    test('unknown codes fall back to the raw message', () {
      final result = classify('some-unknown-code', 'Something went wrong');
      expect(result.success, isFalse);
      expect(result.message, contains('Something went wrong'));
    });
  });

  group('classifyGenericFailure', () {
    test('already-exists means the config was used successfully', () {
      final result = FirebaseConfigValidator.classifyGenericFailure(
        StateError('Firebase app named trakr-config-test-123 already exists'),
        'my-company-firebase',
      );
      expect(result.success, isTrue);
      expect(result.projectId, 'my-company-firebase');
    });

    test('any other error is surfaced as a failure', () {
      final result = FirebaseConfigValidator.classifyGenericFailure(
        Exception('boom'),
        'my-company-firebase',
      );
      expect(result.success, isFalse);
      expect(result.message, contains('boom'));
    });
  });

  group('result + error value objects', () {
    test('success result carries projectId and success=true', () {
      const result = FirebaseConfigConnectionResult.success(
        message: 'Connected.',
        projectId: 'p-1',
      );
      expect(result.success, isTrue);
      expect(result.projectId, 'p-1');
      expect(result.message, 'Connected.');
    });

    test('failure result carries success=false and no projectId', () {
      const result = FirebaseConfigConnectionResult.failure(
        message: 'Nope.',
      );
      expect(result.success, isFalse);
      expect(result.projectId, isNull);
    });

    test('validation exception aggregates field errors', () {
      const errors = [
        FirebaseConfigFieldError('apiKey', 'API key is required.'),
        FirebaseConfigFieldError('projectId', 'Project ID is required.'),
      ];
      const exception = FirebaseConfigValidationException(errors);
      expect(exception.message, contains('API key is required.'));
      expect(exception.fieldErrors['projectId'], 'Project ID is required.');
    });
  });
}
