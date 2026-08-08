// lib/screens/admin/team_directory_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:csv/csv.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../firebase/firebase_context_provider.dart';
import '../../models/manager_model.dart';
import '../../models/staff.dart';
import '../../providers/auth_session_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/email_service.dart';
import '../../services/manager_account_service.dart';
import '../../services/staff_service.dart';
import '../../theme/app_theme_colors.dart';
import '../../utils/country_options.dart';
import '../../utils/departments.dart';
import '../../utils/export_helper.dart';
import '../manager/onboard_user_dialog.dart';

class TeamDirectoryScreen extends StatefulWidget {
  const TeamDirectoryScreen({super.key});

  @override
  State<TeamDirectoryScreen> createState() => _TeamDirectoryScreenState();
}

class _TeamAdminTheme {
  static const surface = AppThemeColors.darkSurface;
  static const border = AppThemeColors.darkBorder;
  static const text = AppThemeColors.darkText;
  static const muted = AppThemeColors.darkMuted;
  static const primary = Color(0xFF0F766E);
  static const danger = Color(0xFFFF3D4F);
  static const white = Color(0xFFFFFFFF);
  static const shadow = Color(0x126B7897);
  static const green = Color(0xFF4CAF50);
  static const green400 = Color(0xFF66BB6A);
  static const red = Color(0xFFF44336);
  static const orange = Color(0xFFFF9800);
  static const amber700 = Color(0xFFFFA000);
  static const grey400 = Color(0xFFBDBDBD);
  static const grey500 = Color(0xFF9E9E9E);
  static const grey800 = Color(0xFF424242);
  static const greySubtle = Color(0xFF94A3B8);
  static const slateDeep = Color(0xFF0F172A);
}

ImageProvider? _directoryProfileImage(String? photoUrl) {
  final raw = photoUrl?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('data:image')) {
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return MemoryImage(base64Decode(payload));
    } catch (_) {
      return null;
    }
  }
  return NetworkImage(raw);
}

String _formatDirectorySalary(double? salary) {
  if (salary == null) return 'Salary -';
  return 'Salary INR ${NumberFormat.decimalPattern().format(salary)}';
}

class _DirectoryAvatar extends StatelessWidget {
  final String name;
  final String fallback;
  final String? photoUrl;
  final Color color;
  final double radius;

  const _DirectoryAvatar({
    required this.name,
    required this.fallback,
    required this.photoUrl,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final image = _directoryProfileImage(photoUrl);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.2),
      backgroundImage: image,
      child: image == null
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : fallback,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            )
          : null,
    );
  }
}

class _TeamDirectoryScreenState extends State<TeamDirectoryScreen> {
  final FirebaseFirestore _db = FirebaseContextProvider.current.firestore;
  final StaffService _staffService = StaffService();
  final ManagerAccountService _managerAccountService = ManagerAccountService();
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _selectedTabIndex = 0; // 0 for Employee, 1 for Manager
  bool _isImporting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openOnboardDialog() async {
    final auth = context.read<AuthSessionProvider>();
    await OnboardUserDialog.show(
      context,
      currentManagerName: '',
      currentManagerEmail: '',
      onboarderRole: auth.role ?? AppUserRole.companyAdmin,
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 700;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 12 : 32,
              isCompact ? 12 : 32,
              isCompact ? 12 : 32,
              isCompact ? 10 : 32,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isCompact: isCompact),
                SizedBox(height: isCompact ? 10 : 18),
                _buildToolbar(isCompact: isCompact),
                SizedBox(height: isCompact ? 10 : 24),
                Expanded(child: _buildTable(isCompact: isCompact)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader({required bool isCompact}) {
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Team Directory',
          style: TextStyle(
            fontSize: isCompact ? 22 : 26,
            fontWeight: FontWeight.bold,
            color: _TeamAdminTheme.text,
            letterSpacing: -0.5,
          ),
        ),
        if (!isCompact) ...[
          const SizedBox(height: 5),
          const Text(
            'Manage employees and managers, their reporting structure, and access.',
            style: TextStyle(fontSize: 13.5, color: _TeamAdminTheme.muted),
          ),
        ],
      ],
    );

