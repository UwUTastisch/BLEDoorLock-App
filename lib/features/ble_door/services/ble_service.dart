// lib/features/ble_door/services/ble_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../utils/ble_constants.dart';
import '../../../utils/session_crypto.dart';
import '../models/ble_door.dart';

class BleService {
  //map  session_crypto
  final Map<String, HybridEncryptionClient> _sessionCrypto = {};

  Future<void> open(BluetoothDevice device, BleDoor door) async {
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
          else if (c.uuid == BleConstants.uuidLockStateCharacteristic)
            lockStateChar = c;
        }
      }
    }

    if (userChar == null || passChar == null || lockStateChar == null) {
      throw Exception('Required characteristic not found');
    }

    //await userChar.write(Uint8List.fromList(utf8.encode(door.userName)));
    //await passChar.write(Uint8List.fromList(utf8.encode(door.password)));
    //await lockStateChar.write(Uint8List.fromList(utf8.encode('2')));

    final crypto = _getCrypto(door);
    final encryptedUserName = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode(door.userName)));
    final encryptedPassword = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode(door.password)));
    final encryptedAction = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode('2')));
    await userChar.write(encryptedUserName);
    await passChar.write(encryptedPassword);
    await lockStateChar.write(encryptedAction);

    await device.disconnect();
  }

  Future<void> getCryptoConnection(BluetoothDevice device, BleDoor door) async {
    await device.connect();
    final services = await device.discoverServices();
    BluetoothCharacteristic? keyChar;

    for (var svc in services) {
      if (svc.uuid == BleConstants.uuidCryptoService) {
        for (var c in svc.characteristics) {
          if (c.uuid == BleConstants.uuidKeyCharacteristic) keyChar = c;
        }
      }
    }

    if (keyChar == null) {
      throw Exception('Required crypto characteristic not found');
    }

    final crypto = _getCrypto(door);

    final rsaKey = crypto.rsaKeyPair.publicKey.toString();

    //subscribe to the key characteristic
    await keyChar.setNotifyValue(true);

    // add listeners to the key characteristic
    keyChar.lastValueStream.listen((value) {
      if (value.isNotEmpty) {
        final encryptedAesKey = Uint8List.fromList(value);
        if (encryptedAesKey.isEmpty) return;
        if (encryptedAesKey == Uint8List.fromList(utf8.encode(rsaKey))) return;
        try {
          if (crypto.setEncryptedAesKey(encryptedAesKey)) {
            if (kDebugMode) {
              print('AES key set successfully');
            }
          } else {
            if (kDebugMode) {
              print('AES key already set, reset key');
            }
            keyChar?.setNotifyValue(false);
            getCryptoConnection(device, door);
            return;
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error setting AES key: $e');
          }
          keyChar?.setNotifyValue(false);
          throw Exception('Failed to set AES key: $e');
        }
      }
    });

    await keyChar.write(Uint8List.fromList(utf8.encode(rsaKey)));
    // wait for the key characteristic to be updated
    await Future.delayed(const Duration(seconds: 2));
    if (crypto.aesKeyStatus != AesKeyStatus.set) {
      keyChar.setNotifyValue(false);
      throw Exception('Failed to set up crypto connection');
    }
  }

  Future<void> addUser(
      BluetoothDevice device, BleDoor admin, BleDoor newUser) async {
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
          else if (c.uuid == BleConstants.uuidAdminPassCharacteristic)
            adminPassChar = c;
          else if (c.uuid == BleConstants.uuidAddUserCharacteristic)
            addUserChar = c;
          else if (c.uuid == BleConstants.uuidAddPassCharacteristic)
            addPassChar = c;
          else if (c.uuid == BleConstants.uuidAdminActionCharacteristic)
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

    /*
    await adminChar.write(Uint8List.fromList(utf8.encode(admin.userName)));
    await adminPassChar.write(Uint8List.fromList(utf8.encode(admin.password)));
    await addUserChar.write(Uint8List.fromList(utf8.encode(newUser.userName)));
    await addPassChar.write(Uint8List.fromList(utf8.encode(newUser.password)));
    await adminActionChar.write(Uint8List.fromList(utf8.encode('1')));
     */

    final crypto = _getCrypto(admin);
    final encryptedUserName = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode(newUser.userName)));
    final encryptedPassword = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode(newUser.password)));
    final encryptedAdminName = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode(admin.userName)));
    final encryptedAdminPassword = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode(admin.password)));
    final encryptedAction = crypto.encryptAesData(
        Uint8List.fromList(utf8.encode('1')));
    await adminChar.write(encryptedAdminName);
    await adminPassChar.write(encryptedAdminPassword);
    await addUserChar.write(encryptedUserName);
    await addPassChar.write(encryptedPassword);
    await adminActionChar.write(encryptedAction);
    // wait for the admin action characteristic to be updated
    await device.disconnect();
  }

  HybridEncryptionClient _getCrypto(BleDoor door) {
    return _sessionCrypto.putIfAbsent(door.peripheralMacAddress, () {
      return HybridEncryptionClient.generate();
    });
  }
}
