import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../control_plane/models/workspace_firebase_config.dart';
import '../../control_plane/services/firebase_config_parser.dart';
import '../../control_plane/services/firebase_config_validator.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

/// Production-grade Firebase configuration control used by the Client
/// Onboarding (Create Workspace) form.
///
/// The Super Admin creates the company's OWN Firebase project manually in the
/// Firebase Console and supplies its CLIENT-side configuration here. Three
/// configuration methods are supported, selectable via a tab strip:
///
/// 1. **NPM** — `npm install firebase` package wiring (package + SDK version)
///    plus the standard config object.
/// 2. **CDN** — official gstatic Firebase CDN `<script>` tags (script URL or
///    SDK version) plus the standard config object.
/// 3. **Config** — the standard Firebase web-app configuration object fields
///    entered directly (`apiKey`, `authDomain`, `projectId`, `storageBucket`,
///    `messagingSenderId`, `appId`, `measurementId`), or pasted/uploaded as
///    JSON (`google-services.json` / iOS plist JSON are auto-detected too).
///
/// Every accepted configuration is validated in two stages before it is handed
/// to the parent:
///
/// 1. Structural validation (required fields, field shapes) via
///    [FirebaseConfigValidator.validateStructure].
/// 2. A live **Test Connection** via
///    [FirebaseConfigValidator.testConnection] — a throwaway Firebase app is
///    initialized from the exact options the tenant will use and a lightweight
///    auth round-trip proves the config works against the real project. The
///    Master TRAKR project is never touched.
///
/// On success the control shows the detected project id, the method badge, the
/// generated SDK wiring preview and a "Confirm mapping" checkbox the operator
/// must tick before the workspace can be provisioned.
class FirebaseConfigUploadField extends StatefulWidget {
  const FirebaseConfigUploadField({
    super.key,
    required this.config,
    required this.confirmed,
    required this.onParsed,
    required this.onRemove,
    required this.onConfirmedChanged,
    this.errorText,
    this.enabled = true,
    this.connectionTester = FirebaseConfigValidator.testConnection,
  });

  /// Currently parsed & validated client config, or `null` when none has been
  /// accepted yet. Owned by the parent.
  final WorkspaceFirebaseConfig? config;

  /// Whether the operator has confirmed the Firebase project mapping.
  final bool confirmed;

  /// Called with the accepted client config after it validates and the project
  /// mapping checks pass.
  final ValueChanged<WorkspaceFirebaseConfig> onParsed;

  /// Called when the operator removes the uploaded configuration.
  final VoidCallback onRemove;

  /// Called whenever the "Confirm mapping" checkbox toggles.
  final ValueChanged<bool> onConfirmedChanged;

  /// Inline validation message shown under the field (e.g. submit errors).
  final String? errorText;

  /// Disables editing (e.g. while the form is submitting).
  final bool enabled;

  /// The live connection-test runner.
  ///
  /// Production always uses [FirebaseConfigValidator.testConnection] (which
  /// initializes a throwaway app and does a real auth round-trip). Exposed as
  /// a constructor seam so widget tests can inject a deterministic fake — the
  /// connection round-trip is the only network-dependent step in the accept
  /// path.
  @visibleForTesting
  final Future<FirebaseConfigConnectionResult> Function(
      WorkspaceFirebaseConfig) connectionTester;

  @override
  State<FirebaseConfigUploadField> createState() =>
      _FirebaseConfigUploadFieldState();
}

class _FirebaseConfigUploadFieldState extends State<FirebaseConfigUploadField> {
  FirebaseConfigMethod _method = FirebaseConfigMethod.config;

  final _apiKeyCtrl = TextEditingController();
  final _authDomainCtrl = TextEditingController();
  final _projectIdCtrl = TextEditingController();
  final _storageBucketCtrl = TextEditingController();
  final _messagingSenderIdCtrl = TextEditingController();
  final _appIdCtrl = TextEditingController();
  final _measurementIdCtrl = TextEditingController();

  final _npmPackageCtrl = TextEditingController();
  final _sdkVersionCtrl = TextEditingController();
  final _cdnUrlCtrl = TextEditingController();

  final _pasteCtrl = TextEditingController();

