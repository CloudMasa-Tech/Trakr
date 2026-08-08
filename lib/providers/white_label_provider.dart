// lib/providers/white_label_provider.dart

import 'dart:async';

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
    if (_context.app.name != current.app.name) {
      setContext(current);
    }
  }

  void setContext(FirebaseContext context, {bool isInitial = false}) {
    if (!isInitial && _context.app.name == context.app.name) return;
    _context = context;
    _service = WhiteLabelService(context: context);
    listenToConfig();
    if (!isInitial) notifyListeners();
  }

  void listenToConfig() {
    _configSubscription?.cancel();
    _configSubscription =
        _service.streamConfig().listen((WhiteLabelModel model) {
      _config = model;
      notifyListeners();
    }, onError: (Object error, StackTrace stackTrace) {
      debugPrint('White label config stream error: $error');
      // On error, reset to default to avoid showing stale branding
      _config = WhiteLabelModel.empty;
      notifyListeners();
    });
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
