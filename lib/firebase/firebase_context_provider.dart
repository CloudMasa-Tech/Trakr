import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'firebase_context.dart';

/// Holds the active [FirebaseContext] and exposes it to the widget tree so
/// services and screens can read the current Firebase project through a single
/// source of truth instead of touching `FirebaseX.instance` directly.
///
/// During Phase 1 there is exactly one context bound to the default Firebase
/// project. A later phase will swap the context when the active workspace
/// changes, which is why this is a [ChangeNotifier].
class FirebaseContextProvider extends ChangeNotifier {
  FirebaseContextProvider({FirebaseContext? context})
      : _context = context ?? FirebaseContext() {
    _current = _context;
    _instance = this;
  }

  static FirebaseContext? _current;
  static FirebaseContextProvider? _instance;

  /// The currently active [FirebaseContext]. Defaults to a context bound to the
  /// default Firebase project, so services constructed without an explicit
  /// context still resolve to the same project the app was booted with.
  static FirebaseContext get current => _current ??= FirebaseContext();

  /// The live provider instance registered by the app bootstrap. Used by
  /// non-widget code (e.g. [FirebaseManager]) to swap the active context.
  static FirebaseContextProvider? get instance => _instance;

  /// Static entry point that swaps the active context from anywhere, including
  /// outside the widget tree. Updates the static [current] so late-bound
  /// services resolve to the new context, and notifies the live provider so
  /// widgets reading `context.firebase` rebuild against the new project.
  static void setActive(FirebaseContext context) {
    _current = context;
    _instance?._apply(context);
  }

  FirebaseContext _context;

  /// The active [FirebaseContext].
  FirebaseContext get context => _context;

  /// Swaps the active context (used when the workspace/tenant changes). Also
  /// updates the static [current] so late-bound services resolve to the new
  /// context.
  void setContext(FirebaseContext context) {
    setActive(context);
  }

  void _apply(FirebaseContext context) {
    _context = context;
    notifyListeners();
  }
}

/// Convenience accessors so screens and widgets can reach the active Firebase
/// services as `context.firebase.auth`, `context.firebase.firestore`, etc.
extension FirebaseContextX on BuildContext {
  /// The active [FirebaseContext] provided above this widget.
  FirebaseContext get firebase => read<FirebaseContextProvider>().context;
}