    final importButton = OutlinedButton.icon(
      onPressed: _isImporting ? null : _importUsers,
      icon: _isImporting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_rounded, size: 18),
      label: Text(
        _isImporting ? 'Importing' : 'Import',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _TeamAdminTheme.primary,
        side: const BorderSide(color: _TeamAdminTheme.primary),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 14 : 20,
          vertical: isCompact ? 11 : 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    final onboardButton = ElevatedButton.icon(
      onPressed: _openOnboardDialog,
      icon: const Icon(Icons.person_add_alt_1_rounded,
          color: _TeamAdminTheme.white, size: 18),
      label: const Text(
        'Onboard User',
        style: TextStyle(
          color: _TeamAdminTheme.white,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: _TeamAdminTheme.primary,
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 14 : 20,
          vertical: isCompact ? 11 : 14,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleBlock,
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: importButton),
              const SizedBox(width: 10),
              Expanded(child: onboardButton),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: titleBlock),
        const SizedBox(width: 16),
        importButton,
        const SizedBox(width: 12),
        onboardButton,
      ],
    );
  }

  Widget _buildToolbar({required bool isCompact}) {
    final tabs = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _TeamAdminTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _TeamAdminTheme.border),
      ),
      child: Row(
        mainAxisSize: isCompact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _TabButton(
            title: 'Employee List',
            isSelected: _selectedTabIndex == 0,
            expand: isCompact,
            onTap: () => setState(() => _selectedTabIndex = 0),
          ),
          _TabButton(
            title: 'Manager List',
            isSelected: _selectedTabIndex == 1,
            expand: isCompact,
            onTap: () => setState(() => _selectedTabIndex = 1),
          ),
        ],
      ),
    );

    final searchField = Container(
      decoration: BoxDecoration(
        color: _TeamAdminTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _TeamAdminTheme.border),
      ),
      child: TextField(
        controller: _searchCtrl,
        cursorColor: _TeamAdminTheme.primary,
        style: const TextStyle(
          color: _TeamAdminTheme.slateDeep,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: _TeamAdminTheme.white,
          hintText: _selectedTabIndex == 0
              ? 'Search employees...'
              : 'Search managers...',
          hintStyle: const TextStyle(
            color: _TeamAdminTheme.greySubtle,
            fontWeight: FontWeight.w500,
          ),
          prefixIcon:
              const Icon(Icons.search, color: _TeamAdminTheme.greySubtle),
          border: InputBorder.none,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _TeamAdminTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: _TeamAdminTheme.primary,
              width: 1.4,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: isCompact ? 11 : 14,
          ),
        ),
        onChanged: (value) =>
            setState(() => _searchQuery = value.trim().toLowerCase()),
      ),
    );

    final exportButton = OutlinedButton.icon(
      onPressed: () => _showExportMenu(context),
      icon: const Icon(Icons.download_rounded, size: 18),
      label: const Text('Export', overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor: _TeamAdminTheme.primary,
        side: const BorderSide(color: _TeamAdminTheme.primary),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 12 : 16,
          vertical: isCompact ? 11 : 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tabs,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 10),
              exportButton,
            ],
          ),
        ],
      );
    }

    return Row(
      children: [
        tabs,
        const SizedBox(width: 24),
        Expanded(child: searchField),
        const SizedBox(width: 12),
        exportButton,
      ],
    );
  }

  Future<void> _showExportMenu(BuildContext context) async {
    final format = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 150, 0, 0),
      color: _TeamAdminTheme.surface,
      items: [
        const PopupMenuItem(
          value: 'csv',
          child: _ExportMenuItem(
            icon: Icons.description_outlined,
            label: 'Export as CSV',
          ),
        ),
        const PopupMenuItem(
          value: 'excel',
          child: _ExportMenuItem(
            icon: Icons.table_chart_outlined,
            label: 'Export as Excel',
          ),
        ),
        const PopupMenuItem(
          value: 'pdf',
          child: _ExportMenuItem(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Export as PDF',
          ),
        ),
        const PopupMenuItem(
          value: 'json',
          child: _ExportMenuItem(
            icon: Icons.data_object_rounded,
            label: 'Export as JSON',
          ),
        ),
        const PopupMenuItem(
          value: 'text',
          child: _ExportMenuItem(
            icon: Icons.notes_outlined,
            label: 'Export as Text',
          ),
        ),
      ],
    );

    if (format != null) {
      await _exportData(format, _selectedTabIndex);
    }
  }

  // ─── Tables ────────────────────────────────────────────────────────────────

  Widget _buildTable({required bool isCompact}) {
    return Container(
      decoration: BoxDecoration(
        color: _TeamAdminTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _TeamAdminTheme.border),
        boxShadow: const [
          BoxShadow(
            color: _TeamAdminTheme.shadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isCompact) _tableHeader(),
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildEmployeeTableBody()
                : _buildManagerTableBody(),
          ),
        ],
      ),
    );
  }

  Widget _tableHeader() {
    final labels = _selectedTabIndex == 0
        ? const [
            'EMPLOYEE',
            'CONTACT',
            'JOB DETAILS',
            'REPORTING',
            'PROFILE',
          ]
        : const [
            'MANAGER',
            'CONTACT',
            'JOB DETAILS',
            'TEAM',
            'PROFILE',
          ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
      decoration: const BoxDecoration(
        color: AppThemeColors.darkCanvas,
        border:
            Border(bottom: BorderSide(color: _TeamAdminTheme.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _ColLabel(labels[0])),
          Expanded(flex: 3, child: _ColLabel(labels[1])),
          Expanded(flex: 3, child: _ColLabel(labels[2])),
          Expanded(flex: 2, child: _ColLabel(labels[3])),
          Expanded(flex: 2, child: _ColLabel(labels[4])),
          const Expanded(flex: 1, child: _ColLabel('ACTION', center: true)),
        ],
      ),
    );
  }

  // Employee Table specific
  Widget _buildEmployeeTableBody() {
    return StreamBuilder<List<Staff>>(
      stream: _staffService.getAllStaff(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _TeamAdminTheme.primary));
        }

        final allStaff = snapshot.data ?? [];
        final staffList = allStaff.where((s) {
          if (_searchQuery.isEmpty) return true;
          return s.name.toLowerCase().contains(_searchQuery) ||
              s.employeeId.toLowerCase().contains(_searchQuery) ||
              s.email.toLowerCase().contains(_searchQuery) ||
              s.phone.toLowerCase().contains(_searchQuery) ||
              s.department.toLowerCase().contains(_searchQuery) ||
              s.position.toLowerCase().contains(_searchQuery);
        }).toList();

        if (staffList.isEmpty) {
          return const _EmptyState(message: 'No employees found.');
        }

        final isMobile = MediaQuery.of(context).size.width < 850;
        return ListView.separated(
          padding: EdgeInsets.only(
            top: isMobile ? 2 : 0,
            bottom: isMobile ? 14 : 0,
          ),
          itemCount: staffList.length,
          separatorBuilder: (_, __) => isMobile
              ? const SizedBox.shrink()
              : const Divider(height: 1, color: _TeamAdminTheme.border),
          itemBuilder: (context, i) => _EmployeeRow(
            staff: staffList[i],
            onEdit: () => _openEditEmployeeDialog(staffList[i]),
            onDelete: () => _confirmDeleteEmployee(staffList[i]),
          ),
        );
      },
    );
  }

  // Manager Table specific
  Widget _buildManagerTableBody() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db.collection('managers').orderBy('name').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: _TeamAdminTheme.primary));
        }

        final docs = snapshot.data?.docs ?? [];
        final managers = docs.map((d) {
          return ManagerModel.fromFirestore(
              d.data() as Map<String, dynamic>, d.id);
        }).where((m) {
          if (_searchQuery.isEmpty) return true;
          return m.name.toLowerCase().contains(_searchQuery) ||
              m.employeeId.toLowerCase().contains(_searchQuery) ||
              m.email.toLowerCase().contains(_searchQuery) ||
              m.phone.toLowerCase().contains(_searchQuery) ||
              m.department.toLowerCase().contains(_searchQuery) ||
              m.position.toLowerCase().contains(_searchQuery);
        }).toList();

        if (managers.isEmpty) {
          return const _EmptyState(message: 'No managers found.');
        }

        final isMobile = MediaQuery.of(context).size.width < 850;
        return ListView.separated(
          padding: EdgeInsets.only(
            top: isMobile ? 2 : 0,
            bottom: isMobile ? 14 : 0,
          ),
          itemCount: managers.length,
          separatorBuilder: (_, __) => isMobile
              ? const SizedBox.shrink()
              : const Divider(height: 1, color: _TeamAdminTheme.border),
          itemBuilder: (context, i) => _ManagerRow(
            manager: managers[i],
            onEdit: () => _openEditManagerDialog(managers[i]),
            onDelete: () => _confirmDeleteManager(managers[i]),
          ),
        );
      },
    );
  }

  // ─── Edit Dialogs ──────────────────────────────────────────────────────────

  void _openEditEmployeeDialog(Staff staff) {
    showDialog(
      context: context,
      builder: (ctx) => _EditEmployeeDialog(
        staff: staff,
        staffService: _staffService,
      ),
    );
  }

  void _openEditManagerDialog(ManagerModel manager) {
    showDialog(
      context: context,
      builder: (ctx) => _EditManagerDialog(
        manager: manager,
        db: _db,
        staffService: _staffService,
      ),
    );
  }

  // ─── Deletion ──────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteEmployee(Staff staff) async {
    final ok = await _showConfirmDialog(
      'Delete Employee',
      'Remove "${staff.name}" from the employee list? This cannot be undone.',
    );
    if (ok == true) {
      await AttendanceService().clearProfileIdentityFromLogs(
        employeeId: staff.employeeId,
        employeeName: staff.name,
      );
      await _staffService.deleteStaff(staff.id);
    }
  }

  Future<void> _confirmDeleteManager(ManagerModel manager) async {
    final ok = await _showConfirmDialog(
      'Delete Manager',
      'Remove "${manager.name}" from the managers list? This cannot be undone.',
    );
    if (ok == true) {
      await AttendanceService().clearProfileIdentityFromLogs(
        employeeId: manager.employeeId,
        employeeName: manager.name,
      );
      await _db.collection('managers').doc(manager.id).delete();
    }
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _TeamAdminTheme.surface,
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: _TeamAdminTheme.text)),
        content:
            Text(content, style: const TextStyle(color: _TeamAdminTheme.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: _TeamAdminTheme.muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _TeamAdminTheme.danger,
              foregroundColor: _TeamAdminTheme.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── Export/Import ─────────────────────────────────────────────────────────

  Future<void> _exportData(String format, int tabIndex) async {
    try {
      if (tabIndex == 0) {
        // Export Employees
        final staffList = await _staffService.getAllStaff().first;
        final filtered = staffList.where((s) {
          if (_searchQuery.isEmpty) return true;
          return s.name.toLowerCase().contains(_searchQuery) ||
              s.employeeId.toLowerCase().contains(_searchQuery) ||
              s.email.toLowerCase().contains(_searchQuery) ||
              s.phone.toLowerCase().contains(_searchQuery) ||
              s.department.toLowerCase().contains(_searchQuery) ||
              s.position.toLowerCase().contains(_searchQuery);
        }).toList();

        final rows = <List<dynamic>>[
          [
            'User Type',
            'Name',
            'Employee ID',
            'Email',
            'Phone',
            'Designation',
            'Position',
            'Reports To',
            'Join Date',
            'Blood Group',
            'Gender',
            'Nationality',
            'Date of Birth',
            'Address',
            'Status'
          ],
          ...filtered.map((s) => [
                'Employee',
                s.name,
                s.employeeId,
                s.email,
                s.phone,
                s.department,
                s.position,
                s.reportsTo ?? '',
                DateFormat('yyyy-MM-dd').format(s.joinDate),
                s.bloodGroup ?? '',
                s.gender ?? '',
                s.nationality ?? '',
                s.dob != null ? DateFormat('yyyy-MM-dd').format(s.dob!) : '',
                s.address ?? '',
                s.isActive ? 'Active' : 'Inactive',
              ])
        ];
        await _saveExport(
            rows, format, 'employees_${DateTime.now().millisecondsSinceEpoch}');
      } else {
        // Export Managers
        final snap = await _db.collection('managers').get();
        final managers = snap.docs
            .map((d) => ManagerModel.fromFirestore(d.data(), d.id))
            .where((m) {
          if (_searchQuery.isEmpty) return true;
          return m.name.toLowerCase().contains(_searchQuery) ||
              m.employeeId.toLowerCase().contains(_searchQuery) ||
              m.email.toLowerCase().contains(_searchQuery) ||
              m.phone.toLowerCase().contains(_searchQuery) ||
              m.department.toLowerCase().contains(_searchQuery) ||
              m.position.toLowerCase().contains(_searchQuery);
        }).toList();

        final rows = <List<dynamic>>[
          [
            'User Type',
            'Name',
            'Manager ID',
            'Email',
            'Phone',
            'Designation',
            'Position',
            'Staff Count',
            'Max Staff',
            'Join Date',
            'Blood Group',
            'Gender',
            'Nationality',
            'Date of Birth',
            'Address',
            'Status'
          ],
          ...managers.map((m) => [
                'Manager',
                m.name,
                m.employeeId,
                m.email,
                m.phone,
                m.department,
                m.position,
                m.staffCount,
                m.maxStaff,
                m.joinDate != null
                    ? DateFormat('yyyy-MM-dd').format(m.joinDate!)
                    : '',
                m.bloodGroup ?? '',
                m.gender ?? '',
                m.nationality ?? '',
                m.dob != null ? DateFormat('yyyy-MM-dd').format(m.dob!) : '',
                m.address ?? '',
                m.status,
              ])
        ];
        await _saveExport(
            rows, format, 'managers_${DateTime.now().millisecondsSinceEpoch}');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Exported successfully'),
              backgroundColor: _TeamAdminTheme.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              backgroundColor: _TeamAdminTheme.red),
        );
      }
    }
  }

  Future<void> _saveExport(
      List<List<dynamic>> rows, String format, String fileName) async {
    switch (format) {
      case 'excel':
        final workbook = Excel.createExcel();
        final sheet = workbook[workbook.getDefaultSheet() ?? 'Sheet1'];
        for (final row in rows) {
          sheet.appendRow(
              row.map((cell) => TextCellValue(cell.toString())).toList());
        }
        final bytes = workbook.encode();
        if (bytes != null) {
          await ExportHelper.saveBytes(
            name: fileName,
            bytes: Uint8List.fromList(bytes),
            ext: 'xlsx',
            mimeType: MimeType.microsoftExcel,
          );
        }
        return;
      case 'pdf':
        final pdf = pw.Document();
        final headers = rows.first.map((cell) => cell.toString()).toList();
        final data = rows.skip(1).map((row) {
          return row.map((cell) => cell.toString()).toList();
        }).toList();

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(18),
            build: (context) => [
              pw.Text(
                _selectedTabIndex == 0
                    ? 'Employee Directory'
                    : 'Manager Directory',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: headers,
                data: data,
                headerStyle: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
                cellStyle: const pw.TextStyle(fontSize: 6),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellAlignment: pw.Alignment.centerLeft,
                cellPadding: const pw.EdgeInsets.all(3),
              ),
            ],
          ),
        );

        await ExportHelper.saveBytes(
          name: fileName,
          bytes: await pdf.save(),
          ext: 'pdf',
          mimeType: MimeType.pdf,
        );
        return;
      case 'json':
        final jsonRows = _rowsToJson(rows);
        const encoder = JsonEncoder.withIndent('  ');
        await ExportHelper.saveBytes(
          name: fileName,
          bytes: Uint8List.fromList(utf8.encode(encoder.convert(jsonRows))),
          ext: 'json',
          mimeType: MimeType.json,
        );
        return;
      case 'text':
        final text = rows.map((row) {
          return row.map((cell) => cell.toString()).join('\t');
        }).join('\n');
        await ExportHelper.saveBytes(
          name: fileName,
          bytes: Uint8List.fromList(utf8.encode(text)),
          ext: 'txt',
          mimeType: MimeType.text,
        );
        return;
      case 'csv':
      default:
        final csv = const ListToCsvConverter().convert(rows);
        await ExportHelper.saveBytes(
          name: fileName,
          bytes: Uint8List.fromList(utf8.encode(csv)),
          ext: 'csv',
          mimeType: MimeType.csv,
        );
    }
  }

  List<Map<String, dynamic>> _rowsToJson(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];
    final headers = rows.first.map((cell) => cell.toString()).toList();
    return rows.skip(1).map((row) {
      final record = <String, dynamic>{};
      for (var i = 0; i < headers.length; i++) {
        record[headers[i]] = i < row.length ? row[i] : '';
      }
      return record;
    }).toList();
  }

  Future<void> _importUsers() async {
    if (_isImporting) return;

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _isImporting = true);
    final summary = _ImportSummary();

    try {
      for (final file in result.files) {
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) {
          summary.skipped++;
          continue;
        }

        late final List<List<String>> rows;
        try {
          rows = _rowsFromImportFile(file.name, bytes);
        } catch (_) {
          summary.failed++;
          continue;
        }

        if (rows.isEmpty) {
          summary.skipped++;
          continue;
        }

        for (final row in _recordsFromRows(rows)) {
          try {
            final imported = await _upsertImportedUser(row);
            if (imported.type == _ImportedUserType.manager) {
              summary.managers++;
            } else if (imported.type == _ImportedUserType.employee) {
              summary.employees++;
            } else {
              summary.skipped++;
            }
          } catch (_) {
            summary.failed++;
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import complete: ${summary.employees} employees, ${summary.managers} managers, ${summary.skipped} skipped, ${summary.failed} failed.',
          ),
          backgroundColor: summary.failed > 0
              ? _TeamAdminTheme.orange
              : _TeamAdminTheme.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import failed: $e'),
          backgroundColor: _TeamAdminTheme.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  List<List<String>> _rowsFromImportFile(String fileName, Uint8List bytes) {
    final extension = fileName.split('.').last.toLowerCase();
    if (extension == 'json') {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      final items = decoded is List
          ? decoded
          : decoded is Map<String, dynamic>
              ? (decoded['users'] ?? decoded['rows'] ?? decoded['data'])
              : null;
      if (items is! List) return const [];

      final maps = items.whereType<Map>().toList();
      final headers = <String>[];
      for (final item in maps) {
        for (final key in item.keys) {
          final text = key.toString();
          if (!headers.contains(text)) headers.add(text);
        }
      }
      if (headers.isEmpty) return const [];
      return [
        headers,
        ...maps.map((item) => headers
            .map((header) => item[header]?.toString().trim() ?? '')
            .toList())
      ];
    }

    if (extension == 'xlsx' || extension == 'xls') {
      final excel = Excel.decodeBytes(bytes);
      final rows = <List<String>>[];
      for (final sheetName in excel.tables.keys) {
        final table = excel.tables[sheetName];
        if (table == null) continue;
        for (final row in table.rows) {
          final values =
              row.map((cell) => cell?.value?.toString().trim() ?? '').toList();
          if (values.any((value) => value.isNotEmpty)) rows.add(values);
        }
      }
      return rows;
    }

    final content = utf8.decode(bytes, allowMalformed: true);
    final delimiter = _detectDelimiter(content);
    return const CsvToListConverter(
      shouldParseNumbers: false,
      allowInvalid: true,
    )
        .convert(content, fieldDelimiter: delimiter)
        .map((row) => row.map((cell) => cell.toString().trim()).toList())
        .where((row) => row.any((value) => value.isNotEmpty))
        .toList();
  }

  String _detectDelimiter(String content) {
    final firstLine = content
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');
    final candidates = {
      ',': ','.allMatches(firstLine).length,
      '\t': '\t'.allMatches(firstLine).length,
      ';': ';'.allMatches(firstLine).length,
    };
    return candidates.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<Map<String, String>> _recordsFromRows(List<List<String>> rows) {
    if (rows.isEmpty) return const [];
    final headerIndex = rows.indexWhere(
      (row) =>
          row.any((cell) {
            final header = _normalizeHeader(cell);
            return header == 'name' ||
                header == 'fullname' ||
                header.contains('employeeid') ||
                header.contains('managerid') ||
                header.contains('staffid');
          }) ||
          row.any((cell) => _normalizeHeader(cell) == 'email'),
    );
    if (headerIndex == -1) return const [];

    final headers = rows[headerIndex].map(_normalizeHeader).toList();
    return rows.skip(headerIndex + 1).map((row) {
      final map = <String, String>{};
      for (var i = 0; i < headers.length && i < row.length; i++) {
        if (headers[i].isEmpty) continue;
        map[headers[i]] = row[i].trim();
      }
      return map;
    }).where((map) {
      return _field(map, const ['name']).isNotEmpty ||
          _field(map, const ['email']).isNotEmpty ||
          _field(map, const ['employeeid', 'id', 'staffid', 'managerid'])
              .isNotEmpty;
    }).toList();
  }

  String _normalizeHeader(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _field(Map<String, String> row, List<String> keys,
      {String fallback = ''}) {
    for (final key in keys) {
      final normalized = _normalizeHeader(key);
      final value = row[normalized]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return fallback;
  }

  Future<_ImportedUserImportResult> _upsertImportedUser(
    Map<String, String> row,
  ) async {
    final roleValue = _field(row, const [
      'role',
      'type',
      'userType',
      'designation',
      'position',
    ]).toLowerCase();
    final isManager = roleValue.contains('manager') ||
        roleValue.contains('admin manager') ||
        (_selectedTabIndex == 1 && !roleValue.contains('staff'));

    final name = _field(row, const ['name', 'fullname', 'employeename']);
    final email = _field(row, const ['email', 'mail', 'emailaddress'])
        .trim()
        .toLowerCase();
    final employeeId = _field(
      row,
      const ['employeeid', 'managerid', 'staffid', 'id'],
      fallback: email.isNotEmpty
          ? email.split('@').first
          : 'IMP-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (name.isEmpty && email.isEmpty) {
      return const _ImportedUserImportResult();
    }

    final phone = _field(row, const ['phone', 'mobile', 'contact', 'number']);
    final department = displayDepartment(_field(
      row,
      const ['department', 'designation', 'division', 'team'],
      fallback: 'Cloud Engineer',
    ));
    final position = _field(
      row,
      const ['position', 'jobtitle', 'title', 'role'],
      fallback: isManager ? 'Manager' : 'Staff',
    );
    final statusText =
        _field(row, const ['status', 'active'], fallback: 'active')
            .toLowerCase();
    final isActive =
        !(statusText.contains('inactive') || statusText.contains('disabled'));
    final joinDate = _parseImportDate(
      _field(row, const ['joindate', 'joiningdate', 'datejoined', 'startdate']),
    );
    final dobText = _field(row, const [
      'dob',
      'dateofbirth',
      'birthdate',
      'datebirth',
    ]);
    final dob = dobText.trim().isEmpty ? null : _parseImportDate(dobText);
    final bloodGroup = _field(row, const [
      'bloodgroup',
      'blood',
      'bloodtype',
    ]);
    final gender = _field(row, const ['gender', 'sex']);
    final nationality = _field(row, const ['nationality', 'nation']);
    final address = _field(row, const [
      'address',
      'homeaddress',
      'residentialaddress',
      'location',
    ]);
    final password = _field(
        row,
        const [
          'password',
          'temporarypassword',
          'temppassword',
          'loginpassword',
        ],
        fallback: _temporaryPassword());
    var credentialEmailSent = false;
    var credentialEmailFailed = false;

    if (isManager) {
      final managerData = {
        'name': name.isNotEmpty ? name : employeeId,
        'email': email,
        'employeeId': employeeId,
        'department': department,
        'phone': phone,
        'position': position,
        'staffCount': int.tryParse(_field(row, const ['staffcount'])) ?? 0,
        'maxStaff':
            int.tryParse(_field(row, const ['maxstaff', 'capacity'])) ?? 20,
        'status': isActive ? 'active' : 'inactive',
        'joinDate': Timestamp.fromDate(joinDate),
        'hasRegistered': false,
        'bloodGroup': bloodGroup,
        'gender': gender,
        'nationality': nationality,
        'dob': dob != null ? Timestamp.fromDate(dob) : null,
        'address': address,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final existing = await _findExistingDoc('managers', employeeId, email);
      if (existing == null && isActive && email.isNotEmpty) {
        await _managerAccountService.createManagerAccount(
          name: name.isNotEmpty ? name : employeeId,
          email: email,
          password: password,
          phone: phone,
          employeeId: employeeId,
          department: department,
          position: position,
          staffCount: int.tryParse(_field(row, const ['staffcount'])) ?? 0,
          maxStaff:
              int.tryParse(_field(row, const ['maxstaff', 'capacity'])) ?? 20,
          joinDate: joinDate,
          status: 'active',
          bloodGroup: bloodGroup,
          gender: gender,
          nationality: nationality,
          dob: dob,
          address: address,
        );
        try {
          await EmailService.sendAccountCredentials(
            recipientEmail: email,
            password: password,
            roleLabel: 'manager',
            recipientName: name,
          );
          credentialEmailSent = true;
        } catch (_) {
          credentialEmailFailed = true;
        }
      } else {
        await _upsertManager(managerData);
      }
      return _ImportedUserImportResult(
        type: _ImportedUserType.manager,
        credentialEmailSent: credentialEmailSent,
        credentialEmailFailed: credentialEmailFailed,
      );
    }

    final staffData = {
      'name': name.isNotEmpty ? name : employeeId,
      'email': email,
      'phone': phone,
      'department': department,
      'position': position,
      'employeeId': employeeId,
      'reportsTo': _field(row, const ['reportsto', 'manager', 'managername']),
      'joinDate': Timestamp.fromDate(joinDate),
      'role': 'staff',
      'isActive': isActive,
      'hasRegistered': false,
      'bloodGroup': bloodGroup,
      'gender': gender,
      'nationality': nationality,
      'dob': dob != null ? Timestamp.fromDate(dob) : null,
      'address': address,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final existing = await _findExistingDoc('staff', employeeId, email);
    if (existing == null && isActive && email.isNotEmpty) {
      final staff = Staff(
        id: '',
        name: name.isNotEmpty ? name : employeeId,
        email: email,
        phone: phone,
        department: department,
        position: position,
        employeeId: employeeId,
        joinDate: joinDate,
        reportsTo: _field(row, const ['reportsto', 'manager', 'managername']),
        role: 'staff',
        password: password,
        isActive: true,
        hasRegistered: true,
        bloodGroup: bloodGroup,
        gender: gender,
        nationality: nationality,
        dob: dob,
        address: address,
      );
      await _staffService.addStaff(staff);
      try {
        await EmailService.sendAccountCredentials(
          recipientEmail: email,
          password: password,
          roleLabel: 'employee',
          recipientName: name,
        );
        credentialEmailSent = true;
      } catch (_) {
        credentialEmailFailed = true;
      }
    } else {
      await _upsertStaff(staffData);
    }
    return _ImportedUserImportResult(
      type: _ImportedUserType.employee,
      credentialEmailSent: credentialEmailSent,
      credentialEmailFailed: credentialEmailFailed,
    );
  }

  String _temporaryPassword() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = stamp.length > 6 ? stamp.substring(stamp.length - 6) : stamp;
    return 'Temp@$suffix';
  }

  DateTime _parseImportDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return DateTime.now();

    final numeric = num.tryParse(trimmed);
    if (numeric != null && numeric > 20000) {
      return DateTime(1899, 12, 30).add(Duration(days: numeric.floor()));
    }

    for (final pattern in const [
      'yyyy-MM-dd',
      'dd-MM-yyyy',
      'MM/dd/yyyy',
      'dd/MM/yyyy',
      'MMM dd, yyyy',
    ]) {
      try {
        return DateFormat(pattern).parseStrict(trimmed);
      } catch (_) {}
    }
    return DateTime.tryParse(trimmed) ?? DateTime.now();
  }

  Future<void> _upsertStaff(Map<String, dynamic> data) async {
    final employeeId = data['employeeId']?.toString().trim() ?? '';
    final email = data['email']?.toString().trim() ?? '';
    final existing = await _findExistingDoc('staff', employeeId, email);
    if (existing == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await _db.collection('staff').add(data);
    } else {
      await existing.reference.set(data, SetOptions(merge: true));
    }
  }

  Future<void> _upsertManager(Map<String, dynamic> data) async {
    final employeeId = data['employeeId']?.toString().trim() ?? '';
    final email = data['email']?.toString().trim() ?? '';
    final existing = await _findExistingDoc('managers', employeeId, email);
    if (existing == null) {
      data['createdAt'] = FieldValue.serverTimestamp();
      await _db.collection('managers').add(data);
    } else {
      await existing.reference.set(data, SetOptions(merge: true));
    }
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findExistingDoc(
    String collection,
    String employeeId,
    String email,
  ) async {
    if (employeeId.isNotEmpty) {
      final byEmployeeId = await _db
          .collection(collection)
          .where('employeeId', isEqualTo: employeeId)
          .limit(1)
          .get();
      if (byEmployeeId.docs.isNotEmpty) return byEmployeeId.docs.first;
    }
    if (email.isNotEmpty) {
      final byEmail = await _db
          .collection(collection)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) return byEmail.docs.first;
    }
    return null;
  }
}

enum _ImportedUserType { employee, manager }

class _ImportedUserImportResult {
  final _ImportedUserType? type;
  final bool credentialEmailSent;
  final bool credentialEmailFailed;

  const _ImportedUserImportResult({
    this.type,
    this.credentialEmailSent = false,
    this.credentialEmailFailed = false,
  });
}

class _ImportSummary {
  int employees = 0;
  int managers = 0;
  int credentialEmails = 0;
  int credentialEmailFailed = 0;
  int skipped = 0;
  int failed = 0;
}

// ─── Minor Widgets ───────────────────────────────────────────────────────────

class _TabButton extends StatelessWidget {
  final String title;
  final bool isSelected;
  final bool expand;
  final VoidCallback onTap;

  const _TabButton({
    required this.title,
    required this.isSelected,
    this.expand = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: expand ? 12 : 20,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? _TeamAdminTheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected ? _TeamAdminTheme.primary : _TeamAdminTheme.muted,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );

    return expand ? Expanded(child: button) : button;
  }
}

class _ColLabel extends StatelessWidget {
  final String text;
  final bool center;
  const _ColLabel(this.text, {this.center = false});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: center ? TextAlign.center : TextAlign.left,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: _TeamAdminTheme.muted,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _ExportMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ExportMenuItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _TeamAdminTheme.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            color: _TeamAdminTheme.text,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.group_outlined,
              size: 56, color: _TeamAdminTheme.grey800),
          const SizedBox(height: 14),
          Text(message,
              style: const TextStyle(
                  color: _TeamAdminTheme.grey500,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _DirectoryDetail {
  final IconData icon;
  final String label;
  final String value;

  const _DirectoryDetail({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _MobileDirectoryCard extends StatelessWidget {
  final Widget avatar;
  final String title;
  final String subtitle;
  final Color statusColor;
  final String statusLabel;
  final List<Widget> actions;
  final List<_DirectoryDetail> primaryDetails;
  final List<_DirectoryDetail> expandedDetails;

  const _MobileDirectoryCard({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.statusColor,
    required this.statusLabel,
    required this.actions,
    required this.primaryDetails,
    required this.expandedDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _TeamAdminTheme.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: _TeamAdminTheme.white.withValues(alpha: 0.07)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: _TeamAdminTheme.primary.withValues(alpha: 0.08),
          highlightColor: _TeamAdminTheme.primary.withValues(alpha: 0.06),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          collapsedIconColor: _TeamAdminTheme.muted,
          iconColor: _TeamAdminTheme.primary,
          leading: avatar,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _TeamAdminTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _MobileStatusPill(color: statusColor, label: statusLabel),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: _TeamAdminTheme.muted, fontSize: 12),
            ),
          ),
          trailing: SizedBox(
            width: 92,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ...actions,
                const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
              ],
            ),
          ),
          children: [
            const Divider(color: _TeamAdminTheme.border, height: 14),
            _MobileDetailGrid(details: primaryDetails),
            if (expandedDetails.isNotEmpty) ...[
              const SizedBox(height: 8),
              _MobileDetailGrid(details: expandedDetails),
            ],
          ],
        ),
      ),
    );
  }
}

class _MobileStatusPill extends StatelessWidget {
  final Color color;
  final String label;

  const _MobileStatusPill({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MobileDetailGrid extends StatelessWidget {
  final List<_DirectoryDetail> details;

  const _MobileDetailGrid({required this.details});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 9,
          children: details
              .map((detail) => SizedBox(
                    width: itemWidth,
                    child: _MobileDetailItem(detail: detail),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _MobileDetailItem extends StatelessWidget {
  final _DirectoryDetail detail;

  const _MobileDetailItem({required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(detail.icon, size: 15, color: _TeamAdminTheme.muted),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _TeamAdminTheme.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                detail.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _TeamAdminTheme.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Row Widgets ─────────────────────────────────────────────────────────────

class _EmployeeRow extends StatelessWidget {
  final Staff staff;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EmployeeRow({
    required this.staff,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        staff.isActive ? _TeamAdminTheme.green400 : _TeamAdminTheme.grey400;
    final mediaWidth = MediaQuery.of(context).size.width;
    final isMobile = mediaWidth < 850;

    if (isMobile) {
      return _MobileDirectoryCard(
        avatar: _DirectoryAvatar(
          name: staff.name,
          fallback: 'E',
          photoUrl: staff.photoUrl,
          color: _TeamAdminTheme.primary,
          radius: 18,
        ),
        title: staff.name,
        subtitle: staff.employeeId,
        statusColor: statusColor,
        statusLabel: staff.isActive ? 'Active' : 'Inactive',
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            icon: const Icon(Icons.edit_outlined,
                color: _TeamAdminTheme.primary, size: 19),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            icon: const Icon(Icons.delete_outline,
                color: _TeamAdminTheme.danger, size: 19),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
        primaryDetails: [
          _DirectoryDetail(
            icon: Icons.badge_outlined,
            label: 'Position',
            value: staff.position,
          ),
          _DirectoryDetail(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: staff.phone.isEmpty ? '-' : staff.phone,
          ),
          _DirectoryDetail(
            icon: Icons.business_outlined,
            label: 'Designation',
            value: displayDepartment(staff.department),
          ),
          _DirectoryDetail(
            icon: Icons.payments_outlined,
            label: 'Salary',
            value: _formatDirectorySalary(staff.salary),
          ),
          _DirectoryDetail(
            icon: Icons.supervisor_account_outlined,
            label: 'Reports To',
            value: staff.reportsTo?.isEmpty == false ? staff.reportsTo! : '-',
          ),
        ],
        expandedDetails: [
          _DirectoryDetail(
            icon: Icons.email_outlined,
            label: 'Email',
            value: staff.email,
          ),
          _DirectoryDetail(
            icon: Icons.calendar_today_outlined,
            label: 'Joined',
            value: DateFormat('MMM dd, yyyy').format(staff.joinDate),
          ),
          _DirectoryDetail(
            icon: Icons.bloodtype_outlined,
            label: 'Blood / Gender',
            value:
                '${staff.bloodGroup?.isNotEmpty == true ? staff.bloodGroup! : '-'} / ${staff.gender?.isNotEmpty == true ? staff.gender! : '-'}',
          ),
          _DirectoryDetail(
            icon: Icons.cake_outlined,
            label: 'DOB / Nationality',
            value:
                '${staff.dob != null ? DateFormat('MMM dd, yyyy').format(staff.dob!) : '-'} / ${staff.nationality?.isNotEmpty == true ? staff.nationality! : '-'}',
          ),
          _DirectoryDetail(
            icon: Icons.home_outlined,
            label: 'Address',
            value: staff.address?.isNotEmpty == true ? staff.address! : '-',
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _DirectoryAvatar(
                  name: staff.name,
                  fallback: 'E',
                  photoUrl: staff.photoUrl,
                  color: _TeamAdminTheme.primary,
                  radius: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name,
                          style: const TextStyle(
                              color: _TeamAdminTheme.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(staff.employeeId,
                          style: const TextStyle(
                              color: _TeamAdminTheme.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.email,
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(staff.phone.isEmpty ? '-' : staff.phone,
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(staff.address?.isNotEmpty == true ? staff.address! : '-',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.position,
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(displayDepartment(staff.department),
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(_formatDirectorySalary(staff.salary),
                    style: const TextStyle(
                        color: _TeamAdminTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                    'Blood: ${staff.bloodGroup?.isNotEmpty == true ? staff.bloodGroup! : '-'} | ${staff.gender?.isNotEmpty == true ? staff.gender! : '-'}',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.reportsTo?.isEmpty == false ? staff.reportsTo! : '-',
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                    staff.nationality?.isNotEmpty == true
                        ? staff.nationality!
                        : '-',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('MMM dd, yyyy').format(staff.joinDate),
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    staff.dob != null
                        ? 'DOB ${DateFormat('MMM dd, yyyy').format(staff.dob!)}'
                        : 'DOB -',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: statusColor),
                    ),
                    const SizedBox(width: 4),
                    Text(staff.isActive ? 'Active' : 'Inactive',
                        style: TextStyle(color: statusColor, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: _TeamAdminTheme.primary, size: 18),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: _TeamAdminTheme.danger, size: 18),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagerRow extends StatelessWidget {
  final ManagerModel manager;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ManagerRow({
    required this.manager,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = manager.status == 'active'
        ? _TeamAdminTheme.green400
        : _TeamAdminTheme.grey400;
    final mediaWidth = MediaQuery.of(context).size.width;
    final isMobile = mediaWidth < 850;

    if (isMobile) {
      final statusLabel = manager.status == 'active'
          ? 'Active'
          : manager.status == 'on_leave'
              ? 'On Leave'
              : 'Inactive';

      return _MobileDirectoryCard(
        avatar: _DirectoryAvatar(
          name: manager.name,
          fallback: 'M',
          photoUrl: manager.photoUrl,
          color: _TeamAdminTheme.amber700,
          radius: 18,
        ),
        title: manager.name,
        subtitle: manager.employeeId,
        statusColor: statusColor,
        statusLabel: statusLabel,
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            icon: const Icon(Icons.edit_outlined,
                color: _TeamAdminTheme.primary, size: 19),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 34),
            icon: const Icon(Icons.delete_outline,
                color: _TeamAdminTheme.danger, size: 19),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
        primaryDetails: [
          _DirectoryDetail(
            icon: Icons.badge_outlined,
            label: 'Position',
            value: manager.position,
          ),
          _DirectoryDetail(
            icon: Icons.phone_outlined,
            label: 'Phone',
            value: manager.phone.isEmpty ? '-' : manager.phone,
          ),
          _DirectoryDetail(
            icon: Icons.business_outlined,
            label: 'Designation',
            value: displayDepartment(manager.department),
          ),
          _DirectoryDetail(
            icon: Icons.payments_outlined,
            label: 'Salary',
            value: _formatDirectorySalary(manager.salary),
          ),
          _DirectoryDetail(
            icon: Icons.supervisor_account_outlined,
            label: 'Team Size',
            value: '${manager.staffCount} / ${manager.maxStaff}',
          ),
        ],
        expandedDetails: [
          _DirectoryDetail(
            icon: Icons.email_outlined,
            label: 'Email',
            value: manager.email,
          ),
          _DirectoryDetail(
            icon: Icons.calendar_today_outlined,
            label: 'Joined',
            value: manager.joinDate != null
                ? DateFormat('MMM dd, yyyy').format(manager.joinDate!)
                : '-',
          ),
          _DirectoryDetail(
            icon: Icons.bloodtype_outlined,
            label: 'Blood / Gender',
            value:
                '${manager.bloodGroup?.isNotEmpty == true ? manager.bloodGroup! : '-'} / ${manager.gender?.isNotEmpty == true ? manager.gender! : '-'}',
          ),
          _DirectoryDetail(
            icon: Icons.cake_outlined,
            label: 'DOB / Nationality',
            value:
                '${manager.dob != null ? DateFormat('MMM dd, yyyy').format(manager.dob!) : '-'} / ${manager.nationality?.isNotEmpty == true ? manager.nationality! : '-'}',
          ),
          _DirectoryDetail(
            icon: Icons.home_outlined,
            label: 'Address',
            value: manager.address?.isNotEmpty == true ? manager.address! : '-',
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _DirectoryAvatar(
                  name: manager.name,
                  fallback: 'M',
                  photoUrl: manager.photoUrl,
                  color: _TeamAdminTheme.amber700,
                  radius: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(manager.name,
                          style: const TextStyle(
                              color: _TeamAdminTheme.text,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(manager.employeeId,
                          style: const TextStyle(
                              color: _TeamAdminTheme.muted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(manager.email,
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(manager.phone.isEmpty ? '-' : manager.phone,
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                    manager.address?.isNotEmpty == true
                        ? manager.address!
                        : '-',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(manager.position,
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(displayDepartment(manager.department),
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Text(_formatDirectorySalary(manager.salary),
                    style: const TextStyle(
                        color: _TeamAdminTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                    'Blood: ${manager.bloodGroup?.isNotEmpty == true ? manager.bloodGroup! : '-'} | ${manager.gender?.isNotEmpty == true ? manager.gender! : '-'}',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${manager.staffCount} / ${manager.maxStaff}',
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 14)),
                const SizedBox(height: 2),
                const Text('Employees',
                    style:
                        TextStyle(color: _TeamAdminTheme.muted, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                    manager.nationality?.isNotEmpty == true
                        ? manager.nationality!
                        : '-',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    manager.joinDate != null
                        ? DateFormat('MMM dd, yyyy').format(manager.joinDate!)
                        : '-',
                    style: const TextStyle(
                        color: _TeamAdminTheme.text, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    manager.dob != null
                        ? 'DOB ${DateFormat('MMM dd, yyyy').format(manager.dob!)}'
                        : 'DOB -',
                    style: const TextStyle(
                        color: _TeamAdminTheme.muted, fontSize: 11)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: statusColor),
                    ),
                    const SizedBox(width: 4),
                    Text(
                        manager.status == 'active'
                            ? 'Active'
                            : manager.status == 'on_leave'
                                ? 'On Leave'
                                : 'Inactive',
                        style: TextStyle(color: statusColor, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: _TeamAdminTheme.primary, size: 18),
                  onPressed: onEdit,
                  tooltip: 'Edit',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: _TeamAdminTheme.danger, size: 18),
                  onPressed: onDelete,
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Simple Edit Dialogs ─────────────────────────────────────────────────────

class _EditEmployeeDialog extends StatefulWidget {
  final Staff staff;
  final StaffService staffService;

  const _EditEmployeeDialog({required this.staff, required this.staffService});

  @override
  State<_EditEmployeeDialog> createState() => _EditEmployeeDialogState();
}

class _EditEmployeeDialogState extends State<_EditEmployeeDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _employeeIdCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _posCtrl;
  late TextEditingController _salaryCtrl;
  late TextEditingController _reportsCtrl;
  late TextEditingController _addressCtrl;
  String _selectedDialCode = '+91';
  String? _selectedDept;
  String? _selectedBloodGroup;
  String? _selectedGender;
  String? _selectedNationality;
  DateTime _joinDate = DateTime.now();
  DateTime? _dob;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.staff.name);
    _emailCtrl = TextEditingController(text: widget.staff.email);
    _employeeIdCtrl = TextEditingController(text: widget.staff.employeeId);
    _selectedDialCode = splitDialCodeFromPhone(widget.staff.phone);
    _phoneCtrl =
        TextEditingController(text: phoneWithoutDialCode(widget.staff.phone));
    _posCtrl = TextEditingController(text: widget.staff.position);
    _salaryCtrl = TextEditingController(
      text: widget.staff.salary == null ? '' : widget.staff.salary.toString(),
    );
    _reportsCtrl = TextEditingController(text: widget.staff.reportsTo ?? '');
    _addressCtrl = TextEditingController(text: widget.staff.address ?? '');
    _selectedDept = displayDepartment(widget.staff.department);
    _selectedBloodGroup = widget.staff.bloodGroup;
    _selectedGender = widget.staff.gender;
    if (!const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
        .contains(_selectedBloodGroup)) {
      _selectedBloodGroup = null;
    }
    if (!const ['Male', 'Female', 'Other'].contains(_selectedGender)) {
      _selectedGender = null;
    }
    _selectedNationality =
        kNationalityOptions.contains(widget.staff.nationality)
            ? widget.staff.nationality
            : null;
    _joinDate = widget.staff.joinDate;
    _dob = widget.staff.dob;
    _isActive = widget.staff.isActive;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _employeeIdCtrl.dispose();
    _phoneCtrl.dispose();
    _posCtrl.dispose();
    _salaryCtrl.dispose();
    _reportsCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _TeamAdminTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Edit Employee',
          style: TextStyle(color: _TeamAdminTheme.text)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _twoCol(
                  _field(_nameCtrl, 'Full Name', required: true),
                  _field(_emailCtrl, 'Email',
                      keyboardType: TextInputType.emailAddress, required: true),
                ),
                const SizedBox(height: 12),
                _twoCol(
                  _phoneField(),
                  _field(_employeeIdCtrl, 'Employee ID', required: true),
                ),
                const SizedBox(height: 12),
                _twoCol(
                  _departmentDropdown(),
                  _field(_posCtrl, 'Position', required: true),
                ),
                const SizedBox(height: 12),
                _field(
                  _salaryCtrl,
                  'Salary',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _salaryValidator,
                ),
                const SizedBox(height: 12),
                _twoCol(_joinDatePicker(), _managerDropdown()),
                const SizedBox(height: 12),
                _twoCol(_bloodGroupDropdown(), _genderDropdown()),
                const SizedBox(height: 12),
                _twoCol(
                  _nationalityDropdown(),
                  _dobPicker(),
                ),
                const SizedBox(height: 12),
                _field(_addressCtrl, 'Address', required: true, maxLines: 2),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Active',
                      style: TextStyle(color: _TeamAdminTheme.text)),
                  value: _isActive,
                  activeThumbColor: _TeamAdminTheme.primary,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: _TeamAdminTheme.muted)),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      if (_dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Date of Birth is required')),
        );
        return;
      }
      await widget.staffService.updateStaff(widget.staff.id, {
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'employeeId': _employeeIdCtrl.text.trim(),
        'phone': '$_selectedDialCode ${_phoneCtrl.text.trim()}'.trim(),
        'department': _selectedDept ?? '',
        'position': _posCtrl.text.trim(),
        'salary': _parseSalary(),
        'joinDate': Timestamp.fromDate(_joinDate),
        'reportsTo':
            _reportsCtrl.text.trim().isEmpty ? null : _reportsCtrl.text.trim(),
        'isActive': _isActive,
        'bloodGroup': _selectedBloodGroup,
        'gender': _selectedGender,
        'nationality': _selectedNationality,
        'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
        'address': _addressCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _twoCol(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  TextFormField _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool required = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: _TeamAdminTheme.text),
      cursorColor: _TeamAdminTheme.primary,
      decoration: _inputDecoration(label),
      validator: validator ??
          (required
              ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
              : null),
    );
  }

  double? _parseSalary() {
    final raw = _salaryCtrl.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String? _salaryValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final salary = double.tryParse(raw);
    if (salary == null) return 'Enter a valid salary';
    if (salary < 0) return 'Salary cannot be negative';
    return null;
  }

  Widget _departmentDropdown() {
    return DropdownButtonFormField<String>(
      initialValue:
          kAppDepartments.contains(_selectedDept) ? _selectedDept : null,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Designation'),
      items: kAppDepartments
          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
          .toList(),
      onChanged: (v) => setState(() => _selectedDept = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _phoneField() {
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      style: const TextStyle(color: _TeamAdminTheme.text),
      cursorColor: _TeamAdminTheme.primary,
      decoration: _inputDecoration('Phone').copyWith(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDialCode,
              dropdownColor: _TeamAdminTheme.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _TeamAdminTheme.muted, size: 18),
              items: kPhoneDialCodeOptions
                  .map((code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text(
                          code,
                          style: const TextStyle(
                            color: _TeamAdminTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedDialCode = value ?? '+91'),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 86, minHeight: 0),
      ),
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _nationalityDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedNationality,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Nationality'),
      items: kNationalityOptions
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedNationality = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _managerDropdown() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseContextProvider.current.firestore
          .collection('managers')
          .snapshots(),
      builder: (context, snapshot) {
        final managers =
            snapshot.data?.docs.map((d) => d['name'] as String).toList() ?? [];
        final currentValue =
            managers.contains(_reportsCtrl.text) ? _reportsCtrl.text : null;
        return DropdownButtonFormField<String>(
          initialValue: currentValue,
          dropdownColor: _TeamAdminTheme.surface,
          style: const TextStyle(color: _TeamAdminTheme.text),
          decoration: _inputDecoration('Reports To'),
          items: [
            const DropdownMenuItem(value: null, child: Text('None')),
            ...managers.map((m) => DropdownMenuItem(value: m, child: Text(m))),
          ],
          onChanged: (v) => setState(() => _reportsCtrl.text = v ?? ''),
        );
      },
    );
  }

  Widget _bloodGroupDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedBloodGroup,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Blood Group'),
      items: const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedBloodGroup = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _genderDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Gender'),
      items: const ['Male', 'Female', 'Other']
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedGender = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _joinDatePicker() {
    return _dateField(
      label: 'Date of Joining',
      value: DateFormat('dd MMM yyyy').format(_joinDate),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _joinDate,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) setState(() => _joinDate = picked);
      },
    );
  }

  Widget _dobPicker() {
    return _dateField(
      label: 'Date of Birth',
      value: _dob == null
          ? 'Select Date of Birth'
          : DateFormat('dd MMM yyyy').format(_dob!),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _dob ?? DateTime(1995),
          firstDate: DateTime(1940),
          lastDate: DateTime.now().subtract(const Duration(days: 365 * 15)),
        );
        if (picked != null) setState(() => _dob = picked);
      },
    );
  }

  Widget _dateField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: _TeamAdminTheme.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: _TeamAdminTheme.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _TeamAdminTheme.muted),
      filled: true,
      fillColor: AppThemeColors.darkCanvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _TeamAdminTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: _TeamAdminTheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _TeamAdminTheme.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _TeamAdminTheme.danger),
      ),
    );
  }
}

class _EditManagerDialog extends StatefulWidget {
  final ManagerModel manager;
  final FirebaseFirestore db;
  final StaffService staffService;

  const _EditManagerDialog({
    required this.manager,
    required this.db,
    required this.staffService,
  });

  @override
  State<_EditManagerDialog> createState() => _EditManagerDialogState();
}

class _EditManagerDialogState extends State<_EditManagerDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _employeeIdCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _posCtrl;
  late TextEditingController _salaryCtrl;
  late TextEditingController _maxCtrl;
  late TextEditingController _addressCtrl;
  String _selectedDialCode = '+91';
  String? _selectedDept;
  String? _selectedBloodGroup;
  String? _selectedGender;
  String? _selectedNationality;
  DateTime _joinDate = DateTime.now();
  DateTime? _dob;
  String _status = 'active';

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.manager.name);
    _emailCtrl = TextEditingController(text: widget.manager.email);
    _employeeIdCtrl = TextEditingController(text: widget.manager.employeeId);
    _selectedDialCode = splitDialCodeFromPhone(widget.manager.phone);
    _phoneCtrl = TextEditingController(
      text: phoneWithoutDialCode(widget.manager.phone),
    );
    _posCtrl = TextEditingController(text: widget.manager.position);
    _salaryCtrl = TextEditingController(
      text:
          widget.manager.salary == null ? '' : widget.manager.salary.toString(),
    );
    _maxCtrl = TextEditingController(text: widget.manager.maxStaff.toString());
    _addressCtrl = TextEditingController(text: widget.manager.address ?? '');
    _selectedDept = displayDepartment(widget.manager.department);
    _selectedBloodGroup = widget.manager.bloodGroup;
    _selectedGender = widget.manager.gender;
    if (!const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
        .contains(_selectedBloodGroup)) {
      _selectedBloodGroup = null;
    }
    if (!const ['Male', 'Female', 'Other'].contains(_selectedGender)) {
      _selectedGender = null;
    }
    _selectedNationality =
        kNationalityOptions.contains(widget.manager.nationality)
            ? widget.manager.nationality
            : null;
    _joinDate = widget.manager.joinDate ?? DateTime.now();
    _dob = widget.manager.dob;
    _status = widget.manager.status;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _employeeIdCtrl.dispose();
    _phoneCtrl.dispose();
    _posCtrl.dispose();
    _salaryCtrl.dispose();
    _maxCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _TeamAdminTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Edit Manager',
          style: TextStyle(color: _TeamAdminTheme.text)),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _twoCol(
                  _field(_nameCtrl, 'Full Name', required: true),
                  _field(_emailCtrl, 'Email',
                      keyboardType: TextInputType.emailAddress, required: true),
                ),
                const SizedBox(height: 12),
                _twoCol(
                  _phoneField(),
                  _field(_employeeIdCtrl, 'Manager ID', required: true),
                ),
                const SizedBox(height: 12),
                _twoCol(
                  _departmentDropdown(),
                  _field(_posCtrl, 'Position', required: true),
                ),
                const SizedBox(height: 12),
                _field(
                  _salaryCtrl,
                  'Salary',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _salaryValidator,
                ),
                const SizedBox(height: 12),
                _twoCol(
                  _joinDatePicker(),
                  _field(_maxCtrl, 'Max Employees',
                      keyboardType: TextInputType.number, required: true),
                ),
                const SizedBox(height: 12),
                _twoCol(_bloodGroupDropdown(), _genderDropdown()),
                const SizedBox(height: 12),
                _twoCol(
                  _nationalityDropdown(),
                  _dobPicker(),
                ),
                const SizedBox(height: 12),
                _field(_addressCtrl, 'Address', required: true, maxLines: 2),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  dropdownColor: _TeamAdminTheme.surface,
                  style: const TextStyle(color: _TeamAdminTheme.text),
                  decoration: _inputDecoration('Status'),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                        value: 'on_leave', child: Text('On Leave')),
                    DropdownMenuItem(
                        value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: (v) => setState(() => _status = v!),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: _TeamAdminTheme.muted)),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() async {
    if (_formKey.currentState!.validate()) {
      if (_dob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Date of Birth is required')),
        );
        return;
      }
      await widget.db.collection('managers').doc(widget.manager.id).update({
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim().toLowerCase(),
        'employeeId': _employeeIdCtrl.text.trim(),
        'phone': '$_selectedDialCode ${_phoneCtrl.text.trim()}'.trim(),
        'department': _selectedDept ?? '',
        'position': _posCtrl.text.trim(),
        'salary': _parseSalary(),
        'joinDate': Timestamp.fromDate(_joinDate),
        'maxStaff': int.tryParse(_maxCtrl.text.trim()) ?? 20,
        'status': _status,
        'bloodGroup': _selectedBloodGroup,
        'gender': _selectedGender,
        'nationality': _selectedNationality,
        'dob': _dob != null ? Timestamp.fromDate(_dob!) : null,
        'address': _addressCtrl.text.trim(),
      });

      // Update names across staff that report to this manager if name changed
      if (_nameCtrl.text.trim() != widget.manager.name) {
        final staffList = await widget.staffService
            .getTeamMemberIdsByManager(widget.manager.name);
        for (var staff in staffList) {
          await widget.staffService
              .updateStaff(staff, {'reportsTo': _nameCtrl.text.trim()});
        }
      }

      if (mounted) Navigator.pop(context);
    }
  }

  Widget _twoCol(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  TextFormField _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool required = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: _TeamAdminTheme.text),
      cursorColor: _TeamAdminTheme.primary,
      decoration: _inputDecoration(label),
      validator: validator ??
          (required
              ? (v) => v == null || v.trim().isEmpty ? 'Required' : null
              : null),
    );
  }

  double? _parseSalary() {
    final raw = _salaryCtrl.text.trim();
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  String? _salaryValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) return null;
    final salary = double.tryParse(raw);
    if (salary == null) return 'Enter a valid salary';
    if (salary < 0) return 'Salary cannot be negative';
    return null;
  }

  Widget _departmentDropdown() {
    return DropdownButtonFormField<String>(
      initialValue:
          kAppDepartments.contains(_selectedDept) ? _selectedDept : null,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Designation'),
      items: kAppDepartments
          .map((d) => DropdownMenuItem(value: d, child: Text(d)))
          .toList(),
      onChanged: (v) => setState(() => _selectedDept = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _phoneField() {
    return TextFormField(
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      style: const TextStyle(color: _TeamAdminTheme.text),
      cursorColor: _TeamAdminTheme.primary,
      decoration: _inputDecoration('Phone').copyWith(
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedDialCode,
              dropdownColor: _TeamAdminTheme.surface,
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _TeamAdminTheme.muted, size: 18),
              items: kPhoneDialCodeOptions
                  .map((code) => DropdownMenuItem<String>(
                        value: code,
                        child: Text(
                          code,
                          style: const TextStyle(
                            color: _TeamAdminTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedDialCode = value ?? '+91'),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 86, minHeight: 0),
      ),
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _nationalityDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedNationality,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Nationality'),
      items: kNationalityOptions
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedNationality = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _bloodGroupDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedBloodGroup,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Blood Group'),
      items: const ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedBloodGroup = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _genderDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender,
      dropdownColor: _TeamAdminTheme.surface,
      style: const TextStyle(color: _TeamAdminTheme.text),
      decoration: _inputDecoration('Gender'),
      items: const ['Male', 'Female', 'Other']
          .map((v) => DropdownMenuItem(value: v, child: Text(v)))
          .toList(),
      onChanged: (v) => setState(() => _selectedGender = v),
      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
    );
  }

  Widget _joinDatePicker() {
    return _dateField(
      label: 'Date of Joining',
      value: DateFormat('dd MMM yyyy').format(_joinDate),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _joinDate,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) setState(() => _joinDate = picked);
      },
    );
  }

  Widget _dobPicker() {
    return _dateField(
      label: 'Date of Birth',
      value: _dob == null
          ? 'Select Date of Birth'
          : DateFormat('dd MMM yyyy').format(_dob!),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _dob ?? DateTime(1995),
          firstDate: DateTime(1940),
          lastDate: DateTime.now().subtract(const Duration(days: 365 * 15)),
        );
        if (picked != null) setState(() => _dob = picked);
      },
    );
  }

  Widget _dateField({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _inputDecoration(label),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: _TeamAdminTheme.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: _TeamAdminTheme.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: _TeamAdminTheme.muted),
      filled: true,
      fillColor: AppThemeColors.darkCanvas,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _TeamAdminTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
            const BorderSide(color: _TeamAdminTheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _TeamAdminTheme.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _TeamAdminTheme.danger),
      ),
    );
  }
}
