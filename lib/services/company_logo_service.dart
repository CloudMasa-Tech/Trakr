// lib/services/company_logo_service.dart

import 'dart:convert';
import 'dart:typed_data';

/// Owns the company logo, stored as a base64 data URL inside the company
/// Firestore document (the Spark plan supports only Auth + Firestore, so no
/// Cloud Storage is used anywhere in the project).
///
/// The company document stores the resulting data URL in both `companyLogoUrl`
/// (newer convention) and `logoUrl` (legacy convention used by
/// `CoCompanyAvatar` and other company-branded surfaces). The service is
/// stateless — callers persist the returned URL themselves.
class CompanyLogoService {
  /// Largest logo payload (raw bytes) that can be stored in a Firestore
  /// document as a base64 data URL while staying comfortably under the 1 MB
  /// document limit (base64 inflates the payload by ~33%).
  static const int maxStoredBytes = 700 * 1024;

  /// Encodes [bytes] as a `data:` URL that image widgets can render directly.
  static String dataUrlFor(Uint8List bytes, {required String contentType}) {
    final safeType = contentType.trim().isNotEmpty ? contentType : 'image/png';
    return 'data:$safeType;base64,${base64Encode(bytes)}';
  }

  static void _validateSize(Uint8List bytes) {
    if (bytes.length > maxStoredBytes) {
      throw Exception(
        'Logo is too large to store. Please choose a smaller image '
        '(under 700 KB).',
      );
    }
  }

  /// Returns the `data:` URL for [bytes] so the caller can persist it in the
  /// company document (via `logoUrl`/`companyLogoUrl`).
  static Future<String> uploadLogo(
    Uint8List bytes, {
    required String companyId,
    required String contentType,
  }) async {
    _validateSize(bytes);
    return dataUrlFor(bytes, contentType: contentType);
  }

  /// Same as [uploadLogo] with a progress callback that is kept for call-site
  /// compatibility. Storing in Firestore is atomic, so progress jumps straight
  /// to `1.0`.
  static Future<String> uploadLogoWithProgress(
    Uint8List bytes, {
    required String companyId,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    _validateSize(bytes);
    onProgress?.call(1.0);
    return dataUrlFor(bytes, contentType: contentType);
  }
}
