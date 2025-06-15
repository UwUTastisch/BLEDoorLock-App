// lib/features/ble_door/services/ble_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../utils/ble_constants.dart';
import '../models/ble_door.dart';

class BleService {
  Future<void> connectAndOpen(
      BluetoothDevice device, BleDoor door) async {
    await device.connect();
    final services = await device.discoverServices();

    BluetoothCharacteristic? userChar;
    BluetoothCharacteristic? passChar;
    BluetoothCharacteristic? lockStateChar;

    for (var svc in services) {
      if (svc.uuid == BleConstants.uuidUserService) {
        for (var c in svc.characteristics) {
          if (c.uuid == BleConstants.uuidUserCharacteristic)
            userChar = c;
          else if (c.uuid == BleConstants.uuidPassCharacteristic)
            passChar = c;
          else if (c.uuid ==
              BleConstants.uuidLockStateCharacteristic) lockStateChar = c;
        }
      }
    }

    if (userChar == null ||
        passChar == null ||
        lockStateChar == null) {
      throw Exception('Required characteristic not found');
    }

    await userChar
        .write(Uint8List.fromList(utf8.encode(door.userName)));
    await passChar
        .write(Uint8List.fromList(utf8.encode(door.password)));
    await lockStateChar
        .write(Uint8List.fromList(utf8.encode('2')));

    await device.disconnect();
  }

  Future<void> addUser(BluetoothDevice device, BleDoor admin,
      BleDoor newUser) async {
    await device.connect();
    final services = await device.discoverServices();

    BluetoothCharacteristic? adminChar;
    BluetoothCharacteristic? adminPassChar;
    BluetoothCharacteristic? addUserChar;
    BluetoothCharacteristic? addPassChar;
    BluetoothCharacteristic? adminActionChar;

    for (var svc in services) {
      if (svc.uuid == BleConstants.uuidAdminService) {
        for (var c in svc.characteristics) {
          if (c.uuid == BleConstants.uuidAdminCharacteristic)
            adminChar = c;
          else if (c.uuid ==
              BleConstants.uuidAdminPassCharacteristic)
            adminPassChar = c;
          else if (c.uuid ==
              BleConstants.uuidAddUserCharacteristic)
            addUserChar = c;
          else if (c.uuid ==
              BleConstants.uuidAddPassCharacteristic)
            addPassChar = c;
          else if (c.uuid ==
              BleConstants.uuidAdminActionCharacteristic)
            adminActionChar = c;
        }
      }
    }

    if (adminChar == null ||
        adminPassChar == null ||
        addUserChar == null ||
        addPassChar == null ||
        adminActionChar == null) {
      throw Exception('Required admin characteristic not found');
    }

    await adminChar.write(
        Uint8List.fromList(utf8.encode(admin.userName)));
    await adminPassChar.write(
        Uint8List.fromList(utf8.encode(admin.password)));
    await addUserChar.write(
        Uint8List.fromList(utf8.encode(newUser.userName)));
    await addPassChar.write(
        Uint8List.fromList(utf8.encode(newUser.password)));
    await adminActionChar
        .write(Uint8List.fromList(utf8.encode('1')));

    await device.disconnect();
  }
}
