import 'dart:convert';

import 'package:image_picker/image_picker.dart';

Future<String?> pickProfilePhotoDataUrl() async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 45,
  );
  if (picked == null) return null;

  final bytes = await picked.readAsBytes();
  if (bytes.length > 512 * 1024) {
    throw Exception('Please choose a smaller photo (under 512KB).');
  }

  final contentType = picked.mimeType?.startsWith('image/') == true
      ? picked.mimeType!
      : 'image/jpeg';
  return 'data:$contentType;base64,${base64Encode(bytes)}';
}
