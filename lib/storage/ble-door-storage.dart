
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ble-door.dart';

class BleDoorStorage {
  static const String _bleDoorKey = 'bleDoors';

  static Future<void> addBleDoor(BleDoor bleDoor) async {
    final prefs = await SharedPreferences.getInstance();
    final bleDoorMap = bleDoor.toJson();
    final bleDoorJson = jsonEncode(bleDoorMap);
    List<String> bleDoors = prefs.getStringList(_bleDoorKey) ?? [];
    bleDoors.add(bleDoorJson);
    await prefs.setStringList(_bleDoorKey, bleDoors);
  }

  static Future<void> removeBleDoor(BleDoor bleDoor) async {
    final prefs = await SharedPreferences.getInstance();
    final bleDoorMap = bleDoor.toJson();
    final bleDoorJson = jsonEncode(bleDoorMap);
    List<String> bleDoors = prefs.getStringList(_bleDoorKey) ?? [];
    bleDoors.remove(bleDoorJson);
    await prefs.setStringList(_bleDoorKey, bleDoors);
  }

  static Future<List<BleDoor>> loadBleDoors() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> bleDoorsJson = prefs.getStringList(_bleDoorKey) ?? [];
    return bleDoorsJson.map((doorJson) {
      final doorMap = jsonDecode(doorJson) as Map<String, dynamic>;
      return BleDoor.fromJson(doorMap);
    }).toList();
  }
}