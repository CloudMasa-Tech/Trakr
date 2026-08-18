import 'package:attendqr/control_plane/models/workspace_firebase_config.dart';
import 'package:attendqr/control_plane/services/firebase_config_validator.dart';
import 'package:attendqr/screens/super_admin/firebase_config_upload_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic connection-tester fake — simulates a successful live round
/// trip without any network or Firebase platform channel.
Future<FirebaseConfigConnectionResult> _successTester(
    WorkspaceFirebaseConfig config) async {
  return FirebaseConfigConnectionResult.success(
    projectId: config.projectId,
    message: 'Connected to Firebase project "${config.projectId}". '
        'The configuration is valid.',
  );
}

Future<FirebaseConfigConnectionResult> _failureTester(
    WorkspaceFirebaseConfig config) async {
  return const FirebaseConfigConnectionResult.failure(
    message: 'The API key is not valid for this project.',
  );
}

class UploadFieldHarness extends StatefulWidget {
  const UploadFieldHarness({
    super.key,
    required this.connectionTester,
    this.onParsed,
    this.onRemove,
    this.onConfirmedChanged,
  });

  final Future<FirebaseConfigConnectionResult> Function(
      WorkspaceFirebaseConfig) connectionTester;
  final void Function(WorkspaceFirebaseConfig)? onParsed;
  final VoidCallback? onRemove;
  final ValueChanged<bool>? onConfirmedChanged;

  @override
  State<UploadFieldHarness> createState() => _UploadFieldHarnessState();
}

class _UploadFieldHarnessState extends State<UploadFieldHarness> {
  WorkspaceFirebaseConfig? _config;
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FirebaseConfigUploadField(
            config: _config,
            confirmed: _confirmed,
            onParsed: (config) {
              setState(() => _config = config);
              widget.onParsed?.call(config);
            },
            onRemove: () {
              setState(() => _config = null);
              widget.onRemove?.call();
            },
            onConfirmedChanged: (value) {
              setState(() => _confirmed = value);
              widget.onConfirmedChanged?.call(value);
            },
            connectionTester: widget.connectionTester,
          ),
        ),
      ),
    );
  }
}

const goodFields = {
  'AIzaSy…': 'AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  '1:1234567890:web:abcdef': '1:123456789012:web:abcdef0123456789',
  'my-company-firebase': 'my-company-firebase',
  'my-company.firebaseapp.com': 'my-company.firebaseapp.com',
  'my-company.appspot.com': 'my-company.appspot.com',
  '123456789012': '123456789012',
  'G-XXXXXXXXXX': 'G-ABCDEFGH12',
};

Finder fieldWithHint(String hint) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    );

