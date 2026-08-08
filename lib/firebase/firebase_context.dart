import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Encapsulates all Firebase services (app, auth, firestore, messaging) bound
/// to a single Firebase project.
///
/// During Phase 1 the context is always created against the default Firebase
/// project so the app behaves exactly as before. A named [FirebaseApp] (and the
/// instances derived from it) can be supplied in a later phase to support
/// per-workspace Firebase projects without changing any consumer code.
///
/// Note: Cloud Storage is intentionally NOT part of the context — the project
/// runs on the Firebase Spark plan and uses only Auth + Firestore.
class FirebaseContext {
  /// Creates a context bound to the default Firebase project unless specific
  /// instances (e.g. derived from a named [FirebaseApp]) are supplied.
  ///
  /// Every service is derived from the resolved [FirebaseApp] through
  /// `FirebaseX.instanceFor(app:)`, so the raw `FirebaseX.instance` globals are
  /// never referenced directly (except messaging, which cannot be per-app).
  FirebaseContext({
    FirebaseApp? app,
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  }) : this._(
          app ?? Firebase.app(),
          auth: auth,
          firestore: firestore,
          messaging: messaging,
        );

  FirebaseContext._(
    FirebaseApp resolvedApp, {
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseMessaging? messaging,
  })  : app = resolvedApp,
        auth = auth ?? FirebaseAuth.instanceFor(app: resolvedApp),
        firestore =
            firestore ?? FirebaseFirestore.instanceFor(app: resolvedApp),
        messaging = messaging ?? FirebaseMessaging.instance;

  /// The [FirebaseApp] this context is bound to.
  final FirebaseApp app;

  /// The [FirebaseAuth] instance bound to [app].
  final FirebaseAuth auth;

  /// The [FirebaseFirestore] instance bound to [app].
  final FirebaseFirestore firestore;

  /// The [FirebaseMessaging] instance bound to [app].
  final FirebaseMessaging messaging;

  /// Creates a context bound to [app], deriving every service instance from
  /// that specific Firebase project via `FirebaseX.instanceFor(app: app)`.
  ///
  /// Used by [FirebaseManager] to build a context for a named tenant app so all
  /// services resolve to the tenant's project instead of the default one.
  ///
  /// Note: firebase_messaging 15.x only supports the default Firebase app (its
  /// `instanceFor` is private), so the messaging instance is always the
  /// default project's. All other services are per-app.
  factory FirebaseContext.fromApp(FirebaseApp app) {
    return FirebaseContext(app: app);
  }
}
