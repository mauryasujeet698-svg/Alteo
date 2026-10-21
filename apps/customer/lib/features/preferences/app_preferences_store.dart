import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appPreferencesStoreProvider = Provider<AppPreferencesStore>((ref) {
  final store = AppPreferencesStore();
  unawaited(store.load());
  ref.onDispose(store.dispose);
  return store;
});

/// Device-local UI preferences. Notification preferences become account-synced
/// only after notification registration and the customer profile API exist.
class AppPreferencesStore extends ChangeNotifier {
  static const _themeKey = 'alteo.theme_mode.v1';
  static const _notificationsKey = 'alteo.notifications_enabled.v1';

  ThemeMode _themeMode = ThemeMode.system;
  bool _notificationsEnabled = true;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  bool get notificationsEnabled => _notificationsEnabled;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final preferences = await SharedPreferences.getInstance();
      final themeName = preferences.getString(_themeKey);
      for (final mode in ThemeMode.values) {
        if (mode.name == themeName) _themeMode = mode;
      }
      _notificationsEnabled =
          preferences.getBool(_notificationsKey) ?? true;
      notifyListeners();
    } catch (_) {
      // Keep accessible system defaults if local preferences cannot be read.
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    unawaited(_persist());
  }

  void setNotificationsEnabled(bool enabled) {
    if (_notificationsEnabled == enabled) return;
    _notificationsEnabled = enabled;
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_themeKey, _themeMode.name);
      await preferences.setBool(_notificationsKey, _notificationsEnabled);
    } catch (_) {
      // Preferences remain usable for the current session if storage is absent.
    }
  }
}
