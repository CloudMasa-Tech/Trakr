// lib/widgets/common/trakr_logo.dart

import 'package:flutter/material.dart';

/// Preset brand logo sizes.
///
/// Use these for consistent, on-brand sizing instead of ad-hoc pixel values.
enum TrakrLogoSize {
  small(32),
  medium(56),
  large(96),
  xlarge(160);

  const TrakrLogoSize(this.value);

  final double value;
}

/// Reusable TRAKR brand logo.
///
/// Renders the canonical brand asset (icon + wordmark) with [BoxFit.contain]
/// so the aspect ratio is always preserved and the logo is never clipped or
/// distorted, regardless of the surrounding theme (light or dark).
///
/// Provide a raw [size] for an exact box, or use the named presets
/// ([sizePreset]) for consistent small / medium / large branding.
class TrakrLogo extends StatelessWidget {
  const TrakrLogo({
    super.key,
    this.size,
    this.sizePreset,
    this.width,
    this.height,
    this.semanticLabel = 'TRAKR',
  });

  /// Canonical brand asset (icon + wordmark).
  static const String assetPath = 'assets/download.png';

  /// Exact square box size. When set, overrides [sizePreset].
  final double? size;

  /// Named preset size. Ignored when [size] is provided.
  final TrakrLogoSize? sizePreset;

  /// Explicit box width. Overrides the resolved preset size.
  final double? width;

  /// Explicit box height. Overrides the resolved preset size.
  final double? height;

  /// Accessible label for screen readers.
  final String semanticLabel;

  double get _resolvedSize =>
      size ?? sizePreset?.value ?? TrakrLogoSize.medium.value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width ?? _resolvedSize,
          height: height ?? _resolvedSize,
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
