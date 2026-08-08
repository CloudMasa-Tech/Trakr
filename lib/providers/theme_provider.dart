import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Drives the Super Admin portal's dark/light theme and persists the choice
/// locally via [SharedPreferences]. Defaults to dark (the portal's original
/// appearance) until the user toggles.
class ThemeProvider extends ChangeNotifier {
  static const String _prefKey = 'super_admin_theme_mode';
  static const String _dark = 'dark';
  static const String _light = 'light';

  bool _isDark = true;
  bool _disposed = false;

  bool get isDark => _isDark;

  /// Loads the persisted preference. Safe to call once at portal startup.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefKey);
      if (stored == _light && !_disposed) {
        _isDark = false;
        notifyListeners();
      }
    } catch (_) {
      // Fall back to the default (dark) on any persistence failure.
    }
  }

  Future<void> toggle() => setDark(!_isDark);

  Future<void> setDark(bool value) async {
    if (_isDark == value) return;
    _isDark = value;
    if (!_disposed) notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, value ? _dark : _light);
    } catch (_) {
      // Persistence is best-effort; the in-memory choice still applies.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
