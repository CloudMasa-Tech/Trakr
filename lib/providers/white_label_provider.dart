// lib/providers/white_label_provider.dart

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../firebase/firebase_context.dart';
import '../firebase/firebase_context_provider.dart';
import '../models/white_label_model.dart';
import '../services/white_label_service.dart';
import '../theme/app_theme.dart';

class WhiteLabelProvider extends ChangeNotifier {
  WhiteLabelProvider({FirebaseContext? context}) {
    setContext(context ?? FirebaseContextProvider.current, isInitial: true);
    FirebaseContextProvider.instance?.addListener(_onActiveContextChanged);
  }

  late WhiteLabelService _service;
  StreamSubscription<WhiteLabelModel>? _configSubscription;

  WhiteLabelModel _config = WhiteLabelModel.empty;

  late FirebaseContext _context;

  WhiteLabelModel get config => _config;
  Color get primaryColor => _config.primaryColor;

  /// Follows the app-wide active Firebase context (Master ↔ tenant swaps) so
  /// the live branding always streams from the project the current session
  /// belongs to.
  void _onActiveContextChanged() {
    final current = FirebaseContextProvider.current;
    if (_context.app.name == current.app.name) return;
    try {
      setContext(current);
    } catch (e, s) {
      // A context-switch re-config failure (e.g. stale/deleted tenant app)
      // must never break the notification that drives signIn's completion.
      // Fall back to default theming and keep going.
      debugPrint(
        'White label context switch failed; using default theme. $e\n$s');
    }
  }

  void setContext(FirebaseContext context, {bool isInitial = false}) {
    if (!isInitial && _context.app.name == context.app.name) return;
    _context = context;
    _service = WhiteLabelService(context: context);
    if (_isMasterControlPlane(context)) {
      // The Master control-plane project has no per-tenant white-label config
      // for a regular user to read (reads are super-admin only). Skip the
      // stream entirely to avoid a permission-denied error at startup.
      _configSubscription?.cancel();
      _configSubscription = null;
      _config = WhiteLabelModel.empty;
    } else {
      listenToConfig();
    }
    if (!isInitial) notifyListeners();
  }

  /// True when [context] is bound to the default (Master control-plane) app
  /// rather than a named tenant app.
  bool _isMasterControlPlane(FirebaseContext context) {
    try {
      return context.app.name == Firebase.app().name;
    } catch (_) {
      return true;
    }
  }

  void listenToConfig() {
    _configSubscription?.cancel();
    _configSubscription = null;
    try {
      _configSubscription = _service.streamConfig().listen(
            (WhiteLabelModel model) {
          _config = model;
          notifyListeners();
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('White label config stream error: $error');
          // On error, reset to default to avoid showing stale branding.
          if (_config != WhiteLabelModel.empty) {
            _config = WhiteLabelModel.empty;
            notifyListeners();
          }
        },
      );
    } catch (e, s) {
      // The stream failed to START (e.g. the Firestore client is bound to a
      // deleted app). Degrade to default theming — never let this throw
      // through notifyListeners and hang/abort the login chain.
      debugPrint(
        'White label config stream failed to start; using default theme. '
        '$e\n$s');
      _config = WhiteLabelModel.empty;
    }
  }

  Future<void> updateConfig(WhiteLabelModel model) async {
    await _service.saveConfig(model);
    _config = model;
    notifyListeners();
  }

  ThemeData buildTheme({required Brightness brightness}) {
    return AppTheme.build(
      brightness: brightness,
      primary: _config.primaryColor,
    );
  }

  ThemeData get darkTheme => buildTheme(brightness: Brightness.dark);

  ThemeData get lightTheme => buildTheme(brightness: Brightness.light);

  ThemeData get theme => lightTheme;

  @override
  void dispose() {
    FirebaseContextProvider.instance?.removeListener(_onActiveContextChanged);
    _configSubscription?.cancel();
    super.dispose();
  }
}
