import 'package:flutter/material.dart';

import '../web/web_storage_stub.dart'
    if (dart.library.html) '../web/web_storage_web.dart';

class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();
  static const String _storageKey = 'intesud_theme_mode';

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> initialize() async {
    final storedValue = webStorageGet(_storageKey);
    if (storedValue == 'dark') {
      _themeMode = ThemeMode.dark;
      return;
    }

    if (storedValue == 'light') {
      _themeMode = ThemeMode.light;
    }
  }

  void toggleDarkMode(bool enabled) {
    final nextMode = enabled ? ThemeMode.dark : ThemeMode.light;
    if (_themeMode == nextMode) {
      return;
    }

    _themeMode = nextMode;
    webStorageSet(_storageKey, enabled ? 'dark' : 'light');
    notifyListeners();
  }
}