Future<void> enterAll(WidgetTester tester) async {
  for (final entry in goodFields.entries) {
    await tester.enterText(fieldWithHint(entry.key), entry.value);
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapValidate(WidgetTester tester) async {
  await tapVisible(
    tester,
    find.widgetWithText(FilledButton, 'Validate & Test Connection'),
  );
}

Finder get _pasteBox => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.maxLines == 8,
    );

void main() {
  Future<UploadFieldHarness> pumpField(
    WidgetTester tester, {
    Future<FirebaseConfigConnectionResult> Function(
        WorkspaceFirebaseConfig)? connectionTester,
    void Function(WorkspaceFirebaseConfig)? onParsed,
    VoidCallback? onRemove,
    ValueChanged<bool>? onConfirmedChanged,
  }) async {
    final harness = UploadFieldHarness(
      connectionTester: connectionTester ?? _successTester,
      onParsed: onParsed,
      onRemove: onRemove,
      onConfirmedChanged: onConfirmedChanged,
    );
    await tester.pumpWidget(harness);
    return harness;
  }

  group('method selector & field visibility', () {
    testWidgets('Config is the default method and shows only config fields',
        (tester) async {
      await pumpField(tester);
      expect(find.text('Configuration method'), findsOneWidget);
      expect(find.text('NPM'), findsOneWidget);
      expect(find.text('CDN'), findsOneWidget);
      expect(find.text('Config'), findsOneWidget);

      expect(find.text('Firebase configuration object'), findsOneWidget);
      expect(find.text('SDK package & version'), findsNothing);
      expect(find.text('CDN script & version'), findsNothing);
      for (final hint in goodFields.keys) {
        expect(fieldWithHint(hint), findsOneWidget,
            reason: 'hint "$hint" must be visible in Config mode');
      }
    });

    testWidgets('NPM shows SDK fields and a live npm install preview',
        (tester) async {
      await pumpField(tester);
      await tester.tap(find.text('NPM'));
      await tester.pumpAndSettle();

      expect(find.text('SDK package & version'), findsOneWidget);
      // "NPM package" is both the method-hint title and the field label.
      expect(find.text('NPM package'), findsWidgets);
      expect(find.text('SDK version'), findsOneWidget);
      expect(find.text('npm install firebase'), findsOneWidget);
      expect(find.text('CDN script & version'), findsNothing);

      await tester.enterText(fieldWithHint('firebase'), 'firebase');
      await tester.enterText(fieldWithHint('11.6.0'), '11.6.0');
      await tester.pump();
      expect(find.text('npm install firebase@11.6.0'), findsOneWidget);
    });

    testWidgets('CDN shows script fields and a live script preview',
        (tester) async {
      await pumpField(tester);
      await tester.tap(find.text('CDN'));
      await tester.pumpAndSettle();

      expect(find.text('CDN script & version'), findsOneWidget);
      expect(find.text('SDK version'), findsOneWidget);
      expect(find.text('CDN script URL'), findsOneWidget);
      // Default fallback script before any version is entered.
      expect(
        find.textContaining('www.gstatic.com/firebasejs/10.14.1'),
        findsOneWidget,
      );
      expect(find.text('SDK package & version'), findsNothing);

      await tester.enterText(fieldWithHint('11.6.0'), '11.6.0');
      await tester.pump();
      // The preview now uses the entered version; the URL field hint also
      // contains the same gstatic path, so this can appear more than once.
      expect(
        find.textContaining('/firebasejs/11.6.0/firebase-app-compat.js'),
        findsWidgets,
      );

      await tester.enterText(
        fieldWithHint(
            'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js'),
        'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js',
      );
      await tester.pump();
      expect(
        find.text('<script src="https://www.gstatic.com/firebasejs/11.6.0/'
            'firebase-app-compat.js"></script>'),
        findsOneWidget,
      );
    });
  });

  group('validation blocking', () {
    testWidgets('missing required fields blocks acceptance with inline errors',
        (tester) async {
      var parsed = false;
      await pumpField(tester, onParsed: (_) => parsed = true);

      await tapValidate(tester);

      // Each field error renders both in the InputDecoration and as an inline
      // message under the field.
      expect(find.text('API key is required.'), findsWidgets);
      expect(find.text('App ID is required.'), findsWidgets);
      expect(find.text('Project ID is required.'), findsWidgets);
      expect(find.text('Messaging sender ID is required.'), findsWidgets);
      expect(
        find.text('Auth domain is required (e.g. '
            'project-id.firebaseapp.com).'),
        findsWidgets,
      );
      expect(
        find.text('Storage bucket is required (e.g. '
            'project-id.appspot.com).'),
        findsWidgets,
      );
      expect(find.text('Fix the highlighted fields, then validate again.'),
          findsOneWidget);
      expect(find.text('Configuration validated & connection verified'),
          findsNothing);
      expect(parsed, isFalse);
    });

    testWidgets('invalid values are flagged and never accepted',
        (tester) async {
      var parsed = false;
      await pumpField(tester, onParsed: (_) => parsed = true);

      await tester.enterText(fieldWithHint('AIzaSy…'), 'short');
      await tester.enterText(
          fieldWithHint('1:1234567890:web:abcdef'), 'not-an-app-id');
      await tester.enterText(fieldWithHint('my-company-firebase'), 'Bad_Project');
      await tester.enterText(fieldWithHint('123456789012'), 'twelve');
      await tester.enterText(
          fieldWithHint('my-company.firebaseapp.com'), 'not a domain');
      await tester.enterText(fieldWithHint('my-company.appspot.com'), 'nope');
      await tester.enterText(fieldWithHint('G-XXXXXXXXXX'), 'X-1');
      await tapValidate(tester);

      expect(
        find.text(
            'API key looks too short to be a real Firebase web API key.'),
        findsWidgets,
      );
      expect(
        find.text('App ID should look like 1:1234567890:web:abcdef….'),
        findsWidgets,
      );
      expect(
        find.text(
            'Project ID can only contain lowercase letters, digits and hyphens.'),
        findsWidgets,
      );
      expect(
        find.text('Messaging sender ID must be a numeric project number.'),
        findsWidgets,
      );
      expect(find.text('Auth domain does not look like a valid domain.'),
          findsWidgets);
      expect(
        find.text('Storage bucket does not look like a valid bucket domain.'),
        findsWidgets,
      );
      expect(
        find.text('Measurement ID should look like G-XXXXXXXXXX.'),
        findsWidgets,
      );
      expect(find.text('Configuration validated & connection verified'),
          findsNothing);
      expect(parsed, isFalse);
    });

    testWidgets('a failing connection test blocks acceptance',
        (tester) async {
      var parsed = false;
      await pumpField(
        tester,
        connectionTester: _failureTester,
        onParsed: (_) => parsed = true,
      );

      await enterAll(tester);
      await tapValidate(tester);

      expect(find.text('The API key is not valid for this project.'),
          findsOneWidget);
      expect(find.text('Configuration validated & connection verified'),
          findsNothing);
      expect(parsed, isFalse);
    });
  });

  group('successful accept path', () {
    testWidgets('Config method: valid values + connection -> parsed card',
        (tester) async {
      WorkspaceFirebaseConfig? accepted;
      var confirmedCalls = 0;
      await pumpField(
        tester,
        onParsed: (config) => accepted = config,
        onConfirmedChanged: (_) => confirmedCalls++,
      );

      await enterAll(tester);
      await tapValidate(tester);

      expect(accepted, isNotNull);
      expect(accepted!.configMethod, FirebaseConfigMethod.config);

      // Parsed card shows badge, project id and no SDK preview for Config.
      expect(find.text('Configuration validated & connection verified'),
          findsOneWidget);
      expect(find.text('my-company-firebase'), findsWidgets);
      expect(find.text('Config'), findsOneWidget);
      expect(find.textContaining('npm install firebase'), findsNothing);

      // Confirm mapping toggles.
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(confirmedCalls, 1);
    });

    testWidgets('NPM method: parsed card shows NPM badge + install command',
        (tester) async {
      WorkspaceFirebaseConfig? accepted;
      await pumpField(tester, onParsed: (config) => accepted = config);

      await tester.tap(find.text('NPM'));
      await tester.pumpAndSettle();
      await tester.enterText(fieldWithHint('firebase'), 'firebase');
      await tester.enterText(fieldWithHint('11.6.0'), '11.6.0');
      await enterAll(tester);
      await tapValidate(tester);

      expect(accepted, isNotNull);
      expect(accepted!.configMethod, FirebaseConfigMethod.npm);
      expect(accepted!.npmPackage, 'firebase');
      expect(accepted!.sdkVersion, '11.6.0');
      expect(accepted!.npmInstallCommand, 'npm install firebase@11.6.0');

      expect(find.text('Configuration validated & connection verified'),
          findsOneWidget);
      expect(find.text('NPM'), findsOneWidget);
      expect(find.text('npm install firebase@11.6.0'), findsOneWidget);
    });

    testWidgets('CDN method: parsed card shows CDN badge + script tag',
        (tester) async {
      WorkspaceFirebaseConfig? accepted;
      await pumpField(tester, onParsed: (config) => accepted = config);

      await tester.tap(find.text('CDN'));
      await tester.pumpAndSettle();
      await tester.enterText(
        fieldWithHint(
            'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js'),
        'https://www.gstatic.com/firebasejs/11.6.0/firebase-app-compat.js',
      );
      await enterAll(tester);
      await tapValidate(tester);

      expect(accepted, isNotNull);
      expect(accepted!.configMethod, FirebaseConfigMethod.cdn);
      expect(accepted!.sdkVersion, isEmpty);
      expect(
        accepted!.cdnScriptTag,
        contains('https://www.gstatic.com/firebasejs/11.6.0/'),
      );

      expect(find.text('Configuration validated & connection verified'),
          findsOneWidget);
      expect(find.text('CDN'), findsOneWidget);
      expect(
        find.text('<script src="https://www.gstatic.com/firebasejs/11.6.0/'
            'firebase-app-compat.js"></script>'),
        findsOneWidget,
      );
    });

    testWidgets('remove clears the accepted configuration', (tester) async {
      var removed = false;
      await pumpField(tester, onRemove: () => removed = true);

      await enterAll(tester);
      await tapValidate(tester);
      expect(find.text('Configuration validated & connection verified'),
          findsOneWidget);

      await tapVisible(tester, find.byIcon(Icons.delete_outline_rounded));
      expect(removed, isTrue);
      expect(find.text('Configuration validated & connection verified'),
          findsNothing);
    });
  });

  group('paste / upload JSON flow', () {
    testWidgets('valid web config JSON is accepted via paste',
        (tester) async {
      WorkspaceFirebaseConfig? accepted;
      await pumpField(tester, onParsed: (config) => accepted = config);

      await tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Paste / upload JSON'),
      );

      await tester.enterText(
        _pasteBox,
        '{"apiKey": "AIzaSyAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", '
        '"appId": "1:123456789012:web:abcdef0123456789", '
        '"projectId": "paste-project", '
        '"storageBucket": "paste-project.appspot.com", '
        '"authDomain": "paste-project.firebaseapp.com", '
        '"messagingSenderId": "123456789012"}',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Validate & detect project id'),
      );

      expect(accepted, isNotNull);
      expect(accepted!.projectId, 'paste-project');
      expect(accepted!.configMethod, FirebaseConfigMethod.config);
      expect(find.text('paste-project'), findsWidgets);
    });

    testWidgets('service-account / private-key payloads are rejected',
        (tester) async {
      var parsed = false;
      await pumpField(tester, onParsed: (_) => parsed = true);

      await tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Paste / upload JSON'),
      );

      await tester.enterText(
        _pasteBox,
        '{"type": "service_account", "project_id": "x", '
        '"private_key": "-----BEGIN PRIVATE KEY-----"}',
      );
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Validate & detect project id'),
      );

      // The paste view footer also mentions serviceAccountKey.json, so the
      // rejection message may coexist with it.
      expect(find.textContaining('serviceAccountKey.json'), findsWidgets);
      expect(
        find.text(
            'This is a serviceAccountKey.json / Admin SDK private key. '
            'Upload the client-side configuration instead: Firebase Console → '
            'Project settings → Your apps → (web app) → SDK setup and '
            'configuration.'),
        findsOneWidget,
      );
      expect(find.text('Configuration validated & connection verified'),
          findsNothing);
      expect(parsed, isFalse);
    });

    testWidgets('non-JSON input is rejected with a clear message',
        (tester) async {
      await pumpField(tester);

      await tapVisible(
        tester,
        find.widgetWithText(OutlinedButton, 'Paste / upload JSON'),
      );

      await tester.enterText(_pasteBox, 'this is not json');
      await tapVisible(
        tester,
        find.widgetWithText(FilledButton, 'Validate & detect project id'),
      );

      expect(
        find.text(
            'That is not valid JSON. Paste the raw configuration text.'),
        findsOneWidget,
      );
    });
  });
}
