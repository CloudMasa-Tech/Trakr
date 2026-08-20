import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

/// Service for managing tenant Firebase project configuration via REST APIs.
///
/// All operations are scoped to a SPECIFIC tenant project ID — never the
/// master/control-plane project. Every method validates the target project ID
/// against the known master project ID and refuses to proceed if they match.
class TenantProjectConfigService {
  TenantProjectConfigService({
    required String masterProjectId,
    required String serviceAccountKeyPath,
  })  : _masterProjectId = masterProjectId,
        _serviceAccountKeyPath = serviceAccountKeyPath;

  final String _masterProjectId;
  final String _serviceAccountKeyPath;

  auth.AutoRefreshingAuthClient? _cachedClient;

  /// Gets an authenticated HTTP client for the service account.
  Future<auth.AutoRefreshingAuthClient> _getAuthClient() async {
    if (_cachedClient != null) {
      return _cachedClient!;
    }

    final credentials = auth.ServiceAccountCredentials.fromJson(
      await File(_serviceAccountKeyPath).readAsString(),
    );

    final scopes = [
      'https://www.googleapis.com/auth/firebase.database',
      'https://www.googleapis.com/auth/cloud-platform',
    ];

    _cachedClient = await auth.clientViaServiceAccount(credentials, scopes);
    return _cachedClient!;
  }

  /// Deploys Realtime Database rules to the tenant project via REST API.
  ///
  /// Uses the Firebase Rules REST API (modern, recommended):
  /// POST https://firebaserules.googleapis.com/v1/projects/{project_id}/releases
  ///
  /// Falls back to legacy database rules API if needed:
  /// PUT https://{databaseURL}/.settings/rules.json
  Future<void> deployDatabaseRules({
    required String tenantProjectId,
    required String databaseURL,
    required Map<String, dynamic> rulesContent,
  }) async {
    _assertNotMasterProject(tenantProjectId, 'deployDatabaseRules');

    final client = await _getAuthClient();

    // Try the modern Firebase Rules API first
    final rulesetUrl =
        'https://firebaserules.googleapis.com/v1/projects/$tenantProjectId/rulesets';
    final rulesetBody = {
      'source': {
        'files': [
          {
            'name': 'database.rules.json',
            'content': jsonEncode({'rules': rulesContent}),
          },
        ],
      },
    };

    final rulesetResponse = await client.post(
      Uri.parse(rulesetUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rulesetBody),
    );

    if (rulesetResponse.statusCode >= 400) {
      // Fall back to legacy API
      await _deployRulesLegacy(
        databaseURL: databaseURL,
        rulesContent: rulesContent,
        client: client,
      );
      return;
    }

    final rulesetData = jsonDecode(rulesetResponse.body) as Map<String, dynamic>;
    final rulesetName = rulesetData['name'] as String;

    // Create a release pointing to this ruleset
    final releaseUrl =
        'https://firebaserules.googleapis.com/v1/projects/$tenantProjectId/releases';
    final releaseBody = {
      'release': {
        'name': 'projects/$tenantProjectId/releases/prod',
        'rulesetName': rulesetName,
      },
    };

    final releaseResponse = await client.post(
      Uri.parse(releaseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(releaseBody),
    );

    if (releaseResponse.statusCode >= 400) {
      // Fall back to legacy API
      await _deployRulesLegacy(
        databaseURL: databaseURL,
        rulesContent: rulesContent,
        client: client,
      );
    }
  }

  /// Legacy RTDB rules deployment via database URL.
  Future<void> _deployRulesLegacy({
    required String databaseURL,
    required Map<String, dynamic> rulesContent,
    required auth.AutoRefreshingAuthClient client,
  }) async {
    final rulesUrl = '$databaseURL/.settings/rules.json';
    final response = await client.put(
      Uri.parse(rulesUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'rules': rulesContent}),
    );

    if (response.statusCode >= 400) {
      throw StateError(
          'Failed to deploy RTDB rules to $databaseURL: ${response.statusCode} ${response.body}');
    }
  }

