import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's light / dark / system choice and persists it with
/// shared_preferences. Hand-written; lives beside the generated tokens.
///
/// Defaults to [ThemeMode.light] on purpose: the legacy views still use
/// hard-coded light colours, so following the OS into dark mode would look
/// broken until the Phase 3-5 migrations. Switch the default to
/// [ThemeMode.system] once those are done.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.light}) : _mode = initial;

  static const String prefsKey = 'ui.themeMode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  /// Reads the saved choice. Never throws: a storage failure must not stop the till starting.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = parse(prefs.getString(prefsKey), fallback: _mode);
    } catch (_) {
      // Keep the default.
    }
  }

  /// Applies [mode] immediately, then persists it.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, mode.name);
    } catch (_) {
      // The choice still applies for this session.
    }
  }

  /// Parses a stored name; unknown or missing values fall back.
  static ThemeMode parse(String? value, {ThemeMode fallback = ThemeMode.light}) {
    for (final m in ThemeMode.values) {
      if (m.name == value) return m;
    }
    return fallback;
  }
}
