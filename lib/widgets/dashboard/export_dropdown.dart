import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/attendance_model.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/export_helper.dart';

class ExportDropdown extends StatelessWidget {
  final List<AttendanceModel> records;
  final String fileNamePrefix;
  final Color? primaryColorOverride;
  final String Function(List<AttendanceModel> records)? fileNameBuilder;

  const ExportDropdown({
    super.key,
    required this.records,
    required this.fileNamePrefix,
    this.primaryColorOverride,
    this.fileNameBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final primaryColor = primaryColorOverride ?? colors.primary;

    return PopupMenuButton<String>(
      tooltip: 'Export options',
      offset: const Offset(0, 50),
      color: colors.surfaceRaised,
      elevation: 8,
      shadowColor: colors.overlay,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      onSelected: (value) async {
        final fileName = fileNameBuilder?.call(records) ??
            _defaultExportFileName(fileNamePrefix);
        try {
          switch (value) {
            case 'excel':
              await ExportHelper.exportToExcel(records, fileName);
              break;
            case 'csv':
              await ExportHelper.exportToCsv(records, fileName);
              break;
            case 'pdf':
              await ExportHelper.exportToPdf(records, fileName);
              break;
            case 'print':
              await ExportHelper.printLogs(records);
              break;
          }
        } catch (error) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Export failed: $error'),
              backgroundColor: colors.error,
            ),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          height: 30,
          child: Text(
            'Export As',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: colors.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        _buildItem(context, 'excel', 'Excel (.xlsx)',
            Icons.table_chart_outlined, colors.success),
        _buildItem(context, 'csv', 'CSV (.csv)', Icons.description_outlined,
            primaryColor),
        _buildItem(context, 'pdf', 'PDF (.pdf)', Icons.picture_as_pdf_outlined,
            colors.error),
        _buildItem(context, 'print', 'Print', Icons.print_outlined,
            colors.textSecondary),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: primaryColor.withValues(alpha: 0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ios_share_rounded, size: 16, color: primaryColor),
            const SizedBox(width: 10),
            Text(
              'Export',
              style: TextStyle(
                color: primaryColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: primaryColor),
          ],
        ),
      ),
    );
  }

  String _defaultExportFileName(String prefix) {
    final now = DateTime.now();
    final date = DateFormat('yyyy-MM-dd').format(now);
    final day = DateFormat('EEEE').format(now);
    return '${_safeFileNamePart(prefix)}_${date}_$day';
  }

  String _safeFileNamePart(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned.isEmpty ? 'Attendance' : cleaned;
  }

  PopupMenuItem<String> _buildItem(BuildContext context, String value,
      String label, IconData icon, Color iconColor) {
    return PopupMenuItem<String>(
      value: value,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
