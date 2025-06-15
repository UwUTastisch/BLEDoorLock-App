import 'package:flutter/material.dart';

class ThemeController {
  final ValueNotifier<ThemeMode> themeMode =
  ValueNotifier(ThemeMode.system);

  void toggleTheme() {
    themeMode.value = (themeMode.value == ThemeMode.dark)
        ? ThemeMode.light
        : ThemeMode.dark;
  }
}