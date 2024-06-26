import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';

String generateRandomString(int length) {
  const _allowedChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  Random _random = Random();

  return List.generate(length, (index) {
    return _allowedChars[_random.nextInt(_allowedChars.length)];
  }).join();
}

bool isValidUsername(String username) {
  return username.length >= 3;
}

double rightAngle() {
  return pi / 2;
}

Color adjustBrightness(Color color, [double amount = 0.2]) {
  assert(amount >= -1 && amount <= 1);

  final hsl = HSLColor.fromColor(color);
  final hslModified = hsl.withLightness(
    (hsl.lightness + amount).clamp(0.0, 1.0),
  );
  return hslModified.toColor();
}