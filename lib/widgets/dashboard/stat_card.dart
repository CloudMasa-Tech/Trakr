import 'package:flutter/material.dart';
import '../../theme/app_theme_colors.dart';

class StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final int count;
  final String label;
  final int? trendValue;
  final String trendLabel;
  final bool? isPositiveTrend;
  final bool showTrendAsText;
  final bool showFooter;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.count,
    required this.label,
    this.trendValue,
    required this.trendLabel,
    this.isPositiveTrend,
    this.showTrendAsText = false,
    this.showFooter = true,
    this.onTap,
  });

  bool get _isAbsent => label.toLowerCase().contains('absent');
  bool get _isLate => label.toLowerCase().contains('late');
  bool get _isEarly => label.toLowerCase().contains('early');

  Color _statusColor(AppColors colors) {
    if (_isAbsent) return colors.error;
    if (_isEarly || _isLate) return colors.warning;
    return colors.success;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final colors = AppColors.of(context);
    final statusColor = _statusColor(colors);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 100;
        final iconSize = isCompact ? 22.0 : (isMobile ? 32.0 : 36.0);
        final iconRadius = isCompact ? 7.0 : 10.0;
        final padding = isCompact ? 6.0 : (isMobile ? 12.0 : 16.0);
        final countSize = isCompact ? 17.0 : (isMobile ? 22.0 : 24.0);
        final labelSize = isCompact ? 8.5 : (isMobile ? 11.0 : 12.0);
        final footerSize = isCompact ? 8.0 : (isMobile ? 11.0 : 12.0);
        final showCompactFooter = showFooter && !isCompact;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.surface,
                  Color.alphaBlend(
                    statusColor.withValues(alpha: 0.07),
                    colors.surface,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.35),
              ),
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(iconRadius),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: isCompact ? 12 : (isMobile ? 16 : 18),
                  ),
                ),
                const Spacer(),
                Text(
                  '$count',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: countSize,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: isCompact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: labelSize,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                  ),
                ),
                if (showCompactFooter) ...[
                  const SizedBox(height: 4),
                  if (showTrendAsText ||
                      trendValue == null ||
                      isPositiveTrend == null)
                    Text(
                      trendLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: footerSize,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Icon(
                          isPositiveTrend!
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          color:
                              isPositiveTrend! ? colors.success : colors.error,
                          size: isMobile ? 11 : 13,
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            '$trendValue% $trendLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isPositiveTrend!
                                  ? colors.success
                                  : colors.error,
                              fontSize: footerSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
