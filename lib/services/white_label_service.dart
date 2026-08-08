// lib/services/white_label_service.dart

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/white_label_model.dart';
import 'company_logo_service.dart';

class WhiteLabelService {
  WhiteLabelService({FirebaseContext? context})
      : _context = context ?? FirebaseContextProvider.current;

  final FirebaseContext _context;

  FirebaseFirestore get _firestore => _context.firestore;

  // Collection path: /settings/white_label
  static const String _docPath = 'settings';
  static const String _docId = 'white_label';

  /// Stream the white label config in real-time
  Stream<WhiteLabelModel> streamConfig() {
    return _firestore.collection(_docPath).doc(_docId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return const WhiteLabelModel(
          companyName: 'QR Attendances',
          primaryColorHex: '0F766E',
          customDomain: '',
          supportEmail: '',
        );
      }
      return WhiteLabelModel.fromMap(snap.data()!);
    });
  }

  /// Save white label config to Firestore
  Future<void> saveConfig(WhiteLabelModel model) async {
    await _firestore
        .collection(_docPath)
        .doc(_docId)
        .set(model.toMap(), SetOptions(merge: true));
  }

  /// Returns a base64 `data:` URL for the logo bytes. The value is persisted by
  /// the caller through [saveConfig] (the `logoUrl` field), so no Cloud Storage
  /// is involved — everything stays on Firestore (Spark plan).
  Future<String> uploadLogo(
    Uint8List bytes, {
    String contentType = 'image/png',
  }) async {
    if (bytes.length > CompanyLogoService.maxStoredBytes) {
      throw Exception(
        'Logo is too large to store. Please choose a smaller image '
        '(under 700 KB).',
      );
    }
    return CompanyLogoService.dataUrlFor(bytes, contentType: contentType);
  }
}
