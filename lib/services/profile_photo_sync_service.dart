import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firebase_context_provider.dart';

class ProfilePhotoSyncService {
  static Future<void> updateAttendancePhoto({
    required String photoUrl,
    required Iterable<String> employeeIds,
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseContextProvider.current.firestore;
    final ids =
        employeeIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();
    if (ids.isEmpty) return;

    var batch = db.batch();
    var writes = 0;

    Future<void> commitIfNeeded({bool force = false}) async {
      if (writes == 0 || (!force && writes < 450)) return;
      await batch.commit();
      batch = db.batch();
      writes = 0;
    }

    for (final employeeId in ids) {
      final attendance = await db
          .collection('attendance')
          .where('employeeId', isEqualTo: employeeId)
          .get();
      for (final doc in attendance.docs) {
        batch.update(doc.reference, {'employeePhotoUrl': photoUrl});
        writes++;
        await commitIfNeeded();
      }
    }

    await commitIfNeeded(force: true);
  }
}
