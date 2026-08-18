import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Single source of truth for the platform Super Admin identity.
///
/// The email is resolved in priority order:
///   1. `app_config/admin_access.primaryAdminEmail` on the Master control-plane
///      project — set by the server-side setup tooling
///      (`functions/make_superadmin.js`). Authoritative.
///   2. A `SUPERADMIN_EMAIL` dart-define supplied at build time — fallback so
///      the app still knows its Super Admin before the config doc exists.
///
/// The password is intentionally NOT represented here: it is only set/rotated
/// server-side (setup script / Firebase console) and never shipped inside the
/// Flutter app or any client bundle.
///
/// NOTE: this config only drives *routing* (which Firebase project the Super
/// Admin signs into) and the Super Admin console rules. Authorization NEVER
/// depends on it: the canonical flow is `users/{uid}.role == super_admin` on
/// the authenticated account, enforced in `AuthSessionProvider`.
class SuperAdminConfig {
  SuperAdminConfig._();

  static const String _envEmail = String.fromEnvironment('SUPERADMIN_EMAIL');

  static String? _email;
  static bool _loadStarted = false;

  /// The configured Super Admin email, or `null` while unknown.
  static String? get email => _email;

  /// Whether a Super Admin identity has been configured.
  static bool get isConfigured => _email != null && _email!.trim().isNotEmpty;

  /// Whether [value] is the configured Super Admin email.
  static bool matches(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    return normalized.isNotEmpty && normalized == _email;
  }

  /// Loads (once) the Super Admin email from the Master `app_config` doc,
  /// falling back to the `SUPERADMIN_EMAIL` dart-define.
  ///
  /// The Firestore read is only attempted while a user is signed in on the
  /// Master project — Firestore rules deny the doc to unauthenticated callers
  /// and the read would only produce a `permission-denied` before login. No
  /// directory/collection scan is performed: the Super Admin's role is
  /// authorized from its own `users/{uid}` document at sign-in, not from a
  /// legacy `super_admin` lookup.
  static Future<void> ensureLoaded(FirebaseFirestore masterFirestore) async {
    if (_loadStarted && isConfigured) return;
    _loadStarted = true;

    if (_email == null && _envEmail.trim().isNotEmpty) {
      _email = _envEmail.trim().toLowerCase();
    }
    if (_email != null) return;

    // Pre-login there is no way to read the config doc (rules require an
    // authenticated user), so skip the attempt entirely instead of logging a
    // permission-denied error on every launch.
    final signedIn = FirebaseAuth.instanceFor(app: masterFirestore.app)
        .currentUser;
    if (signedIn == null) return;

    try {
      final doc = await masterFirestore
          .collection('app_config')
          .doc('admin_access')
          .get();
      final configured = ((doc.data()?['primaryAdminEmail'] as String?) ?? '')
          .trim()
          .toLowerCase();
      if (configured.isNotEmpty) {
        _email = configured;
      }
    } catch (e) {
      debugPrint('[SuperAdminConfig] reading app_config failed: $e');
    }
  }

  /// Clears cached state (used in tests / after a hard logout).
  static void reset() {
    _loadStarted = false;
    _email = null;
  }
}