  /// Verifies that the Realtime Database instance exists for the tenant project.
  ///
  /// Uses the Firebase Management API:
  /// GET https://firebase.googleapis.com/v1beta1/projects/{project_id}/locations/{location}/instances/{instance}
  Future<bool> verifyDatabaseInstanceExists({
    required String tenantProjectId,
    String location = 'us-central1',
    String instance = 'default',
  }) async {
    _assertNotMasterProject(tenantProjectId, 'verifyDatabaseInstanceExists');

    final client = await _getAuthClient();
    final url =
        'https://firebase.googleapis.com/v1beta1/projects/$tenantProjectId/locations/$location/instances/$instance';

    final response = await client.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 404) {
      return false;
    }
    if (response.statusCode >= 400) {
      throw StateError(
          'Failed to verify RTDB instance for $tenantProjectId: ${response.statusCode} ${response.body}');
    }
    return true;
  }

  /// Verifies that Email/Password authentication is enabled for the tenant project.
  ///
  /// Uses the Identity Toolkit (Firebase Auth) API:
  /// GET https://identitytoolkit.googleapis.com/v1/projects/{project_id}/config?key={apiKey}
  Future<bool> verifyEmailPasswordAuthEnabled({
    required String tenantProjectId,
    required String apiKey,
  }) async {
    _assertNotMasterProject(tenantProjectId, 'verifyEmailPasswordAuthEnabled');

    // This uses the public API key, not the service account
    final url =
        'https://identitytoolkit.googleapis.com/v1/projects/$tenantProjectId/config?key=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode >= 400) {
      throw StateError(
          'Failed to verify Email/Password auth for $tenantProjectId: ${response.statusCode} ${response.body}');
    }

    final config = jsonDecode(response.body) as Map<String, dynamic>;
    final signIn = config['signIn'] as Map<String, dynamic>?;
    final emailPassword = signIn?['emailPassword'] as Map<String, dynamic>?;

    return emailPassword?['enabled'] == true;
  }

  /// Guards against accidentally operating on the master project.
  void _assertNotMasterProject(String tenantProjectId, String operation) {
    if (tenantProjectId.trim().isEmpty) {
      throw StateError(
          '[$operation] Refusing to proceed: tenant project ID is empty/null');
    }
    if (tenantProjectId == _masterProjectId) {
      throw StateError(
          '[$operation] SECURITY VIOLATION: Attempted to operate on master project ($_masterProjectId). '
          'This service must only target tenant projects, never the control-plane project.');
    }
  }

  /// Loads the standard TRAKR tenant database rules from the single source of truth.
  Future<Map<String, dynamic>> loadStandardRules() async {
    final file = File('database.rules.json');
    if (!file.existsSync()) {
      throw StateError('database.rules.json not found in project root');
    }
    final content = file.readAsStringSync();
    final rules = jsonDecode(content) as Map<String, dynamic>;
    return rules['rules'] as Map<String, dynamic>;
  }

  /// Creates a Realtime Database instance for the tenant project.
  ///
  /// POST https://firebase.googleapis.com/v1beta1/projects/{project_id}/locations/{location}/instances
  /// Requires: roles/firebasedatabase.admin on the tenant project (already granted
  /// in the existing service account role list).
  Future<void> createDatabaseInstance({
    required String tenantProjectId,
    String location = 'us-central1',
    String instance = 'default',
    String type = 'DEFAULT_DATABASE',
  }) async {
    _assertNotMasterProject(tenantProjectId, 'createDatabaseInstance');

    final client = await _getAuthClient();
    final url =
        'https://firebase.googleapis.com/v1beta1/projects/$tenantProjectId/locations/$location/instances?instance_id=$instance';

    final body = {
      'instanceId': instance,
      'projectId': tenantProjectId,
      'locationId': location,
      'type': type,
    };

    final response = await client.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode == 409) {
      // Instance already exists — treat as success (idempotent).
      debugPrint('TenantProjectConfigService: RTDB instance already exists for $tenantProjectId');
      return;
    }
    if (response.statusCode >= 400) {
      throw StateError(
          'Failed to create RTDB instance for $tenantProjectId: ${response.statusCode} ${response.body}');
    }
    debugPrint('TenantProjectConfigService: Created RTDB instance for $tenantProjectId');
  }

  /// Enables Email/Password authentication for the tenant project.
  ///
  /// PATCH https://identitytoolkit.googleapis.com/v1/projects/{project_id}/config
  /// Requires: roles/identitytoolkit.editor on the tenant project ( grants
  /// `firebaseauth.configs.update` permission). Do NOT use
  /// roles/firebaseauth.configManager — that role name is not valid in the
  /// current Google IAM schema (verified against 2026 docs).
  Future<void> enableEmailPasswordAuth({
    required String tenantProjectId,
  }) async {
    _assertNotMasterProject(tenantProjectId, 'enableEmailPasswordAuth');

    final client = await _getAuthClient();
    final url =
        'https://identitytoolkit.googleapis.com/v1/projects/$tenantProjectId/config';

    final body = {
      'signIn': {
        'emailPassword': {
          'enabled': true,
        },
      },
    };

    final response = await client.patch(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode >= 400) {
      throw StateError(
          'Failed to enable Email/Password auth for $tenantProjectId: ${response.statusCode} ${response.body}');
    }
    debugPrint('TenantProjectConfigService: Enabled Email/Password auth for $tenantProjectId');
  }

  /// Closes the cached auth client.
  void dispose() {
    _cachedClient?.close();
    _cachedClient = null;
  }
}