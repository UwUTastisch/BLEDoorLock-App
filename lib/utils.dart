import 'dart:math';

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