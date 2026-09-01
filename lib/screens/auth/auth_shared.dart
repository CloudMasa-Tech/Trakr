import 'package:flutter/material.dart';

import '../../providers/auth_session_provider.dart';
import '../../theme/app_theme_colors.dart';
import '../../widgets/common/trakr_logo.dart';

const Color authNavy = AppThemeColors.darkText;
const Color authSky = AppThemeColors.actionStart;
const Color authCard = AppThemeColors.darkSurface;
const Color authInput = AppThemeColors.darkCanvas;
const Color authBorder = AppThemeColors.darkBorder;
const Color authSubtext = AppThemeColors.darkMuted;

class AuthFormCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? header;
  final Widget form;
  final TextAlign titleAlign;
  final double headerGap;

  const AuthFormCard({
    super.key,
    required this.title,
    this.subtitle,
    this.header,
    this.titleAlign = TextAlign.start,
    this.headerGap = 28,
    required this.form,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: authCard,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.overlay,
            blurRadius: 40,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null) ...[
            header!,
            SizedBox(height: headerGap),
          ],
          Align(
            alignment: titleAlign == TextAlign.center
                ? Alignment.center
                : Alignment.centerLeft,
            child: AppGradientText(
              title,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: titleAlign == TextAlign.center
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: Text(
                subtitle!,
                textAlign: titleAlign,
                style: const TextStyle(
                  color: authSubtext,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
          form,
        ],
      ),
    );
  }
}

class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const LabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: authNavy,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class PortalLogo extends StatelessWidget {
  final double size;
  final double? width;
  final double? height;
  final double borderRadius;

  const PortalLogo({
    super.key,
    this.size = 96,
    this.width,
    this.height,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return TrakrLogo(
      width: width,
      height: height,
      size: size,
    );
  }
}

/// Canonical brand lockup for every auth / loading / splash screen — the exact
/// TRAKR logo, size, and spacing used on the Login screen. Auth screens must
/// render this widget instead of ad-hoc logos so branding stays pixel-identical.
class AuthBrandHeader extends StatelessWidget {
  const AuthBrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 620,
        height: 210,
        child: PortalLogo(
          width: 620,
          height: 210,
          borderRadius: 0,
        ),
      ),
    );
  }
}

/// Full-screen branded loading state for the auth flow. Uses the same dark
/// background, logo, spacing, and typography as the Login screen, showing only
/// a simple status line — never internal role-validation or technical details.
class AuthLoadingScreen extends StatelessWidget {
  final String? message;
  final String? errorMessage;

  const AuthLoadingScreen({
    super.key,
    this.message,
    this.errorMessage,
  });

  static int _buildCount = 0;

  @override
  Widget build(BuildContext context) {
    _buildCount++;
    AuthSessionProvider.timingLog(
        'AuthLoadingScreen.build #$_buildCount '
        'message=${message ?? '(default: Loading your workspace...)'} '
        'hasError=${errorMessage != null && errorMessage!.trim().isNotEmpty}');
    final status = (message == null || message!.trim().isEmpty)
        ? 'Loading your workspace...'
        : message!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        forceDark: true,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AuthBrandHeader(),
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: authSky,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: authNavy,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (errorMessage != null &&
                      errorMessage!.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: authSubtext,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GoogleAuthButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  const GoogleAuthButton({
    super.key,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: authNavy,
        side: const BorderSide(color: authBorder),
        backgroundColor: authInput,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GoogleGlyph(size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class GoogleGlyph extends StatelessWidget {
  final double size;

  const GoogleGlyph({
    super.key,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleGlyphPainter(),
      ),
    );
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.18;
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    void drawArc(Color color, double start, double sweep) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    drawArc(AppThemeColors.googleBlue, -0.15, 1.25);
    drawArc(AppThemeColors.googleRed, 1.20, 1.15);
    drawArc(AppThemeColors.googleYellow, 2.35, 1.05);
    drawArc(AppThemeColors.googleGreen, 3.35, 1.55);

    final linePaint = Paint()
      ..color = AppThemeColors.googleBlue
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final y = center.dy;
    canvas.drawLine(
      Offset(center.dx + radius * 0.08, y),
      Offset(size.width - stroke * 0.3, y),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AuthDivider extends StatelessWidget {
  final String label;

  const AuthDivider({
    super.key,
    this.label = 'or',
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(color: authBorder, height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: authSubtext,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
        const Expanded(
          child: Divider(color: authBorder, height: 1),
        ),
      ],
    );
  }
}

InputDecoration authInputDecoration(String hint, {IconData? prefixIcon}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: authSubtext,
      fontSize: 14,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: prefixIcon != null
        ? Icon(prefixIcon, color: authSubtext, size: 20)
        : null,
    filled: true,
    fillColor: authInput,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: authBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: authBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: authSky, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.dark.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.dark.error, width: 2),
    ),
  );
}
