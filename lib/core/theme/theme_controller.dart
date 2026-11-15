import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';

/// Light / dark / follow-the-device, remembered on this device.
///
/// Kept in the device's own preferences rather than in the business settings.
/// With one database shared by every device, a theme stored there would mean
/// one person's click turning every till in the business dark.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => _parse(ref.watch(clientPreferencesProvider).themeMode);

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(clientPreferencesProvider).setThemeMode(mode.name);
  }

  /// Cycles light -> dark -> system, for the top bar's single-click toggle.
  Future<void> cycle() {
    final next = switch (state) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    return set(next);
  }

  static ThemeMode _parse(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
