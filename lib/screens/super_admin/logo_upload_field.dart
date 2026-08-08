import 'package:flutter/material.dart';

import '../../theme/app_theme_colors.dart';
import '../../utils/logo_file_picker.dart';
import 'portal_widgets.dart';

/// Production-grade logo upload control used by the Client Onboarding form.
///
/// Supports click-to-browse (via the platform file picker) and drag & drop on
/// web, validates the file type (PNG/JPG/JPEG/SVG) and the 700 KB size limit,
/// shows an in-place preview before submit, and renders progress while the
/// parent is encoding and persisting the logo to Firestore (as a data URL).
///
/// The widget is fully controlled: the parent owns the selected file, the
/// upload state, and the progress value.
class LogoUploadField extends StatefulWidget {
  const LogoUploadField({
    super.key,
    required this.logo,
    required this.onPicked,
    required this.onRemove,
    this.uploading = false,
    this.progress = 0,
    this.enabled = true,
    this.errorText,
  });

  /// Currently selected logo (null when none chosen). Uploaded bytes are owned
  /// by the parent so it can persist them to Firestore on submit.
  final PickedLogoFile? logo;

  /// Called when the user picks a valid file via browse or drag & drop.
  final ValueChanged<PickedLogoFile> onPicked;

  /// Called when the user removes the selected logo.
  final VoidCallback onRemove;

  /// True while the parent is persisting the logo to Firestore.
  final bool uploading;

  /// Upload progress in the range 0..1.
  final double progress;

  /// Disables picking (e.g. while the form is submitting).
  final bool enabled;

  /// Inline validation message shown under the drop zone.
  final String? errorText;

  @override
  State<LogoUploadField> createState() => _LogoUploadFieldState();
}

class _LogoUploadFieldState extends State<LogoUploadField> {
  void Function()? _disposeDropListener;
  bool _dragActive = false;
  bool _hovering = false;
  bool _picking = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _disposeDropListener = listenForLogoDragDrop(
      onFile: _handleFile,
      onHover: (active) {
        if (!mounted) return;
        setState(() => _dragActive = active);
      },
    );
  }

  @override
  void dispose() {
    _disposeDropListener?.call();
    super.dispose();
  }

  void _handleFile(PickedLogoFile file) {
    final error = _validate(file);
    if (!mounted) return;
    if (error != null) {
      setState(() => _localError = error);
      return;
    }
    setState(() {
      _localError = null;
      _dragActive = false;
    });
    widget.onPicked(file);
  }

  Future<void> _browse() async {
    if (!widget.enabled || widget.uploading || _picking) return;
    setState(() => _picking = true);
    try {
      final file = await pickLogoFile();
      if (file != null) _handleFile(file);
    } catch (_) {
      if (mounted) setState(() => _localError = 'Could not read the file.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  String? _validate(PickedLogoFile file) {
    if (!PickedLogoFile.allowedExtensions.contains(file.extension)) {
      return 'Unsupported file type. Please choose a PNG, JPG, JPEG or SVG.';
    }
    if (file.sizeInBytes > PickedLogoFile.maxSizeBytes) {
      return 'File is larger than 700 KB. Please choose a smaller logo.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasLogo = widget.logo != null;
    final effectiveError = widget.errorText ?? _localError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabel(),
        const SizedBox(height: 8),
        _buildDropZone(hasLogo: hasLogo, error: effectiveError),
        if (effectiveError != null) ...[
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
          'Company logo',
          style: TextStyle(
              color: kCoLabel, fontWeight: FontWeight.w700, fontSize: 13),
        ),
        SizedBox(width: 4),
        Text('(optional)', style: TextStyle(color: kCoSubtle, fontSize: 12)),
      ],
    );
  }

  Widget _buildDropZone({required bool hasLogo, String? error}) {
    if (widget.uploading) return _buildUploading();
    if (hasLogo) return _buildSelected();

    final borderColor = error != null
        ? kCoDanger
        : _dragActive || _hovering
            ? kCoAccent
            : kCoBorder;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        decoration: BoxDecoration(
          color: _dragActive || _hovering
              ? kCoAccent.withValues(alpha: 0.06)
              : AppThemeColors.darkCanvas,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: _dragActive || _hovering ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kCoAccent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: _picking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kCoAccent),
                    )
                  : const Icon(Icons.upload_rounded,
                      color: kCoAccent, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              _dragActive
                  ? 'Drop the logo to add it'
                  : 'Drag & drop your logo here',
              style: const TextStyle(
                color: kCoLabel,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'or',
              style: TextStyle(color: kCoSubtle, fontSize: 12),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.enabled ? _browse : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: kCoAccent,
                side: BorderSide(color: kCoAccent.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.folder_open_rounded, size: 17),
              label: const Text('Browse files',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 12),
            const Text(
              'PNG, JPG, JPEG or SVG  •  Recommended 512×512  •  Max 700 KB',
              style: TextStyle(color: kCoSubtle, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelected() {
    final logo = widget.logo!;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeColors.darkCanvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCoAccent.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Row(
        children: [
          _buildPreview(logo),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  logo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kCoLabel,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${logo.extension.toUpperCase()}  •  '
                  '${_formatBytes(logo.sizeInBytes)}',
                  style: const TextStyle(color: kCoSubtle, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: widget.enabled ? _browse : null,
            child: const Text('Change', style: TextStyle(color: kCoAccent)),
          ),
          IconButton(
            onPressed: widget.enabled ? widget.onRemove : null,
            icon: const Icon(Icons.delete_outline_rounded,
                color: kCoSubtle, size: 19),
            tooltip: 'Remove logo',
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(PickedLogoFile logo) {
    if (logo.isSvg) {
      return Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kCoAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.extension_rounded, color: kCoAccent, size: 24),
      );
    }
    try {
      return Container(
        width: 52,
        height: 52,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kCoAccent.withValues(alpha: 0.4)),
        ),
        child: Image.memory(logo.bytes, fit: BoxFit.cover),
      );
    } catch (_) {
      return Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kCoAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.image_outlined, color: kCoAccent, size: 24),
      );
    }
  }

  Widget _buildUploading() {
    final percent = (widget.progress.clamp(0.0, 1.0) * 100).round();
    return Container(
      padding: const EdgeInsets.all(18),
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
              const SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: kCoAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.logo?.name ?? 'Uploading logo…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: kCoLabel,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5),
                ),
              ),
              Text('$percent%',
                  style: const TextStyle(
                      color: kCoAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: widget.progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: kCoBorder,
              color: kCoAccent,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Encoding into Firestore…',
            style: TextStyle(color: kCoSubtle, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