  bool _picking = false;
  bool _parsing = false;
  bool _testing = false;
  bool _pasteMode = false;
  bool _obscureSecrets = true;
  bool _configUploaded = false;

  String? _localError;
  String? _testError;
  String? _testSuccess;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _apiKeyCtrl,
      _authDomainCtrl,
      _projectIdCtrl,
      _storageBucketCtrl,
      _messagingSenderIdCtrl,
      _appIdCtrl,
      _measurementIdCtrl,
      _npmPackageCtrl,
      _sdkVersionCtrl,
      _cdnUrlCtrl,
    ]) {
      controller.addListener(_onFieldChanged);
    }
  }

  @override
  void didUpdateWidget(covariant FirebaseConfigUploadField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != null && widget.config == null) {
      // The configuration was removed — reset the transient validation state so
      // the operator starts from a clean entry form.
      _testError = null;
      _testSuccess = null;
      _fieldErrors = const {};
      _localError = null;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _apiKeyCtrl,
      _authDomainCtrl,
      _projectIdCtrl,
      _storageBucketCtrl,
      _messagingSenderIdCtrl,
      _appIdCtrl,
      _measurementIdCtrl,
      _npmPackageCtrl,
      _sdkVersionCtrl,
      _cdnUrlCtrl,
      _pasteCtrl,
    ]) {
      controller.removeListener(_onFieldChanged);
      controller.dispose();
    }
    super.dispose();
  }

  void _onFieldChanged() {
    // Rebuild on every keystroke so the live SDK wiring preview (npm install /
    // CDN script) tracks the fields in real time, and any stale validation
    // errors/success messages are cleared as the operator edits.
    setState(() {
      _fieldErrors = const {};
      _testError = null;
      _testSuccess = null;
      _localError = null;
    });
  }

  void _setMethod(FirebaseConfigMethod method) {
    if (method == _method) return;
    setState(() {
      _method = method;
      _pasteMode = false;
      _fieldErrors = const {};
      _testError = null;
      _testSuccess = null;
      _localError = null;
    });
  }

  bool get _busy => !widget.enabled || _picking || _parsing || _testing;

  Future<void> _browse() async {
    if (_busy) return;
    setState(() {
      _picking = true;
      _localError = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'txt'],
        withData: true,
      );
      final file = result?.files.firstOrNull;
      if (file == null) return;

      final String text;
      final bytes = file.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        text = utf8.decode(bytes, allowMalformed: true);
      } else if (file.path != null && file.path!.isNotEmpty) {
        text = await File(file.path!).readAsString();
      } else {
        setState(() => _localError = 'Could not read the configuration file.');
        return;
      }
      await _handleRawText(text, fileName: file.name);
    } catch (_) {
      if (mounted) {
        setState(() => _localError = 'Could not read the configuration file.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _handleRawText(String text, {String? fileName}) async {
    if (!mounted) return;
    setState(() {
      _parsing = true;
      _localError = null;
    });

    final result = FirebaseConfigParser.parse(text);
    if (!result.isValid || result.config == null) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _localError = result.errorMessage;
      });
      return;
    }

    final config = result.config!;
    if (!mounted) return;
    setState(() {
      _parsing = false;
      _pasteMode = false;
      _method = FirebaseConfigMethod.config;
      _fieldErrors = const {};
      _testError = null;
      _testSuccess = null;
      _localError = null;
      _configUploaded = true;
    });
    _fillControllers(config);

    // Route the pasted/uploaded config through the same live connection test
    // as the manually-entered fields, so every accepted config is verified.
    final validated = await _runValidation();

    if (fileName != null && validated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kCoSuccess,
          content: Text('Configuration uploaded successfully: '
              '${config.projectId}'),
        ),
      );
    }
  }

  void _fillControllers(WorkspaceFirebaseConfig config) {
    _apiKeyCtrl.text = config.apiKey;
    _authDomainCtrl.text = config.authDomain;
    _projectIdCtrl.text = config.projectId;
    _storageBucketCtrl.text = config.storageBucket;
    _messagingSenderIdCtrl.text = config.messagingSenderId;
    _appIdCtrl.text = config.appId;
    _measurementIdCtrl.text = config.measurementId ?? '';
    _npmPackageCtrl.text = config.npmPackage;
    _sdkVersionCtrl.text = config.sdkVersion;
    _cdnUrlCtrl.text = config.cdnUrl;
  }

  Future<bool> _runValidation() async {
    final structureErrors = FirebaseConfigValidator.validateStructure(
      method: _method,
      apiKey: _apiKeyCtrl.text,
      appId: _appIdCtrl.text,
      projectId: _projectIdCtrl.text,
      messagingSenderId: _messagingSenderIdCtrl.text,
      authDomain: _authDomainCtrl.text,
      storageBucket: _storageBucketCtrl.text,
      measurementId: _measurementIdCtrl.text,
      npmPackage: _npmPackageCtrl.text,
      sdkVersion: _sdkVersionCtrl.text,
      cdnUrl: _cdnUrlCtrl.text,
    );

    if (structureErrors.isNotEmpty) {
      if (!mounted) return false;
      setState(() {
        _fieldErrors = {
          for (final e in structureErrors) e.field: e.message,
        };
        _testError = 'Fix the highlighted fields, then validate again.';
        _testSuccess = null;
        _localError = null;
      });
      return false;
    }

    final config = WorkspaceFirebaseConfig(
      apiKey: _apiKeyCtrl.text.trim(),
      appId: _appIdCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      messagingSenderId: _messagingSenderIdCtrl.text.trim(),
      storageBucket: _storageBucketCtrl.text.trim(),
      authDomain: _authDomainCtrl.text.trim(),
      measurementId:
          _measurementIdCtrl.text.trim().isEmpty ? null : _measurementIdCtrl.text.trim(),
      configMethod: _method,
      npmPackage: _method == FirebaseConfigMethod.npm
          ? _npmPackageCtrl.text.trim()
          : '',
      sdkVersion:
          (_method == FirebaseConfigMethod.npm ||
                  _method == FirebaseConfigMethod.cdn)
              ? _sdkVersionCtrl.text.trim()
              : '',
      cdnUrl: _method == FirebaseConfigMethod.cdn ? _cdnUrlCtrl.text.trim() : '',
    );

    if (!mounted) return false;
    setState(() {
      _testing = true;
      _testError = null;
      _testSuccess = null;
      _localError = null;
    });

    final connection = await widget.connectionTester(config);
    if (!mounted) return false;

    if (!connection.success) {
      if (!mounted) return false;
      setState(() {
        _testing = false;
        _testError = connection.message;
      });
      return false;
    }

    // Every workspace must run on its OWN dedicated Firebase project. Mapping a
    // workspace to the TRAKR platform (Master) project would mix tenant data
    // with the control plane, so that configuration is rejected outright.
    if (FirebaseConfigValidator.isPlatformProject(config.projectId)) {
      if (!mounted) return false;
      setState(() {
        _testing = false;
        _testError = 'This is the TRAKR Master platform project. Workspaces '
            'must use their own dedicated Firebase project — create one in the '
            'Firebase Console and provide ITS client-side configuration.';
      });
      return false;
    }

    if (!mounted) return false;
    setState(() {
      _testing = false;
      _testSuccess = connection.message;
    });
    widget.onParsed(config);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final hasConfig = widget.config != null;
    final effectiveError = widget.errorText ?? _localError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLabel(),
        const SizedBox(height: 8),
        if (_busy)
          _buildBusy()
        else if (hasConfig)
          _buildParsed()
        else if (_pasteMode)
          _buildPaste()
        else
          _buildEntry(error: effectiveError),
        if (!hasConfig &&
            effectiveError != null &&
            !_pasteMode &&
            !_busy) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: kCoDanger, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  effectiveError,
                  style: const TextStyle(color: kCoDanger, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLabel() {
    return const Row(
      children: [
        Text(
          'Firebase configuration',
          style: TextStyle(
              color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13),
        ),
        SizedBox(width: 4),
        Text('(required)', style: TextStyle(color: kCoDanger, fontSize: 12)),
      ],
    );
  }

  // ── Entry form (method tabs + fields + validate) ────────────────────────
  Widget _buildEntry({String? error}) {
    final borderColor = error != null ? kCoDanger : kCoBorder;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: error != null ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildMethodSelector(),
          const SizedBox(height: 12),
          _buildMethodHint(),
          const SizedBox(height: 18),
          if (_method == FirebaseConfigMethod.npm) ...[
            _buildSdkFields(),
            const SizedBox(height: 16),
          ],
          if (_method == FirebaseConfigMethod.cdn) ...[
            _buildSdkFields(),
            const SizedBox(height: 16),
          ],
          _buildConfigFields(),
          if (_testError != null || _testSuccess != null) ...[
            const SizedBox(height: 14),
            _buildTestResult(),
          ],
          const SizedBox(height: 18),
          _buildActions(),
          const SizedBox(height: 14),
          _buildImporterLink(),
        ],
      ),
    );
  }

  Widget _buildMethodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Configuration method',
          style: TextStyle(
            color: kCoLabel,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<FirebaseConfigMethod>(
          segments: const [
            ButtonSegment(
              value: FirebaseConfigMethod.npm,
              label: Text('NPM'),
              icon: Icon(Icons.widgets_rounded, size: 17),
            ),
            ButtonSegment(
              value: FirebaseConfigMethod.cdn,
              label: Text('CDN'),
              icon: Icon(Icons.public_rounded, size: 17),
            ),
            ButtonSegment(
              value: FirebaseConfigMethod.config,
              label: Text('Config'),
              icon: Icon(Icons.data_object_rounded, size: 17),
            ),
          ],
          selected: {_method},
          onSelectionChanged: (selection) => _setMethod(selection.first),
          showSelectedIcon: false,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? kCoAccent
                  : const Color(0xFF0B0E11),
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? kCoWhite
                  : kCoSubtle,
            ),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.selected)
                    ? kCoAccent
                    : kCoBorder,
              ),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            textStyle: const WidgetStatePropertyAll(
              TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMethodHint() {
    final (title, body) = switch (_method) {
      FirebaseConfigMethod.npm => (
          'NPM package',
          'Install the Firebase JS SDK with npm and initialize it with the '
              'configuration object below. The package and version fields '
              'describe the SDK wiring; the configuration object is identical '
              'for every method.',
        ),
      FirebaseConfigMethod.cdn => (
          'CDN scripts',
          'Load Firebase through the official gstatic CDN <script> tags and '
              'call firebase.initializeApp(config). The script URL/version '
              'fields describe the SDK wiring; the configuration object is '
              'identical for every method.',
        ),
      FirebaseConfigMethod.config => (
          'Configuration object',
          'Enter the standard Firebase web-app configuration object fields '
              '(Firebase Console → Project settings → Your apps → SDK setup '
              'and configuration). You can also paste the JSON or upload a '
              'google-services.json / iOS plist JSON instead.',
        ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: kCoAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.info_outline_rounded,
              color: kCoAccent, size: 15),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: kCoLabel,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style:
                    const TextStyle(color: kCoSubtle, fontSize: 11.5, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSdkFields() {
    final isNpm = _method == FirebaseConfigMethod.npm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isNpm ? 'SDK package & version' : 'CDN script & version',
          style: const TextStyle(
            color: kCoLabel,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        if (isNpm)
          _buildFieldGrid([
            _field(
              label: 'NPM package',
              errorKey: 'npmPackage',
              hint: 'firebase',
              controller: _npmPackageCtrl,
              optional: true,
              monospace: true,
            ),
            _field(
              label: 'SDK version',
              errorKey: 'sdkVersion',
              hint: '11.6.0',
              controller: _sdkVersionCtrl,
              optional: true,
              monospace: true,
            ),
          ])
        else
          _buildFieldGrid([
            _field(
              label: 'SDK version',
              errorKey: 'sdkVersion',
              hint: '11.6.0',
              controller: _sdkVersionCtrl,
              optional: true,
              monospace: true,
            ),
            _field(
              label: 'CDN script URL',
              errorKey: 'cdnUrl',
              hint: 'https://www.gstatic.com/firebasejs/11.6.0/'
                  'firebase-app-compat.js',
              controller: _cdnUrlCtrl,
              optional: true,
              monospace: true,
            ),
          ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0E11),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kCoBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.code_rounded, color: kCoAccent, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  _sdkPreview,
                  style: const TextStyle(
                    color: kCoGreen,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfigFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Firebase configuration object',
          style: TextStyle(
            color: kCoLabel,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 8),
        // When Config method is selected, show paste textarea before first paste,
        // then show the field grid (which supports manual editing after paste).
        if (_method == FirebaseConfigMethod.config &&
            !_pasteMode &&
            !_configUploaded) ...[
          _buildConfigPasteTextarea(),
          const SizedBox(height: 12),
        ],
        // Field grid for NPM/CDN methods or for displaying/editing config after
        // it has been pasted/parsed (the grid still supports manual editing).
        _buildFieldGrid(_buildConfigFieldsGridWidgets()),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Build the list of 7 config field widgets for the field grid.
  List<Widget> _buildConfigFieldsGridWidgets() => [
    _field(
      label: 'API key',
      errorKey: 'apiKey',
      hint: 'AIzaSy…',
      controller: _apiKeyCtrl,
      monospace: true,
      obscure: () => _obscureSecrets,
      onToggleObscure: () =>
          setState(() => _obscureSecrets = !_obscureSecrets),
    ),
    _field(
      label: 'App ID',
      errorKey: 'appId',
      hint: '1:1234567890:web:abcdef',
      controller: _appIdCtrl,
      monospace: true,
      obscure: () => _obscureSecrets,
      onToggleObscure: () =>
          setState(() => _obscureSecrets = !_obscureSecrets),
    ),
    _field(
      label: 'Project ID',
      errorKey: 'projectId',
      hint: 'my-company-firebase',
      controller: _projectIdCtrl,
      monospace: true,
    ),
    _field(
      label: 'Auth domain',
      errorKey: 'authDomain',
      hint: 'my-company.firebaseapp.com',
      controller: _authDomainCtrl,
      monospace: true,
    ),
    _field(
      label: 'Storage bucket',
      errorKey: 'storageBucket',
      hint: 'my-company.appspot.com',
      controller: _storageBucketCtrl,
      monospace: true,
    ),
    _field(
      label: 'Messaging sender ID',
      errorKey: 'messagingSenderId',
      hint: '123456789012',
      controller: _messagingSenderIdCtrl,
      monospace: true,
    ),
    _field(
      label: 'Measurement ID',
      errorKey: 'measurementId',
      hint: 'G-XXXXXXXXXX',
      controller: _measurementIdCtrl,
      optional: true,
      monospace: true,
    ),
  ];

  /// Large textarea for pasting the entire Firebase config object/JSON.
  ///
  /// User pastes text like:
  ///   { "apiKey": "…", "authDomain": "…", "projectId": "…",
   ///    "storageBucket": "…", "messagingSenderId": "…", "appId": "…",
    ///    "measurementId": "…" }
  Widget _buildConfigPasteTextarea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCoAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.content_paste_rounded,
                  color: kCoAccent, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Paste Firebase Config',
                  style: TextStyle(
                    color: kCoLabel,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy || _parsing
                    ? null
                    : () => setState(() => _pasteMode = true),
                icon: const Icon(Icons.close_rounded,
                    color: kCoSubtle, size: 18),
                tooltip: 'Back to manual entry',
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pasteCtrl,
            enabled: !_busy && !_parsing,
            maxLines: 8,
            minLines: 5,
            style: const TextStyle(
              color: kCoLabel,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            cursorColor: kCoAccent,
            decoration: InputDecoration(
              hintText:
                  '{ "apiKey": "…", "appId": "…", "projectId": "…", '
                  '"messagingSenderId": "…", … }',
              hintStyle:
                  const TextStyle(color: kCoSubtle, fontSize: 11.5),
              filled: true,
              fillColor: const Color(0xFF0B0E11),
              isDense: true,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kCoBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kCoBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kCoAccent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: (_busy || _parsing)
                    ? null
                    : () => _handleRawText(_pasteCtrl.text),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kCoAccent,
                  side: BorderSide(color: kCoAccent.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.manage_search_rounded, size: 16),
                label: const Text(
                  'Validate & detect project id',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _pasteMode = true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kCoSubtle,
                  side: const BorderSide(color: kCoBorder),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 11),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.upload_file_rounded, size: 16),
                label: const Text('Upload file',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Accepted: web-app config, google-services.json or '
            'GoogleService-Info.plist (as JSON). A live connection test runs '
            'after parsing.  serviceAccountKey.json is rejected.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kCoSubtle, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldGrid(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 560;
        final width = twoCol ? (c.maxWidth - 14) / 2 : c.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final field in fields) SizedBox(width: width, child: field),
          ],
        );
      },
    );
  }

  Widget _field({
    required String label,
    required String errorKey,
    required String hint,
    required TextEditingController controller,
    bool optional = false,
    bool monospace = false,
    bool Function()? obscure,
    VoidCallback? onToggleObscure,
  }) {
    final errorText = _fieldErrors[errorKey];
    final isObscure = obscure?.call() ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: kCoLabel,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            if (!optional) ...[
              const SizedBox(width: 4),
              const Text('*', style: TextStyle(color: kCoDanger)),
            ] else ...[
              const SizedBox(width: 4),
              const Text('(optional)',
                  style: TextStyle(color: kCoSubtle, fontSize: 11)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: !_busy,
          obscureText: isObscure,
          style: TextStyle(
            color: kCoLabel,
            fontSize: 12.5,
            fontFamily: monospace ? 'monospace' : null,
          ),
          cursorColor: kCoAccent,
          decoration: _inputDecoration(
            hint,
            errorText: errorText,
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    onPressed: _busy ? null : onToggleObscure,
                    icon: Icon(
                      isObscure
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: kCoSubtle,
                      size: 17,
                    ),
                    tooltip: isObscure ? 'Show value' : 'Hide value',
                  ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Text(
              errorText,
              style: const TextStyle(color: kCoDanger, fontSize: 11.5),
            ),
          ),
      ],
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: FilledButton.icon(
            onPressed: _busy ? null : _runValidation,
            style: FilledButton.styleFrom(
              backgroundColor: kCoAccent,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kCoWhite),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: Text(
              _testing ? 'Testing connection…' : 'Validate & Test Connection',
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => setState(() => _pasteMode = true),
            style: OutlinedButton.styleFrom(
              foregroundColor: kCoSubtle,
              side: const BorderSide(color: kCoBorder),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.content_paste_rounded, size: 16),
            label: const Text('Paste / upload JSON',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildImporterLink() {
    return const Align(
      alignment: Alignment.center,
      child: Text(
        'serviceAccountKey.json and private keys are always rejected. '
        'Only client-side configuration is accepted.',
        textAlign: TextAlign.center,
        style: TextStyle(color: kCoSubtle, fontSize: 11, height: 1.4),
      ),
    );
  }

  Widget _buildTestResult() {
    final isError = _testError != null;
    final color = isError ? kCoDanger : kCoGreen;
    final bg = isError
        ? kCoDanger.withValues(alpha: 0.09)
        : kCoSuccess.withValues(alpha: 0.08);
    final icon = isError ? Icons.error_rounded : Icons.check_circle_rounded;
    final message = isError ? _testError! : _testSuccess!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? kCoErrorLight : kCoGreen,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Paste / upload JSON view ────────────────────────────────────────────
  Widget _buildPaste() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCoAccent.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.content_paste_rounded,
                  color: kCoAccent, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Paste or upload the Firebase client configuration',
                  style: TextStyle(
                    color: kCoLabel,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : () => setState(() => _pasteMode = false),
                icon: const Icon(Icons.close_rounded,
                    color: kCoSubtle, size: 18),
                tooltip: 'Back to manual entry',
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pasteCtrl,
            enabled: !_busy && !_parsing,
            maxLines: 8,
            minLines: 5,
            style: const TextStyle(
              color: kCoLabel,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
            cursorColor: kCoAccent,
            decoration: InputDecoration(
              hintText: '{ "apiKey": "…", "appId": "…", '
                  '"projectId": "…", "messagingSenderId": "…", … }',
              hintStyle:
                  const TextStyle(color: kCoSubtle, fontSize: 11.5),
              filled: true,
              fillColor: const Color(0xFF0B0E11),
              isDense: true,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kCoBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kCoBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: kCoAccent, width: 1.5),
              ),
            ),
          ),
          if (_localError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: kCoDanger, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _localError!,
                    style:
                        const TextStyle(color: kCoDanger, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _browse,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kCoAccent,
                    side: BorderSide(color: kCoAccent.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.upload_file_rounded, size: 16),
                  label: const Text('Upload file',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                FilledButton.icon(
                  onPressed: (_busy || _parsing)
                      ? null
                      : () => _handleRawText(_pasteCtrl.text),
                  style: FilledButton.styleFrom(
                    backgroundColor: kCoAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: _parsing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kCoWhite),
                        )
                      : const Icon(Icons.manage_search_rounded, size: 17),
                  label: Text(
                    _parsing ? 'Validating…' : 'Validate & detect project id',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Accepted: web-app config, google-services.json or '
            'GoogleService-Info.plist (as JSON). A live connection test runs '
            'after parsing.  serviceAccountKey.json is rejected.',
            textAlign: TextAlign.center,
            style: TextStyle(color: kCoSubtle, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ── Accepted / parsed view ──────────────────────────────────────────────
  Widget _buildParsed() {
    final config = widget.config!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCoSuccess.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCoSuccess.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: kCoGreen, size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Configuration validated & connection verified',
                  style: TextStyle(
                    color: kCoGreen,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? null : widget.onRemove,
                icon: const Icon(Icons.delete_outline_rounded,
                    color: kCoSubtle, size: 19),
                tooltip: 'Remove configuration',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppThemeColors.darkCanvas,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kCoBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.cloud_outlined,
                        color: kCoAccent, size: 17),
                    const SizedBox(width: 8),
                    const Text(
                      'Detected Firebase project',
                      style: TextStyle(color: kCoSubtle, fontSize: 12),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kCoAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        config.configMethod.label,
                        style: const TextStyle(
                          color: kCoAccent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  config.projectId,
                  style: const TextStyle(
                    color: kCoLabel,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                if (_sdkPreviewFor(config).isNotEmpty) ...[
                  Text(
                    _sdkPreviewFor(config),
                    style: const TextStyle(
                      color: kCoGreen,
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                const Text(
                  'This workspace will be mapped to its OWN dedicated Firebase '
                  'project. The TRAKR platform project stays untouched.',
                  style: TextStyle(
                      color: kCoSubtle, fontSize: 11.5, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              value: widget.confirmed,
              onChanged: _busy
                  ? null
                  : (v) => widget.onConfirmedChanged(v ?? false),
              activeColor: kCoAccent,
              checkColor: kCoWhite,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Confirm mapping to Firebase project',
                style: TextStyle(
                  color: kCoLabel,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                'I created this Firebase project in the Firebase Console and '
                'verify the project id "${config.projectId}" above.',
                style: const TextStyle(color: kCoSubtle, fontSize: 11.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusy() {
    final testing = _testing;
    final parsing = _parsing;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCoBorder),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: kCoAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              testing
                  ? 'Testing the connection to the Firebase project…'
                  : parsing
                      ? 'Validating Firebase configuration…'
                      : 'Validating Firebase configuration…',
              style: const TextStyle(
                  color: kCoLabel,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5),
            ),
          ),
          if (testing)
            const Text(
              'Live round-trip',
              style: TextStyle(color: kCoSubtle, fontSize: 12),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    String hint, {
    String? errorText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kCoSubtle, fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF0B0E11),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      errorText: errorText,
      errorMaxLines: 2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoDanger, width: 1.3),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kCoDanger, width: 1.5),
      ),
      suffixIcon: suffixIcon,
    );
  }

  String get _sdkPreview {
    switch (_method) {
      case FirebaseConfigMethod.npm:
        final package =
            _npmPackageCtrl.text.trim().isEmpty ? 'firebase' : _npmPackageCtrl.text.trim();
        final version = _sdkVersionCtrl.text.trim();
        return 'npm install $package${version.isEmpty ? '' : '@$version'}';
      case FirebaseConfigMethod.cdn:
        final url = _cdnUrlCtrl.text.trim();
        if (url.isNotEmpty) return '<script src="$url"></script>';
        final version = _sdkVersionCtrl.text.trim();
        return '<script src="https://www.gstatic.com/firebasejs/'
            '${version.isEmpty ? '10.14.1' : version}/firebase-app-compat.js"></script>';
      case FirebaseConfigMethod.config:
        return '';
    }
  }

  String _sdkPreviewFor(WorkspaceFirebaseConfig config) {
    switch (config.configMethod) {
      case FirebaseConfigMethod.npm:
        return config.npmInstallCommand;
      case FirebaseConfigMethod.cdn:
        return config.cdnScriptTag;
      case FirebaseConfigMethod.config:
        return '';
    }
  }
}
