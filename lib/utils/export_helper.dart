import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/attendance_model.dart';

class ExportHelper {
  static const int _pdfRowsPerPage = 12;

  static Future<String?> saveBytes({
    required String name,
    required Uint8List bytes,
    required String ext,
    required MimeType mimeType,
  }) {
    if (kIsWeb) {
      return FileSaver.instance.saveFile(
        name: name,
        bytes: bytes,
        ext: ext,
        mimeType: mimeType,
      );
    }

    return FileSaver.instance.saveAs(
      name: name,
      bytes: bytes,
      ext: ext,
      mimeType: mimeType,
    );
  }

  static final List<String> _headers = [
    "Employee Name",
    "Employee ID",
    "Date",
    "Designation",
    "Status",
    "Check-In",
    "Check-Out",
    "Working Hours",
    "Pending Hours",
    "Absent/Present",
    "Latitude",
    "Longitude",
  ];

  static List<List<dynamic>> _generateDataRows(List<AttendanceModel> records) {
    final sorted = List<AttendanceModel>.from(records)
      ..sort((a, b) {
        final dateCompare =
            a.dateKey.compareTo(b.dateKey); // oldest first (1 to 30/31)
        if (dateCompare != 0) return dateCompare;

        final nameCompare = a.employeeName
            .trim()
            .toLowerCase()
            .compareTo(b.employeeName.trim().toLowerCase());
        if (nameCompare != 0) return nameCompare;

        return a.employeeId.trim().compareTo(b.employeeId.trim());
      });

    return sorted
        .map((record) => [
              record.employeeName,
              record.employeeId,
              record.dateFormatted,
              record.department,
              record.statusLabel,
              record.checkInFormatted,
              record.checkOutFormatted,
              record.workingHoursFormatted,
              record.pendingHoursFormatted,
              record.pendingAbsenceLabel,
              record.latitude ?? "",
              record.longitude ?? "",
            ])
        .toList();
  }

  static Future<void> exportToCsv(
      List<AttendanceModel> records, String fileName) async {
    List<List<dynamic>> rows = [_headers, ..._generateDataRows(records)];
    String csvData = const ListToCsvConverter().convert(rows);
    Uint8List bytes = Uint8List.fromList(utf8.encode(csvData));

    await saveBytes(
      name: fileName,
      bytes: bytes,
      ext: "csv",
      mimeType: MimeType.csv,
    );
  }

  static Future<void> exportToExcel(
      List<AttendanceModel> records, String fileName) async {
    var excel = excel_pkg.Excel.createExcel();

    // Rename default sheet to avoid the empty "Sheet1"
    String defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Attendance Logs');
    var sheet = excel['Attendance Logs'];

    // Add headers
    sheet.appendRow(_headers.map((h) => excel_pkg.TextCellValue(h)).toList());

    // Add data with separate space for days
    final dataRows = _generateDataRows(records);
    String? lastDate;

    for (var row in dataRows) {
      final currentDate = row[2].toString(); // Date is at index 2
      if (lastDate != null && lastDate != currentDate) {
        // Insert empty row
        sheet.appendRow(
            _headers.map((_) => excel_pkg.TextCellValue('')).toList());
      }
      sheet.appendRow(
          row.map((cell) => excel_pkg.TextCellValue(cell.toString())).toList());
      lastDate = currentDate;
    }

    var bytes = excel.encode();
    if (bytes != null) {
      await saveBytes(
        name: fileName,
        bytes: Uint8List.fromList(bytes),
        ext: "xlsx",
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  static Future<void> exportToPdf(
      List<AttendanceModel> records, String fileName) async {
    final pdf = await _createPdfDocument();
    final data = _generateDataRows(records);
    final chunks = _chunkRows(data, _pdfRowsPerPage);

    for (var i = 0; i < chunks.length; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (pw.Context context) {
            return _attendancePage(
              rows: chunks[i],
              title: i == 0 ? 'Attendance Logs' : null,
              recordRange:
                  'Records ${i * _pdfRowsPerPage + 1}-${i * _pdfRowsPerPage + chunks[i].length} of ${data.length}',
            );
          },
        ),
      );
    }

    final bytes = await pdf.save();
    await saveBytes(
      name: fileName,
      bytes: bytes,
      ext: "pdf",
      mimeType: MimeType.pdf,
    );
  }

  static Future<void> printLogs(List<AttendanceModel> records) async {
    final pdf = await _createPdfDocument();
    final data = _generateDataRows(records);
    final chunks = _chunkRows(data, _pdfRowsPerPage);

    for (var i = 0; i < chunks.length; i++) {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          build: (pw.Context context) {
            return _attendancePage(
              rows: chunks[i],
              title: i == 0 ? 'Attendance Logs' : null,
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save());
  }

  static Future<pw.Document> _createPdfDocument() async {
    final regular =
        pw.Font.ttf(await rootBundle.load('fonts/Poppins-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('fonts/Poppins-Bold.ttf'));

    return pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
      ),
    );
  }

  static pw.Widget _attendancePage({
    required List<List<dynamic>> rows,
    String? title,
    String? recordRange,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
        ],
        if (recordRange != null) ...[
          pw.Text(
            recordRange,
            style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
          ),
          pw.SizedBox(height: 8),
        ],
        pw.Expanded(child: _attendanceTable(rows)),
      ],
    );
  }

  static pw.Widget _attendanceTable(List<List<dynamic>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: _headers,
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 6),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.center,
        3: pw.Alignment.centerLeft,
        4: pw.Alignment.center,
        5: pw.Alignment.center,
        6: pw.Alignment.center,
        7: pw.Alignment.center,
        8: pw.Alignment.center,
        9: pw.Alignment.center,
        10: pw.Alignment.center,
        11: pw.Alignment.center,
      },
    );
  }

  static List<List<List<dynamic>>> _chunkRows(
    List<List<dynamic>> rows,
    int size,
  ) {
    if (rows.isEmpty) return const [[]];

    final chunks = <List<List<dynamic>>>[];
    for (var i = 0; i < rows.length; i += size) {
      final end = i + size > rows.length ? rows.length : i + size;
      chunks.add(rows.sublist(i, end));
    }
    return chunks;
  }
}
