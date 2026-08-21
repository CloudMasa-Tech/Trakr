import 'dart:async';

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../control_plane/control_plane_firebase.dart';
import '../../control_plane/models/workspace_provision_request.dart';
import '../../control_plane/services/workspace_provisioning_client_service.dart';
import '../../theme/app_theme_colors.dart';
import 'portal_widgets.dart';

class _LogLine {
  const _LogLine(
      {required this.seq, required this.time, required this.message});

  final int seq;
  final String time;
  final String message;
}

/// Real-time provisioning audit modal.
///
/// Streams the `workspace_provision_logs/{logId}` doc (written by
/// [WorkspaceProvisioningClientService] on the master project) while
/// provisioning runs, renders a terminal-style live log viewer, and shows a
/// success state (dashboard invite link + copy) or a failure state (full
/// error details + Retry).
class WorkspaceProvisioningProgressModal extends StatefulWidget {
  const WorkspaceProvisioningProgressModal({
    super.key,
    required this.request,
    required this.initialLogId,
    this.provisioningClient,
  });

  final WorkspaceProvisionRequest request;
  final String initialLogId;
  final WorkspaceProvisioningClientService? provisioningClient;

  /// Opens the modal and starts provisioning. Resolves with the provision
  /// result when the operator confirms a successful run via "Done", or `null`
  /// when the run failed and was closed.
  static Future<WorkspaceProvisionResult?> show(
    BuildContext context, {
    required WorkspaceProvisionRequest request,
    required String initialLogId,
    WorkspaceProvisioningClientService? provisioningClient,
  }) {
    return showDialog<WorkspaceProvisionResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WorkspaceProvisioningProgressModal(
        request: request,
        initialLogId: initialLogId,
        provisioningClient: provisioningClient,
      ),
    );
  }

  /// Generates a unique, URL-safe id for a provisioning audit-log doc.
  static String generateLogId() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'provision-$millis-$rand';
  }

  @override
  State<WorkspaceProvisioningProgressModal> createState() =>
      _WorkspaceProvisioningProgressModalState();
}

