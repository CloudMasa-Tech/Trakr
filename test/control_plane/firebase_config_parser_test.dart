import 'package:attendqr/control_plane/models/workspace_firebase_config.dart';
import 'package:attendqr/control_plane/services/firebase_config_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const validWebJson = '''
{
  "apiKey": "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  "appId": "1:123456789012:web:abcdef0123456789",
  "projectId": "my-company-firebase",
  "storageBucket": "my-company-firebase.appspot.com",
  "authDomain": "my-company-firebase.firebaseapp.com",
  "messagingSenderId": "123456789012"
}
''';

const validAndroidJson = '''
{
  "project_info": {
    "project_number": "123456789012",
    "project_id": "my-company-firebase",
    "storage_bucket": "my-company-firebase.appspot.com"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:123456789012:android:abcdef0123456789"
      },
      "api_key": [
        { "current_key": "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" }
      ]
    }
  ]
}
''';

const validIosJson = '''
{
  "PROJECT_ID": "my-company-firebase",
  "GOOGLE_APP_ID": "1:123456789012:ios:abcdef0123456789",
  "API_KEY": "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
  "GCM_SENDER_ID": "123456789012",
  "STORAGE_BUCKET": "my-company-firebase.appspot.com"
}
''';

const serviceAccountJson = '''
{
  "type": "service_account",
  "project_id": "my-company-firebase",
  "private_key": "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----"
}
''';

void main() {
  group('FirebaseConfigParser', () {
    test('rejects empty input', () {
      final result = FirebaseConfigParser.parse('   ');
      expect(result.isValid, isFalse);
      expect(result.error, FirebaseConfigParseError.empty);
    });

    test('rejects non-JSON', () {
      final result = FirebaseConfigParser.parse('not json at all');
      expect(result.isValid, isFalse);
      expect(result.error, FirebaseConfigParseError.notJson);
    });

    test('rejects a JSON array root', () {
      final result = FirebaseConfigParser.parse('[1, 2, 3]');
      expect(result.isValid, isFalse);
      expect(result.error, FirebaseConfigParseError.notObject);
    });

    test('rejects service-account / Admin SDK keys', () {
      final result = FirebaseConfigParser.parse(serviceAccountJson);
      expect(result.isValid, isFalse);
      expect(result.error, FirebaseConfigParseError.serviceAccountKey);
    });

    test('rejects payloads without a projectId', () {
      final result =
          FirebaseConfigParser.parse('{"apiKey": "AIzaSyAAAAAAAAAAAAA"}');
      expect(result.isValid, isFalse);
      expect(result.error, FirebaseConfigParseError.missingProjectId);
    });

    test('rejects incomplete web config', () {
      final result = FirebaseConfigParser.parse('''
        {"projectId": "my-company-firebase", "apiKey": "AIzaSyAAAAAAAAAAAAA"}
      ''');
      expect(result.isValid, isFalse);
      expect(result.error, FirebaseConfigParseError.incomplete);
    });

    test('parses a flat web-app config', () {
      final result = FirebaseConfigParser.parse(validWebJson);
      expect(result.isValid, isTrue);
      expect(result.source, FirebaseConfigSource.web);
      expect(result.projectId, 'my-company-firebase');
      final config = result.config!;
      expect(config.apiKey, startsWith('AIzaSy'));
      expect(config.appId, contains(':web:'));
      expect(config.messagingSenderId, '123456789012');
      expect(config.configMethod.name, 'config');
      expect(config.isValid, isTrue);
    });

    test('parses a google-services.json payload', () {
      final result = FirebaseConfigParser.parse(validAndroidJson);
      expect(result.isValid, isTrue);
      expect(result.source, FirebaseConfigSource.googleServices);
      expect(result.projectId, 'my-company-firebase');
      expect(result.config!.appId, contains(':android:'));
      expect(result.config!.apiKey, startsWith('AIzaSy'));
    });

    test('parses an iOS plist JSON payload', () {
      final result = FirebaseConfigParser.parse(validIosJson);
      expect(result.isValid, isTrue);
      expect(result.source, FirebaseConfigSource.iOSPlist);
      expect(result.projectId, 'my-company-firebase');
      expect(result.config!.appId, contains(':ios:'));
      expect(result.config!.messagingSenderId, '123456789012');
    });

    test('parsed config round-trips through toMap/fromMap', () {
      final parsed = FirebaseConfigParser.parse(validWebJson).config!;
      final restored = WorkspaceFirebaseConfig.fromMap(parsed.toMap());
      expect(restored.projectId, parsed.projectId);
      expect(restored.configMethod, parsed.configMethod);
    });
  });
}
