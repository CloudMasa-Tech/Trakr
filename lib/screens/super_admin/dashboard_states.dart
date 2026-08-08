import 'package:flutter/material.dart';

import '../../theme/portal_palette.dart';

/// Full-page loading placeholder for the platform dashboard. Mirrors the
/// dashboard layout (header, KPI cards, charts) with gently pulsing blocks so
/// first paint does not jump when real data arrives.
class DashboardSkeleton extends StatefulWidget {
  const DashboardSkeleton({super.key});

  @override
  State<DashboardSkeleton> createState() => _DashboardSkeletonState();
}

class _DashboardSkeletonState extends State<DashboardSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.45,
      upperBound: 1.0,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PortalPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: FadeTransition(
            opacity: _controller,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _block(palette, width: 260, height: 22, radius: 6),
                const SizedBox(height: 10),
                _block(palette, width: 420, height: 14, radius: 6),
                const SizedBox(height: 24),
                _metricRow(palette),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _card(
                        palette,
                        child: _block(palette, height: 150, radius: 8),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _card(
                        palette,
                        child: _block(palette, height: 150, radius: 8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _card(
                  palette,
                  child: Column(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        Row(
                          children: [
                            _block(palette, width: 34, height: 34, radius: 10),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _block(palette, height: 12, radius: 6),
                            ),
                            const SizedBox(width: 40),
                            _block(palette, width: 60, height: 12, radius: 6),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metricRow(PortalPalette palette) {
    final cards = <Widget>[];
    for (var i = 0; i < 6; i++) {
      cards.add(
        Expanded(
          child: _card(
            palette,
            child: Row(
              children: [
                _block(palette, width: 36, height: 36, radius: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _block(palette, width: 60, height: 15, radius: 6),
                      const SizedBox(height: 6),
                      _block(palette, width: 90, height: 10, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (i < 5) const SizedBox(width: 12);
    }
    return Row(children: cards);
  }

  Widget _card(PortalPalette palette, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }

  Widget _block(
    PortalPalette palette, {
    double? width,
    required double height,
    required double radius,
  }) {
    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: palette.border.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Full-page error state shown when the dashboard cannot load its initial
/// data (network failure, timeout, permissions). Offers a retry.
class DashboardErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const DashboardErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PortalPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: palette.danger.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded,
                  color: palette.danger, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load the dashboard',
              style: TextStyle(
                color: palette.label,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message == null
                  ? 'Something went wrong while loading platform data.'
                  : 'Something went wrong while loading platform data: $message',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: palette.subtle, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact inline error used when a live stream fails after initial load.
class SectionErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const SectionErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final palette = PortalPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: palette.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: palette.subtle, fontSize: 12.5),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: palette.accent),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
