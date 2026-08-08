import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../services/attendance_service.dart';
import '../../theme/app_theme_colors.dart';

/// QR codes must always render on a light background for scannability, so the
/// QR surface/module colors are fixed constants rather than theme tokens.
const _qrSurface = Color(0xFFFFFFFF);
const _qrModule = Color(0xFF000000);
const _qrMutedOnSurface = Color(0x8A000000);

class LiveQrWidget extends StatefulWidget {
  const LiveQrWidget({super.key});

  @override
  State<LiveQrWidget> createState() => _LiveQrWidgetState();
}

class _LiveQrWidgetState extends State<LiveQrWidget> {
  static const Duration _tokenLifetime = Duration(days: 90);
  static const Duration _tokenHealthCheckInterval = Duration(hours: 1);

  final _svc = AttendanceService();
  bool _loading = false;
  bool _downloading = false;
  bool _refreshingToken = false;
  String? _qrError;
  Timer? _tokenHealthCheckTimer;

  String? get _tenant => FirebaseContextProvider.current.auth.currentUser?.uid;

  String _qrPayload(String token) => token;

  Stream<int> get _liveGeoFenceRadiusStream {
    return FirebaseContextProvider.current.firestore
        .collection('geo_config')
        .doc('default')
        .snapshots()
        .asyncMap((snap) async {
      final data = snap.data() ?? const <String, dynamic>{};
      final radius =
          (data['radius'] as num?) ?? (data['geoFenceRadius'] as num?);
      if (radius != null) return radius.round();

      final officeDoc = await FirebaseContextProvider.current.firestore
          .collection('offices')
          .doc('default')
          .get();
      final officeData = officeDoc.data() ?? const <String, dynamic>{};
      return ((officeData['radius'] as num?) ??
              (officeData['geoFenceRadius'] as num?) ??
              50)
          .round();
    });
  }

  bool _isExpired(DateTime? expiresAt) {
    return expiresAt == null || !expiresAt.isAfter(DateTime.now());
  }

  void _setLoading(bool value) {
    if (!mounted) return;
    setState(() => _loading = value);
  }

