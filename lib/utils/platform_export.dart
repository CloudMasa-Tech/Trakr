import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Generic, column-based export helpers (CSV / XLSX / PDF) used by the Super
/// Admin Reports, Billing, and Audit Logs modules. Unlike [ExportHelper], these
/// are not tied to [AttendanceModel] and accept arbitrary string rows.
class PlatformExport {
  static const int _pdfRowsPerPage = 18;

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

  static String _safe(dynamic value) {
    if (value == null) return '';
    if (value is DateTime) return DateFormat('dd MMM yyyy').format(value);
    final s = value.toString();
    return s;
  }

  static List<List<String>> _rows(
      List<String> headers, List<List<dynamic>> data) {
    return [
      headers,
      ...data.map((row) => row.map(_safe).toList()),
    ];
  }

  static Future<void> toCsv({
    required String name,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final data = _rows(headers, rows);
    final csv = const ListToCsvConverter().convert(data);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    await saveBytes(
      name: name,
      bytes: bytes,
      ext: 'csv',
      mimeType: MimeType.csv,
    );
  }

  static Future<void> toExcel({
    required String name,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final excel = excel_pkg.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Report');
    final sheet = excel['Report'];
    sheet.appendRow(headers.map((h) => excel_pkg.TextCellValue(h)).toList());
    for (final row in rows) {
      sheet.appendRow(
        row.map((cell) => excel_pkg.TextCellValue(_safe(cell))).toList(),
      );
    }
    final bytes = excel.encode();
    if (bytes != null) {
      await saveBytes(
        name: name,
        bytes: Uint8List.fromList(bytes),
        ext: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
    }
  }

  static Future<void> toPdf({
    required String name,
    required String title,
    required List<String> headers,
    required List<List<dynamic>> rows,
  }) async {
    final regular = pw.Font.ttf(
      await rootBundle.load('fonts/Poppins-Regular.ttf'),
    );
    final bold = pw.Font.ttf(await rootBundle.load('fonts/Poppins-Bold.ttf'));
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final data = rows.map((row) => row.map(_safe).toList()).toList();
    final chunks = _chunkRows(data, _pdfRowsPerPage);

    for (var i = 0; i < chunks.length; i++) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  i == 0 ? title : '',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                if (i > 0 || rows.isEmpty)
                  pw.SizedBox(height: 8)
                else
                  pw.SizedBox(height: 8),
                pw.Text(
                  '${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'
                  ' • Records ${i * _pdfRowsPerPage + 1}-${i * _pdfRowsPerPage + chunks[i].length} of ${rows.length}',
                  style:
                      const pw.TextStyle(color: PdfColors.grey700, fontSize: 9),
                ),
                pw.SizedBox(height: 10),
                pw.Expanded(
                  child: pw.TableHelper.fromTextArray(
                    headers: headers,
                    data: chunks[i],
                    headerStyle: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 8,
                    ),
                    headerDecoration: const pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                    cellStyle: const pw.TextStyle(fontSize: 7),
                    cellPadding: const pw.EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 3,
                    ),
                    cellAlignments: {
                      for (var c = 0; c < headers.length; c++)
                        c: pw.Alignment.centerLeft,
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
    final bytes = await doc.save();
    await saveBytes(
      name: name,
      bytes: bytes,
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  static List<List<List<String>>> _chunkRows(
    List<List<String>> rows,
    int size,
  ) {
    if (rows.isEmpty) return const [[]];
    final chunks = <List<List<String>>>[];
    for (var i = 0; i < rows.length; i += size) {
      final end = i + size > rows.length ? rows.length : i + size;
      chunks.add(rows.sublist(i, end));
    }
    return chunks;
  }
}
