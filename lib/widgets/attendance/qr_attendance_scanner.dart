import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../models/staff.dart';
import '../../providers/auth_session_provider.dart';
import '../../services/attendance_service.dart';
import '../../services/geo_fence_service.dart';
import '../../theme/app_theme_colors.dart';

class QrAttendanceScanner extends StatefulWidget {
  final AppUserRole role;

  const QrAttendanceScanner({super.key, required this.role});

  @override
  State<QrAttendanceScanner> createState() => _QrAttendanceScannerState();
}

class _QrAttendanceScannerState extends State<QrAttendanceScanner> {
  final AttendanceService _attendanceService = AttendanceService();
  final GeoFenceService _geoFenceService = GeoFenceService();
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _manualInputController = TextEditingController();

  String? _token;
  String? _employeeId;
  Staff? _staff;
  String? _scanStatus;
  String? _errorText;
  bool _isWorking = false;
  final DateTime _selectedDate = DateTime.now();
  AttendanceSubmissionResult? _lastResult;

  @override
  void initState() {
    super.initState();
    _loadCurrentStaffDetails();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isWorking) return;
    if (capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null || rawValue.trim().isEmpty) return;

    await _applyScannedPayload(rawValue.trim());
  }

  Future<void> _applyScannedPayload(String payload) async {
    setState(() {
      _scanStatus = 'QR detected. Parsing code...';
      _errorText = null;
      _lastResult = null;
    });

    final parsed = _parseScanPayload(payload);
    if (parsed.token == null && parsed.employeeId == null) {
      setState(() {
        _scanStatus = null;
        _errorText = 'Scan did not contain a valid attendance QR token.';
      });
      return;
    }

    _token = parsed.token ?? _token;
    _employeeId = parsed.employeeId ?? _employeeId;

    if (_employeeId != null) {
      await _loadStaffDetails(_employeeId!);
    } else {
      await _loadCurrentStaffDetails();
    }

    setState(() {
      _scanStatus =
          'Admin QR loaded. ${_staff != null ? 'Ready to submit.' : 'Signed-in profile pending.'}';
      _errorText = null;
    });
  }

  Future<void> _loadCurrentStaffDetails() async {
    final user = FirebaseContextProvider.current.auth.currentUser;
    if (user == null) {
      setState(() {
        _errorText =
            'Unable to identify the signed-in user. Sign in again to continue.';
      });
      return;
    }
    await _loadSignedInProfile(user);
  }

  Future<void> _loadSignedInProfile(User user) async {
    setState(() => _isWorking = true);
    try {
      final staff = await _attendanceService.getStaffByUserIdentity(
        uid: user.uid,
        email: user.email,
      );
      if (staff == null) {
        setState(() {
          _staff = null;
          _employeeId = null;
          _errorText =
              'No staff or manager profile found for the signed-in account.';
          _scanStatus = null;
        });
        return;
      }

      setState(() {
        _staff = staff;
        _employeeId = staff.employeeId.trim().isNotEmpty
            ? staff.employeeId.trim()
            : staff.email.trim().isNotEmpty
                ? staff.email.trim()
                : user.uid;
      });
    } catch (error) {
      setState(() {
        _staff = null;
        _employeeId = null;
        _errorText = 'Unable to load signed-in profile. ${error.toString()}';
      });
    } finally {
      setState(() => _isWorking = false);
    }
  }

  Future<void> _loadStaffDetails(String employeeId) async {
    setState(() => _isWorking = true);
    try {
      final staff = await _attendanceService.getStaffByEmployeeId(employeeId);
      if (staff == null) {
        setState(() {
          _staff = null;
          _errorText = 'No employee data found for ID "$employeeId".';
          _scanStatus = null;
        });
        return;
      }

      setState(() {
        _staff = staff;
        _employeeId = employeeId;
      });
    } catch (error) {
      setState(() {
        _staff = null;
        _errorText = 'Unable to load employee data. ${error.toString()}';
      });
    } finally {
      setState(() => _isWorking = false);
    }
  }

  _ParsedQrPayload _parseScanPayload(String raw) {
    String? token;
    String? employeeId;

    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        token = decoded['token']?.toString();
        employeeId = decoded['employeeId']?.toString();
      }
    } catch (_) {
      // Not JSON, continue with query parsing.
    }

    if (raw.contains('=')) {
      final uri = Uri.tryParse(raw);
      final queryParams = uri?.queryParameters.isNotEmpty == true
          ? uri!.queryParameters
          : Uri.splitQueryString(raw.startsWith('?') ? raw.substring(1) : raw);
      token ??= queryParams['token']?.trim();
      employeeId ??= queryParams['employeeId']?.trim() ??
          queryParams['employee_id']?.trim() ??
          queryParams['employeeid']?.trim();
    }

    if (token == null && raw.length >= 16 && !raw.contains(' ')) {
      token = raw;
    }

    return _ParsedQrPayload(token: token, employeeId: employeeId);
  }

  Future<void> _onManualScanSubmit() async {
    final payload = _manualInputController.text.trim();
    if (payload.isEmpty) {
      setState(() => _errorText = 'Enter token or payload to continue.');
      return;
    }
    await _applyScannedPayload(payload);
  }

  String get _formattedDate =>
      DateFormat('EEE, MMM d, yyyy').format(_selectedDate);

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _submitAttendance() async {
    if (_token == null || _token!.isEmpty) {
      setState(
          () => _errorText = 'QR token is required before marking attendance.');
      return;
    }

    if (!_isSameDay(_selectedDate, DateTime.now())) {
      setState(() => _errorText = 'Attendance can only be recorded for today.');
      return;
    }

    if (_staff == null) await _loadCurrentStaffDetails();

    if (_staff == null || _employeeId == null) {
      setState(() => _errorText =
          'Signed-in profile details are missing. Cannot complete attendance.');
      return;
    }

    setState(() {
      _isWorking = true;
      _scanStatus = 'Checking location and recording attendance...';
      _errorText = null;
    });

    try {
      final locationAccess = await _geoFenceService.ensureLocationAccess();
      if (!locationAccess.granted) {
        setState(() {
          _scanStatus = null;
          _errorText = locationAccess.message;
        });
        return;
      }

      final currentPosition = await _geoFenceService.getCurrentPosition();
      if (currentPosition == null) {
        setState(() {
          _scanStatus = null;
          _errorText =
              'Unable to read your current location. Please wait a moment and try again.';
        });
        return;
      }

      final office = await _loadOfficeConfig(
        fallbackLat: currentPosition.latitude,
        fallbackLng: currentPosition.longitude,
      );

      final result = await _attendanceService.markAttendance(
        employeeId: _employeeId!,
        employeeName: _staff!.name,
        department: _staff!.department,
        qrToken: _token!,
        userLat: currentPosition.latitude,
        userLng: currentPosition.longitude,
        officeLat: office.latitude,
        officeLng: office.longitude,
        geoFenceRadiusMetres: office.radius,
        userAccuracyMetres: currentPosition.accuracy,
      );

      if (!result.success) {
        setState(() {
          _scanStatus = null;
          _errorText = result.message;
        });
        return;
      }

      setState(() {
        _lastResult = result;
        _scanStatus = 'Attendance recorded: ${result.statusLabel}';
        _errorText = null;
      });
    } catch (error) {
      setState(() {
        _scanStatus = null;
        _errorText = 'Attendance submission failed: ${error.toString()}';
      });
    } finally {
      setState(() => _isWorking = false);
    }
  }

  Future<_ScannerOfficeConfig> _loadOfficeConfig({
    required double fallbackLat,
    required double fallbackLng,
  }) async {
    final geoDoc = await FirebaseContextProvider.current.firestore
        .collection('geo_config')
        .doc('default')
        .get();
    final geoConfig = _officeConfigFromData(geoDoc.data());
    if (geoConfig != null) return geoConfig;

    final officeDoc = await FirebaseContextProvider.current.firestore
        .collection('offices')
        .doc('default')
        .get();
    final officeConfig = _officeConfigFromData(officeDoc.data());
    if (officeConfig != null) return officeConfig;

    return _ScannerOfficeConfig(
      latitude: fallbackLat,
      longitude: fallbackLng,
      radius: 50,
    );
  }

  _ScannerOfficeConfig? _officeConfigFromData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    return _ScannerOfficeConfig(
      latitude: lat,
      longitude: lng,
      radius: (data['radius'] as num?)?.toDouble() ??
          (data['geoFenceRadius'] as num?)?.toDouble() ??
          50,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QR Scanner',
          style: TextStyle(
              color: colors.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Scan the admin attendance QR code to mark attendance. The system validates the signed-in profile, location, and today’s date.',
          style:
              TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.6),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 1040;
            return Flex(
              direction: isNarrow ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildScannerPanel()),
                SizedBox(width: isNarrow ? 0 : 24, height: isNarrow ? 24 : 0),
                Expanded(flex: 2, child: _buildResultPanel()),
              ],
            );
          },
        ),
        if (_scanStatus != null || _errorText != null) ...[
          const SizedBox(height: 20),
          if (_scanStatus != null)
            Text(_scanStatus!,
                style: TextStyle(
                    color: colors.success, fontWeight: FontWeight.w600)),
          if (_errorText != null)
            Text(_errorText!,
                style: TextStyle(
                    color: colors.error, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'If the camera does not detect the QR automatically, paste the token below and submit manually.',
            style: TextStyle(
                color: colors.textSecondary, fontSize: 12, height: 1.5),
          ),
        ],
      ],
    );
  }

  Widget _buildScannerPanel() {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scan Area',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 420,
              width: double.infinity,
              child: MobileScanner(
                controller: _scannerController,
                onDetect: _onBarcodeDetected,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Position the QR code inside the frame for automatic detection.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: () {
                  _scannerController.toggleTorch();
                },
                child: const Text('Toggle Torch'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _manualInputController,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Paste QR token or payload manually',
              hintStyle: TextStyle(color: colors.textSecondary),
              filled: true,
              fillColor: colors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: Icon(Icons.send, color: colors.iconSecondary),
                onPressed: _onManualScanSubmit,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    final colors = AppColors.of(context);
    final hasStaff = _staff != null;
    final statusText = _lastResult?.statusLabel ?? 'Pending';
    final statusColor = _lastResult?.success == true
        ? (_lastResult?.status == 'present' ? colors.success : colors.warning)
        : colors.primary;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Scan Result',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          hasStaff
              ? Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: colors.primary,
                      child: Text(
                        _staff!.name
                            .split(' ')
                            .map((part) => part.isNotEmpty ? part[0] : '')
                            .take(2)
                            .join(),
                        style: TextStyle(
                            color: colors.onPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_staff!.name,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text('${_staff!.employeeId} • ${_staff!.department}',
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(_staff!.position,
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                )
              : Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                  decoration: BoxDecoration(
                    color: colors.tableHeader,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'No QR scan result yet. Scan the admin attendance QR code or paste the token to display the signed-in profile here.',
                    style: TextStyle(color: colors.textSecondary, height: 1.6),
                  ),
                ),
          const SizedBox(height: 22),
          _buildStatusRow(statusText, statusColor),
          const SizedBox(height: 16),
          _buildFeatureChip(
            label: 'Date',
            value: _formattedDate,
            color: colors.textSecondary,
          ),
          const SizedBox(height: 12),
          _buildFeatureChip(
            label: 'Validation',
            value: _lastResult?.success == true ? 'Valid' : 'Pending',
            color:
                _lastResult?.success == true ? colors.success : colors.warning,
          ),
          const SizedBox(height: 16),
          _buildDetailRow('Name', hasStaff ? _staff!.name : '—'),
          const SizedBox(height: 10),
          _buildDetailRow('Designation', hasStaff ? _staff!.department : '—'),
          const SizedBox(height: 10),
          _buildDetailRow('Position', hasStaff ? _staff!.position : '—'),
          const SizedBox(height: 10),
          _buildDetailRow('Employee ID', hasStaff ? _staff!.employeeId : '—'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isWorking || !hasStaff ? null : _submitAttendance,
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: Text(
              _lastResult == null ? 'Mark Attendance' : 'Mark Again',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if (_lastResult != null) ...[
            const SizedBox(height: 16),
            Text(
              _lastResult!.message,
              style: TextStyle(
                color: _lastResult!.success ? colors.textPrimary : colors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.tableHeader,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'Only today can be marked. Past or future dates are blocked and any late/absent scan sends an alert for manager review.',
              style: TextStyle(color: colors.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String statusText, Color statusColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            statusText,
            style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Text('$label:',
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(value,
                  style: TextStyle(color: AppColors.of(context).textPrimary))),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontSize: 13))),
          Text(value,
              style: TextStyle(
                  color: AppColors.of(context).textPrimary,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ParsedQrPayload {
  final String? token;
  final String? employeeId;

  _ParsedQrPayload({this.token, this.employeeId});
}

class _ScannerOfficeConfig {
  final double latitude;
  final double longitude;
  final double radius;

  const _ScannerOfficeConfig({
    required this.latitude,
    required this.longitude,
    required this.radius,
  });
}
