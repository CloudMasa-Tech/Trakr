import 'dart:typed_data';

/// A logo file picked by the user (from the file picker or drag & drop),
/// held in memory until it is stored as a data URL in the tenant's Firestore
/// company record (no Cloud Storage is used).
class PickedLogoFile {
  final Uint8List bytes;
  final String name;
  final String mimeType;

  const PickedLogoFile({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  /// Lowercased file extension without the leading dot, e.g. `png`, `svg`.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get isSvg =>
      mimeType.contains('svg') ||
      mimeType == 'image/svg+xml' ||
      extension == 'svg';

  bool get isRaster =>
      extension == 'png' || extension == 'jpg' || extension == 'jpeg';

  int get sizeInBytes => bytes.length;

  static const Set<String> allowedExtensions = {'png', 'jpg', 'jpeg', 'svg'};

  static const int maxSizeBytes = 700 * 1024;

  /// Resolves the content type used for the stored data URL.
  String storageContentType() {
    if (isSvg) return 'image/svg+xml';
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      default:
        return mimeType.startsWith('image/') ? mimeType : 'image/png';
    }
  }
}
