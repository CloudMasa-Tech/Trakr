import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/attendance_model.dart';
import '../models/leave_request.dart';
import '../models/permission_request.dart';
import '../models/staff.dart';

class PayrollService {
  PayrollService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _db => _context.firestore;
  static const double baseSalary = 12000.0;
  static const int standardWorkingDays = 26;

  /// Cached data to avoid redundant fetches
  Map<String, Map<String, dynamic>>? _monthlyCache;
  DateTime? _cachedMonth;
  bool _isRefreshing = false;

  Future<Map<String, dynamic>> calculateMonthlyPayroll(
      String staffId, int month, int year) async {
    // If we have cached results for this month, return from cache

    if (_monthlyCache != null &&
        _cachedMonth?.month == month &&
        _cachedMonth?.year == year) {
      return _monthlyCache![staffId] ?? _emptyPayroll(staffId);
    }

    // Otherwise, trigger a full month refresh
    await _refreshMonthlyData(month, year);
    return _monthlyCache![staffId] ?? _emptyPayroll(staffId);
  }

  Future<void> _refreshMonthlyData(int month, int year) async {
    if (_isRefreshing) {
      while (_isRefreshing) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return;
    }

    try {
      _isRefreshing = true;
      final startOfMonth = DateTime(year, month, 1);
      final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);

      _monthlyCache = {};
      _cachedMonth = DateTime(year, month);

      // 1. Fetch All Staff
      final staffSnap = await _db.collection('staff').get();
      final allStaff =
          staffSnap.docs.map((d) => Staff.fromFirestore(d)).toList();

      // 2. Fetch All Attendance for the month (Using simple range query)
      final attendanceSnap = await _db
          .collection('attendance')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();

      // 3. Fetch Approved Leaves (In-memory filtering handles date range below)
      final leaveSnap = await _db
          .collection('leave_requests')
          .where('status', isEqualTo: 'approved')
          .get();

      // 4. Fetch Approved Permissions (In-memory filtering handles date range below)
      final permissionSnap = await _db
          .collection('permission_requests')
          .where('status', isEqualTo: 'approved')
          .get();

      // Grouping logic
      for (final staff in allStaff) {
        final staffId = staff.employeeId;

        final staffAttendance = attendanceSnap.docs
            .map((d) => AttendanceModel.fromFirestore(d))
            .where((a) => a.employeeId == staffId)
            .toList();

        final staffLeaves = leaveSnap.docs
            .map((d) => LeaveRequest.fromFirestore(d.data(), d.id))
            .where((l) =>
                l.employeeId == staffId &&
                l.unpaidDayCount > 0 &&
                l.startDate.isBefore(endOfMonth) &&
                l.endDate.isAfter(startOfMonth))
            .toList();

        final staffPermissions = permissionSnap.docs
            .map((d) => PermissionRequest.fromFirestore(d))
            .where((p) =>
                p.employeeId == staffId &&
                !p.isPaid &&
                p.requestedAt.isAfter(startOfMonth) &&
                p.requestedAt.isBefore(endOfMonth))
            .toList();

        // Calculations
        int daysPresent = 0;
        int daysAbsent = 0;
        int daysLate = 0;
        int unauthorizedExits = 0;
        double totalWorkingHours = 0.0;

        for (final record in staffAttendance) {
          if (record.status == AttendanceStatus.present ||
              record.status == AttendanceStatus.late) {
            daysPresent++;
            if (record.status == AttendanceStatus.late) daysLate++;
          } else if (record.status == AttendanceStatus.absent) {
            daysAbsent++;
          }
          if (record.currentState == AttendanceState.unauthorizedExit) {
            unauthorizedExits++;
          }

          if (record.storedWorkingHours != null) {
            final parts = record.storedWorkingHours!.split(':');
            if (parts.length == 2) {
              totalWorkingHours +=
                  int.parse(parts[0]) + (int.parse(parts[1]) / 60.0);
            }
          }
        }

        double dailyRate = baseSalary / standardWorkingDays;
        double hourlyRate = dailyRate / 8.0;
        final unpaidLeaveDays = staffLeaves.fold<double>(
            0, (total, leave) => total + leave.unpaidDayCount);
        double leaveDeduction = unpaidLeaveDays * dailyRate;

        double totalPermissionHours = 0.0;
        for (final p in staffPermissions) {
          if (p.exitTime != null && p.returnTime != null) {
            final duration = p.returnTime!.difference(p.exitTime!);
            totalPermissionHours += duration.inMinutes / 60.0;
          }
        }
        double permissionDeduction = totalPermissionHours * hourlyRate;
        double lateDeduction = daysLate * 50.0;
        double unauthorizedExitPenalty = unauthorizedExits * 200.0;
        double totalDeductions = leaveDeduction +
            permissionDeduction +
            lateDeduction +
            unauthorizedExitPenalty;
        double netSalary = baseSalary - totalDeductions;

        _monthlyCache![staffId] = {
          'baseSalary': baseSalary,
          'daysPresent': daysPresent,
          'daysAbsent': daysAbsent,
          'daysLate': daysLate,
          'unauthorizedExits': unauthorizedExits,
          'totalWorkingHours': totalWorkingHours,
          'permissionHours': totalPermissionHours,
          'unpaidLeaveDays': unpaidLeaveDays,
          'leaveDeduction': leaveDeduction,
          'permissionDeduction': permissionDeduction,
          'lateDeduction': lateDeduction,
          'unauthorizedExitPenalty': unauthorizedExitPenalty,
          'totalDeductions': totalDeductions,
          'netSalary': netSalary < 0 ? 0.0 : netSalary,
        };
      }
    } catch (e) {
      debugPrint('Error refreshing payroll data: $e');
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }

  Map<String, dynamic> _emptyPayroll(String staffId) {
    return {
      'baseSalary': baseSalary,
      'daysPresent': 0,
      'daysAbsent': 0,
      'daysLate': 0,
      'unauthorizedExits': 0,
      'totalWorkingHours': 0.0,
      'permissionHours': 0.0,
      'unpaidLeaveDays': 0,
      'leaveDeduction': 0.0,
      'permissionDeduction': 0.0,
      'lateDeduction': 0.0,
      'unauthorizedExitPenalty': 0.0,
      'totalDeductions': 0.0,
      'netSalary': baseSalary,
    };
  }

  Future<Map<String, dynamic>> getPayrollSummary(int month, int year) async {
    if (_monthlyCache == null ||
        _cachedMonth?.month != month ||
        _cachedMonth?.year != year) {
      await _refreshMonthlyData(month, year);
    }

    double totalPayroll = 0.0;
    double totalDeductions = 0.0;
    int processedCount = 0;

    _monthlyCache?.forEach((id, payroll) {
      totalPayroll += (payroll['baseSalary'] as num).toDouble();
      totalDeductions += (payroll['totalDeductions'] as num).toDouble();
      processedCount++;
    });

    return {
      'totalEmployees': _monthlyCache?.length ?? 0,
      'totalPayroll': totalPayroll,
      'totalDeductions': totalDeductions,
      'netPayroll': totalPayroll - totalDeductions,
      'processedCount': processedCount,
    };
  }
}