  Future<void> _ensureCurrentQrToken({bool showLoading = false}) async {
    final tenant = _tenant;
    if (_refreshingToken || tenant == null || tenant.isEmpty) return;
    _refreshingToken = true;
    if (showLoading) _setLoading(true);
    try {
      final doc = await FirebaseContextProvider.current.firestore
          .collection('qr_tokens')
          .doc(tenant)
          .get();
      final data = doc.data();
      final token = data?['token'] as String?;
      final expiresAt = (data?['expiresAt'] as Timestamp?)?.toDate();
      if (token == null || token.isEmpty || _isExpired(expiresAt)) {
        await _svc.generateQrToken(
          tenant,
          validFor: _tokenLifetime,
          refreshSource: 'auto',
        );
      }
      if (!mounted) return;
      if (_qrError != null) {
        setState(() => _qrError = null);
      }
    } catch (e, stackTrace) {
      debugPrint('QR token health check failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || !showLoading) return;
      setState(() => _qrError = _friendlyQrError(e));
    } finally {
      _refreshingToken = false;
      if (showLoading) _setLoading(false);
    }
  }

  Future<void> _refreshQr() async {
    final tenant = _tenant;
    if (_refreshingToken || !mounted) return;
    if (tenant == null || tenant.isEmpty) {
      setState(() => _qrError = 'Please sign in again before refreshing QR.');
      return;
    }
    _refreshingToken = true;
    _setLoading(true);
    try {
      await _svc.generateQrToken(
        tenant,
        validFor: _tokenLifetime,
        refreshSource: 'manual',
      );
      if (!mounted) return;
      setState(() => _qrError = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('QR code refreshed.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('Manual QR refresh failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      final message = _friendlyQrError(e);
      setState(() => _qrError = message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.of(context).error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      _refreshingToken = false;
      _setLoading(false);
    }
  }

  String _friendlyQrError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'Unable to refresh QR code. Please try again.';
    }
    return message;
  }

  Future<void> _downloadQr(String token) async {
    if (token.isEmpty || _downloading || !mounted) return;

    setState(() => _downloading = true);
    try {
      final painter = QrPainter(
        data: _qrPayload(token),
        version: QrVersions.auto,
        gapless: true,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: _qrModule,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: _qrModule,
        ),
      );
      final qrImageData = await painter.toImageData(
        1024,
        format: ui.ImageByteFormat.png,
      );
      if (qrImageData == null) {
        throw Exception('Unable to generate QR image.');
      }
      final codec = await ui.instantiateImageCodec(
        qrImageData.buffer.asUint8List(
          qrImageData.offsetInBytes,
          qrImageData.lengthInBytes,
        ),
      );
      final frame = await codec.getNextFrame();
      final qrImage = frame.image;
      const quietZone = 128.0;
      const outputSize = 1280.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = _qrSurface;
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, outputSize, outputSize),
        paint,
      );
      canvas.drawImageRect(
        qrImage,
        Rect.fromLTWH(
          0,
          0,
          qrImage.width.toDouble(),
          qrImage.height.toDouble(),
        ),
        const Rect.fromLTWH(
          quietZone,
          quietZone,
          outputSize - (quietZone * 2),
          outputSize - (quietZone * 2),
        ),
        Paint(),
      );
      final image = await recorder
          .endRecording()
          .toImage(outputSize.toInt(), outputSize.toInt());
      final imageData = await image.toByteData(format: ui.ImageByteFormat.png);
      qrImage.dispose();
      image.dispose();
      if (imageData == null) {
        throw Exception('Unable to export QR image.');
      }
      final qrPngBytes = imageData.buffer.asUint8List(
        imageData.offsetInBytes,
        imageData.lengthInBytes,
      );

      final now = DateTime.now();
      final dateSlug =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final pdf = pw.Document();
      final qrPdfImage = pw.MemoryImage(qrPngBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(48),
          build: (context) => pw.Center(
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Text(
                  'Attendance QR Code',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 24),
                pw.Container(
                  width: 320,
                  height: 320,
                  child: pw.Image(qrPdfImage),
                ),
                pw.SizedBox(height: 18),
                pw.Text(
                  'Generated on $dateSlug',
                  style: const pw.TextStyle(
                    fontSize: 12,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await FileSaver.instance.saveFile(
        name: 'attendance_qr_$dateSlug',
        bytes: await pdf.save(),
        ext: 'pdf',
        mimeType: MimeType.pdf,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('QR code PDF downloaded.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.of(context).error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_ensureCurrentQrToken(showLoading: true));
    _tokenHealthCheckTimer = Timer.periodic(
      _tokenHealthCheckInterval,
      (_) => unawaited(_ensureCurrentQrToken()),
    );
  }

  @override
  void dispose() {
    _tokenHealthCheckTimer?.cancel();
    super.dispose();
  }

  Widget _buildSignedOutQrCard() {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance QR Code',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Container(
              width: 180,
              height: 180,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _qrSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'Sign in required to generate QR',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _qrMutedOnSurface,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              'Please sign in again before refreshing QR.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.error,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final tenant = _tenant;
    if (tenant == null || tenant.isEmpty) {
      return _buildSignedOutQrCard();
    }

    return StreamBuilder<int>(
      stream: _liveGeoFenceRadiusStream,
      initialData: 50,
      builder: (context, radiusSnapshot) {
        final radius = radiusSnapshot.data ?? 50;

        return StreamBuilder<Map<String, dynamic>>(
          stream: _svc.getQrTokenStream(tenant),
          builder: (context, snapshot) {
            final tokenData = snapshot.data ?? {};
            final token = tokenData['token'] as String? ?? '';
            final expiresAt = (tokenData['expiresAt'] as Timestamp?)?.toDate();
            final hasToken = token.isNotEmpty;
            final streamError =
                snapshot.hasError ? _friendlyQrError(snapshot.error!) : null;
            final visibleError = streamError ?? _qrError;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Attendance QR Code',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.35,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: colors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: colors.success.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: colors.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '3-month token',
                              style: TextStyle(
                                color: colors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _qrSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _loading && !hasToken
                          ? SizedBox(
                              width: 160,
                              height: 160,
                              child: Center(
                                child: CircularProgressIndicator(
                                    color: colors.primary),
                              ),
                            )
                          : hasToken
                              ? QrImageView(
                                  data: _qrPayload(token),
                                  version: QrVersions.auto,
                                  size: 160,
                                  backgroundColor: _qrSurface,
                                  gapless: true,
                                )
                              : const SizedBox(
                                  width: 160,
                                  height: 160,
                                  child: Center(
                                    child: Text(
                                      'No QR token available',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _qrMutedOnSurface,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (expiresAt != null)
                    Center(
                      child: Text(
                        'Valid until ${expiresAt.toLocal().toIso8601String().split('T').first}',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (visibleError != null) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        visibleError,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.error,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          'Valid for 3 months. Admin can refresh anytime.',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Geo-fence: ${radius}m radius',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: hasToken && !_downloading
                          ? () => _downloadQr(token)
                          : null,
                      icon: _downloading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label:
                          Text(_downloading ? 'Downloading...' : 'Download QR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.primary,
                        side: BorderSide(
                            color: colors.primary.withValues(alpha: 0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _refreshQr,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: Text(
                        _loading ? 'Refreshing...' : 'Refresh QR Now',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
