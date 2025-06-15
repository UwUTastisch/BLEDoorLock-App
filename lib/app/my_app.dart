import 'package:flutter/material.dart';
import '../app/theme_controller.dart';
import '../features/ble_door/views/ble_door_page.dart';
import '../theme/custom_theme.dart';

class MyApp extends StatelessWidget {
  final ThemeController _themeController = ThemeController();

  MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeController.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'BLE-Door-Opener',
          theme: CustomTheme.lightTheme,
          darkTheme: CustomTheme.darkTheme,
          themeMode: themeMode,
          home: BleDoorPage(themeController: _themeController),
        );
      },
    );
  }
}
