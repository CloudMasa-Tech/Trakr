import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../firebase/firebase_context.dart';
import '../firebase/firebase_manager.dart';

/// Anchors the **Master Firebase** (control plane) project.
///
/// The control plane lives on the DEFAULT Firebase project — the one
/// bootstrapped in `main()` — and is intentionally separate from tenant
/// (data plane) projects, which are managed by [FirebaseManager]. Every
/// platform-level collection (`workspaces`, `plans`, `subscriptions`,
/// billing, settings) is read and written through this single source of
/// truth so it can never accidentally resolve to an active tenant project.
class ControlPlaneFirebase {
  ControlPlaneFirebase._();

  /// The shared [ControlPlaneFirebase] instance.
  static final ControlPlaneFirebase instance = ControlPlaneFirebase._();

  FirebaseContext? _context;

  /// The master Firebase context, always bound to the default project.
  FirebaseContext get context => _context ??= FirebaseContext();

  /// Firestore on the master (control plane) project.
  FirebaseFirestore get firestore => context.firestore;

  /// Auth on the master (control plane) project.
  FirebaseAuth get auth => context.auth;

  /// Ensures the master Firebase app is initialized (idempotent).
  ///
  /// Delegates to [FirebaseManager.ensureDefaultApp] so the control plane and
  /// the rest of the app share the same default-project bootstrap.
  Future<FirebaseContext> ensureInitialized({FirebaseOptions? options}) async {
    await FirebaseManager.instance.ensureDefaultApp(options: options);
    return context;
  }
}
