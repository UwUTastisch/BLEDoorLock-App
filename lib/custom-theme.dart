import 'package:flutter/material.dart';

class CustomTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: Colors.pink,
      dividerColor: Colors.black54,
      // other properties for the light theme
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: Colors.grey[900],
      dividerColor: Colors.white54,
      // other properties for the dark theme
    );
  }
}