import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BootstrapService {
  BootstrapService._();
  static final BootstrapService instance = BootstrapService._();

  static const String _superAdminEmail = 'keerthana.s@cloudmasa.com';
  static const String _superAdminPassword = 'Superadmin@123';
  static const String _isBootstrappedKey = 'app_is_bootstrapped_v1';

  /// Bootstraps the master super admin on first run if the Firebase Auth is empty.
  /// Uses a secondary FirebaseApp to ensure we don't accidentally log the
  /// super admin into the main app state when creating the user.
  Future<void> bootstrapMasterAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_isBootstrappedKey) == true) {
        return; // Already bootstrapped locally, safe to skip.
      }

      // Initialize a temporary secondary Firebase App to probe and create the user
      // without affecting the main Firebase Auth state (e.g., logging them in).
      FirebaseApp? tempApp;
      try {
        tempApp = Firebase.app('bootstrapApp');
      } catch (e) {
        tempApp = await Firebase.initializeApp(
          name: 'bootstrapApp',
          options: Firebase.app().options,
        );
      }

      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final tempFirestore = FirebaseFirestore.instanceFor(app: tempApp);

      UserCredential? credential;

      try {
        // Try to create the user
        credential = await tempAuth.createUserWithEmailAndPassword(
          email: _superAdminEmail,
          password: _superAdminPassword,
        );
        debugPrint('[BootstrapService] Created new Master Super Admin user.');
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          // The user exists in Auth. Let's try to sign in to get their UID
          // so we can verify their Firestore document.
          try {
            credential = await tempAuth.signInWithEmailAndPassword(
              email: _superAdminEmail,
              password: _superAdminPassword,
            );
            debugPrint('[BootstrapService] Master Super Admin user already exists in Auth.');
          } catch (signInErr) {
            // They might have changed their password. We should gracefully recover
            // and assume it's bootstrapped enough.
            debugPrint('[BootstrapService] Master Super Admin exists but failed to sign in: $signInErr');
            await prefs.setBool(_isBootstrappedKey, true);
            return;
          }
        } else {
          // Some other Auth exception (e.g. network), fail gracefully.
          debugPrint('[BootstrapService] Error creating Master Super Admin: $e');
          return;
        }
      }

      // If we got here, we have a logged-in user in the temporary app.
      final uid = credential?.user?.uid;
      if (uid != null) {
        final docRef = tempFirestore.collection('users').doc(uid);
        final docSnap = await docRef.get();

        if (!docSnap.exists) {
          await docRef.set({
            'email': _superAdminEmail,
            'role': 'super_admin',
            'isActive': true,
            'name': 'Master Super Admin',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          debugPrint('[BootstrapService] Created missing Firestore document for Master Super Admin.');
        } else {
          debugPrint('[BootstrapService] Firestore document for Master Super Admin already exists.');
        }
      }

      // Mark locally as bootstrapped.
      await prefs.setBool(_isBootstrappedKey, true);

      // Sign out from temp app to clear its state.
      await tempAuth.signOut();

    } catch (e, st) {
      debugPrint('[BootstrapService] Bootstrap failed with exception: $e\n$st');
    }
  }
}
