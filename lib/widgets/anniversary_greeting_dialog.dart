import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/anniversary_greeting_service.dart';
import '../theme/app_theme_colors.dart';

Future<void> showAnniversaryGreetingDialog(
  BuildContext context,
  AnniversaryGreeting greeting,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AnniversaryGreetingDialog(greeting: greeting),
  );
}

class AnniversaryGreetingDialog extends StatefulWidget {
  final AnniversaryGreeting greeting;

  const AnniversaryGreetingDialog({
    super.key,
    required this.greeting,
  });

  @override
  State<AnniversaryGreetingDialog> createState() =>
      _AnniversaryGreetingDialogState();
}

class _AnniversaryGreetingDialogState extends State<AnniversaryGreetingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final years = widget.greeting.yearsCompleted;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 420,
              margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              decoration: BoxDecoration(
                color: AppThemeColors.celebrationBackground,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppThemeColors.celebrationBorder),
                boxShadow: [
                  BoxShadow(
                    color: AppThemeColors.celebrationBackground
                        .withValues(alpha: 0.4),
                    blurRadius: 34,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          AppThemeColors.celebrationGoldStart,
                          AppThemeColors.celebrationFlame,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: AppThemeColors.celebrationTitle,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Congratulations!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppThemeColors.celebrationTitle,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You have completed $years '
                    '${years == 1 ? 'year' : 'years'} in '
                    '${widget.greeting.companyName}.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppThemeColors.celebrationSubtitle,
                      fontSize: 17,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.greeting.employeeName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppThemeColors.celebrationGold,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppThemeColors.celebrationFlame,
                      foregroundColor: AppThemeColors.celebrationTitle,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Thank you',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _ConfettiPainter(progress: _controller.value),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final double progress;

  const _ConfettiPainter({required this.progress});

  static const _colors = [
    Color(0xFFFFC857),
    Color(0xFFFF7A18),
    Color(0xFF35C2FF),
    Color(0xFF22C55E),
    Color(0xFFFF4D8D),
    Colors.white,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 90; i++) {
      final seed = i * 41.0;
      final localProgress = (progress + (i % 15) / 15) % 1.0;
      final xBase = ((seed * 17) % 1000) / 1000 * size.width;
      final sway = math.sin(localProgress * math.pi * 2 + seed) * 28;
      final y = -48 + localProgress * (size.height + 116);
      final position = Offset(xBase + sway, y);
      final opacity = localProgress < .82
          ? 1.0
          : (1 - ((localProgress - .82) / .18)).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: opacity);
      final width = 5.0 + (i % 4) * 2;
      final height = 9.0 + (i % 5) * 2;

      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(localProgress * math.pi * 4 + seed);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: width, height: height),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
