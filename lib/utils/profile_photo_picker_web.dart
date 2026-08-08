// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';

const int _maxDataUrlLength = 512 * 1024;

Future<String?> pickProfilePhotoDataUrl() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  final blob = html.Blob([bytes], picked.mimeType ?? 'image/jpeg');
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);

  try {
    final image = html.ImageElement(src: objectUrl);
    await image.onLoad.first.timeout(const Duration(seconds: 10));

    for (final maxSide in const [320, 280, 240, 200, 160, 128]) {
      final canvas = _drawToCanvas(image, maxSide);
      for (final quality in const [0.82, 0.7, 0.58, 0.46, 0.36, 0.28]) {
        final dataUrl = canvas.toDataUrl('image/jpeg', quality);
        if (dataUrl.length <= _maxDataUrlLength) {
          return dataUrl;
        }
      }
    }
  } finally {
    html.Url.revokeObjectUrl(objectUrl);
  }

  throw Exception('Please choose a smaller photo.');
}

html.CanvasElement _drawToCanvas(html.ImageElement image, int maxSide) {
  final sourceWidth = image.naturalWidth;
  final sourceHeight = image.naturalHeight;
  final longestSide = math.max(sourceWidth, sourceHeight);
  final scale = longestSide > 0 ? math.min(1, maxSide / longestSide) : 1;
  final width = math.max(1, (sourceWidth * scale).round());
  final height = math.max(1, (sourceHeight * scale).round());

  final canvas = html.CanvasElement(width: width, height: height);
  canvas.context2D.drawImageScaled(image, 0, 0, width, height);
  return canvas;
}