class _WorkspaceProvisioningProgressModalState
    extends State<WorkspaceProvisioningProgressModal> {
  late String _logId;
  late final WorkspaceProvisioningClientService _client;

  // Real-time Firestore listen subscription for workspace_provision_logs/{_logId}.
  // Stored explicitly so it can be cancelled before [disposeTenant()] in the
  // provisioner, preventing the FIRESTORE INTERNAL ASSERTION FAILED (ID: b815)
  // error that occurs when a watch-target callback arrives after the
  // FirebaseApp is deleted.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>?>? _logsSubscription;

  // Cached latest log lines, updated by the listener callback via setState().
  // Used by _buildBody() so the UI never reads from a StreamBuilder.
  List<_LogLine> _lines = [];

  WorkspaceProvisionResult? _result;
  Object? _error;
  bool _running = false;
  String _copiedUrl = '';

  @override
  void initState() {
    super.initState();
    _logId = widget.initialLogId;
    _client = widget.provisioningClient ?? WorkspaceProvisioningClientService();
    _startLogsStream();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runProvision());
  }

  /// Starts an explicit Firestore [StreamSubscription] on
    /// [workspace_provision_logs/{_logId}] that updates [_lines] via
    /// [setState()]. The subscription is stored in [_logsSubscription] so it
    // can be cancelled in [dispose()] and also before [disposeTenant()] in the
    // provisioner, preventing the FIRESTORE INTERNAL ASSERTION FAILED (ID: b815)
    // error that occurs when a watch-target callback arrives after app delete.
  void _startLogsStream() {
    final firestore = ControlPlaneFirebase.instance.firestore;
    _logsSubscription = firestore
        .collection('workspace_provision_logs')
        .doc(_logId)
        .snapshots()
        .listen(
          (DocumentSnapshot<Map<String, dynamic>>? snapshot) async {
            if (!mounted) return;
            final data = snapshot?.data();
            final status = (data?['status'] as String?) ?? '';
            _lines = _parseLogs(data?['logs']);

            if (_result != null || status == 'succeeded') {
              // Provisioning succeeded — stop listening.
              await _logsSubscription!.cancel();
              _logsSubscription = null;
              if (!mounted) return;
              setState(() {});
              return;
            }
            if (_error != null || status == 'failed') {
              // Provisioning failed — stop listening.
              await _logsSubscription!.cancel();
              _logsSubscription = null;
              if (!mounted) return;
              setState(() {});
              return;
            }
            // Still processing — update UI.
            if (mounted) {
              setState(() {});
            }
          },
          // onError: treat SDK errors as transient; keep listening.
          onError: (Object error) {
            debugPrint(
              'WorkspaceProvisioningProgressModal: logs stream error: $error',
            );
          },
          // cancelOnError: false — keep listening even after an error.
        );
  }

  Future<void> _runProvision() async {
    if (_running) return;
    setState(() {
      _running = true;
      _result = null;
      _error = null;
      _copiedUrl = '';
    });

    try {
      final result =
          await _client.provision(widget.request.copyWith(logId: _logId));
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
      });
    } catch (e, st) {
      debugPrint(
        'WorkspaceProvisioningProgressModal: provisioning failed for '
        '"${widget.request.workspaceName}" (logId=$_logId) - $e\n$st',
      );
      if (!mounted) return;
      setState(() {
        _error = e;
        _running = false;
      });
    }
  }

  void _retry() {
    setState(() {
      _logId = WorkspaceProvisioningProgressModal.generateLogId();
    });
    _runProvision();
  }

  void _copyInviteLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    setState(() => _copiedUrl = url);
  }

  String _dashboardUrl(String slug) {
    if (slug.isEmpty) return '';
    final path = '/workspace/$slug/dashboard';
    if (!kIsWeb) return path;
    final origin = Uri.base.origin;
    return origin.isEmpty ? path : '$origin$path';
  }

  String _formatLogTime(dynamic at) {
    if (at is Timestamp) {
      final dt = at.toDate();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      final s = dt.second.toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '--:--:--';
  }

  List<_LogLine> _parseLogs(dynamic rawLogs) {
    final raw = rawLogs as List? ?? const [];
    final lines = <_LogLine>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final message = entry['message'] as String? ?? '';
      if (message.isEmpty) continue;
      final seq = entry['seq'];
      lines.add(_LogLine(
        seq: seq is num ? seq.toInt() : 0,
        time: _formatLogTime(entry['at']),
        message: message,
      ));
    }
    lines.sort((a, b) => a.seq.compareTo(b.seq));
    return lines;
  }

  /// Cancels the explicit [StreamSubscription] observing
  /// [workspace_provision_logs/{_logId}] so the SDK's TargetState no longer
  // expects watch-target callbacks after the FirebaseApp is deleted,
  // preventing the FIRESTORE INTERNAL ASSERTION FAILED (ID: b815) error that
  // occurred when a watch-target response arrived after app delete.
  // [StreamSubscription.cancel()] is safe to call multiple times.
  @override
  void dispose() {
    // (a) Cancel the explicit StreamSubscription so the SDK's TargetState
    //     no longer expects watch-target callbacks after the FirebaseApp is
    //     deleted, preventing the FIRESTORE INTERNAL ASSERTION FAILED (ID: b815)
    //     error that occurred when a watch-target response arrived after app
    //     delete. StreamSubscription.cancel() is safe to call multiple times.
    _logsSubscription?.cancel();
    _logsSubscription = null;
    super.dispose();
  }

  /// Exposes the underlying [StreamSubscription] cancel action so that external
  /// code (e.g. the provisioner's [_teardownTenant] callback) can cancel the
  // Firestore listen target before the tenant FirebaseApp is deleted.
  void cancelLogsSubscription() {
    _logsSubscription?.cancel();
    _logsSubscription = null;
  }

  @override
  Widget build(BuildContext context) {
    final succeeded = _result != null;
    final failed = _error != null;

    return PopScope(
      canPop: !_running && (succeeded || failed),
      child: Dialog(
        backgroundColor: AppThemeColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: kCoBorder),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 660),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(succeeded: succeeded, failed: failed),
                const SizedBox(height: 16),
                Flexible(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({required bool succeeded, required bool failed}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kCoAccent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child:
              const Icon(Icons.workspaces_rounded, color: kCoAccent, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Provisioning workspace',
                style: TextStyle(
                  color: kCoLabel,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.request.workspaceName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kCoSubtle, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        CoStatusBadge(
          label: succeeded
              ? 'Succeeded'
              : failed
                  ? 'Failed'
                  : 'Processing',
          color: succeeded
              ? kCoGreen
              : failed
                  ? kCoRed
                  : kCoAmber,
        ),
      ],
    );
  }

  Widget _buildBody() {
    // If we have a cached result or error, render the settled view immediately.
    if (_result != null) {
      final slug = _result?.workspaceSlug ?? '';
      return _buildSuccess(slug, []);
    }
    if (_error != null) {
      return _buildError(_error!.toString(), []);
    }

    // Otherwise, render using the explicit listen subscription state.
    // If the subscription is active and has delivered at least one event,
    // show the latest log lines; otherwise show the processing indicator.
    if (_logsSubscription != null && _logsSubscription!.isPaused == false) {
      // Subscription is active — show lines if available, otherwise indicator.
      if (_lines.isEmpty) {
        return _buildProcessing([]);
      }
      // Show the latest log lines.
      return _buildProcessing(_lines);
    }

    // No subscription active yet — show the processing indicator.
    return _buildProcessing([]);
  }

  Widget _buildProcessing(List<_LogLine> lines, {bool streamError = false}) {
    final current = lines.isEmpty
        ? 'Waiting for provisioning to start…'
        : lines.last.message;
    return SizedBox(
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: kCoAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Provisioning in progress…',
                      style: TextStyle(
                        color: kCoLabel,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      current,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: kCoSubtle, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const _LogLabel(label: 'LIVE AUDIT LOG'),
          const SizedBox(height: 6),
          Expanded(child: _LogTerminal(lines: lines)),
          const SizedBox(height: 10),
          Text(
            streamError
                ? 'Live log unavailable (check Firestore rules are deployed). '
                    'Provisioning continues in the background.'
                : 'This usually takes a few minutes. Keep this window open.',
            style:
                const TextStyle(color: kCoSubtle, fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(String slug, List<_LogLine> lines) {
    final url = _dashboardUrl(slug);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: kCoGreen, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Workspace provisioned',
                      style: TextStyle(
                        color: kCoLabel,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _result?.emailSent == true
                          ? "Admin invite email sent to ${widget.request.companyAdminEmail}."
                          : "Workspace is ready, but the admin invite email was not sent. Use the resend action for ${widget.request.companyAdminEmail}.",
                      style: const TextStyle(
                          color: kCoSubtle, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (url.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
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
                      const Icon(Icons.link_rounded, color: kCoAccent, size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Workspace dashboard link',
                          style: TextStyle(
                            color: kCoLabel,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _copyInviteLink(url),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            _copiedUrl == url
                                ? Icons.check_rounded
                                : Icons.copy_rounded,
                            color: _copiedUrl == url ? kCoGreen : kCoSubtle,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    url,
                    style: const TextStyle(
                      color: kCoAccent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (lines.isNotEmpty) ...[
            const _LogLabel(label: 'AUDIT LOG'),
            const SizedBox(height: 6),
            SizedBox(height: 130, child: _LogTerminal(lines: lines)),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(_result),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kCoLabel,
                    side: const BorderSide(color: kCoBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Done'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: url.isEmpty ? null : () => _copyInviteLink(url),
                  style: FilledButton.styleFrom(
                    backgroundColor: kCoAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    _copiedUrl == url ? Icons.check_rounded : Icons.copy_rounded,
                    size: 18,
                  ),
                  label: Text(_copiedUrl == url
                      ? 'Invite link copied'
                      : 'Copy invite link'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildError(String errorMessage, List<_LogLine> lines) {
    final detail = errorMessage.trim();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.error_rounded, color: kCoRed, size: 46),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Provisioning failed',
                      style: TextStyle(
                        color: kCoLabel,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'The workspace could not be created. Review the audit log '
                      'below, then retry.',
                      style: TextStyle(
                          color: kCoSubtle, fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (detail.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppThemeColors.darkCanvas,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kCoRed.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.report_gmailerrorred_rounded,
                      color: kCoRed, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      detail.length > 200
                          ? '${detail.substring(0, 200)}…'
                          : detail,
                      style: const TextStyle(
                          color: kCoErrorLight, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                'View complete error details',
                style: TextStyle(
                    color: kCoSubtle,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700),
              ),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppThemeColors.darkCanvas,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kCoBorder),
                  ),
                  child: SelectableText(
                    detail,
                    style: const TextStyle(
                      color: kCoErrorLight,
                      fontSize: 12,
                      height: 1.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (lines.isNotEmpty) ...[
            const _LogLabel(label: 'AUDIT LOG'),
            const SizedBox(height: 6),
            SizedBox(height: 120, child: _LogTerminal(lines: lines)),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kCoLabel,
                    side: const BorderSide(color: kCoBorder),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _running ? null : _retry,
                  style: FilledButton.styleFrom(
                    backgroundColor: kCoAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _running
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: kCoWhite),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_running ? 'Retrying…' : 'Retry'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LogLabel extends StatelessWidget {
  const _LogLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: kCoSubtle,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Terminal-style read-only log viewer with auto-scroll to the newest line.
class _LogTerminal extends StatefulWidget {
  const _LogTerminal({required this.lines});

  final List<_LogLine> lines;

  @override
  State<_LogTerminal> createState() => _LogTerminalState();
}

class _LogTerminalState extends State<_LogTerminal> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(_LogTerminal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lines.length != widget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E11),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kCoBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: widget.lines.isEmpty
          ? const Center(
              child: Text(
                'Waiting for the first log entry…',
                style: TextStyle(color: kCoSubtle, fontSize: 12),
              ),
            )
          : Scrollbar(
              controller: _controller,
              thumbVisibility: true,
              child: ListView.builder(
                controller: _controller,
                itemCount: widget.lines.length,
                itemBuilder: (context, index) {
                  final line = widget.lines[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '[${line.time}] ',
                            style: const TextStyle(
                              color: kCoGreen,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: line.message,
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
