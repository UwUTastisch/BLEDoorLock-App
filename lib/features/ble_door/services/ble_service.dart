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

    // Old unencrypted method - commented out
    // await userChar.write(Uint8List.fromList(utf8.encode(door.userName)));
    // await passChar.write(Uint8List.fromList(utf8.encode(door.password)));
    // await lockStateChar.write(Uint8List.fromList(utf8.encode('2')));

    final crypto = _getCrypto(door);
    final encryptedUserName = crypto.prepareBLEData(door.userName);
    final encryptedPassword = crypto.prepareBLEData(door.password);
    final encryptedAction = crypto.prepareBLEData('2');
    
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

    // For development: Send PEM format instead of DER
    String rsaKeyPEM = crypto.publicKey; // Get PEM string directly
    Uint8List rsaKeyBytes = Uint8List.fromList(utf8.encode(rsaKeyPEM));
    
    if (kDebugMode) {
      print('[BLE] Starting key exchange protocol...');
      print('[BLE] Sending PEM key (${rsaKeyBytes.length} bytes):');
      print(rsaKeyPEM);
    }

    // Try single write first, fall back to chunked if it fails
    bool usedChunkedTransfer = false;
    try {
      if (kDebugMode) {
        print('[BLE] Attempting single write of ${rsaKeyBytes.length} bytes');
      }
      await keyChar.write(rsaKeyBytes, withoutResponse: false);
      if (kDebugMode) {
        print('[BLE] Single write successful');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[BLE] Single write failed: $e, falling back to chunked write');
      }
      // Fall back to chunked write
      await _writeDataInChunks(keyChar, rsaKeyBytes);
      usedChunkedTransfer = true;
    }
    
    // Wait for ESP32 to process the key and generate AES key
    // Use different delays based on transfer method
    if (usedChunkedTransfer) {
      if (kDebugMode) {
        print('[BLE] Waiting for ESP32 to process chunked key transfer...');
      }
      await Future.delayed(const Duration(milliseconds: 500)); // More time for chunked
    } else {
      if (kDebugMode) {
        print('[BLE] Waiting for ESP32 to process single key transfer...');
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // Attempt to read the encrypted AES key with retry logic
    Uint8List? encryptedAesKey;
    int maxRetries = 3;
    int retryDelay = 200; // ms
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (kDebugMode) {
          print('[BLE] Reading encrypted AES key (attempt $attempt/$maxRetries)...');
        }
        
        List<int> rawResponse = await keyChar.read();
        
        if (kDebugMode) {
          print('[BLE] Raw response length: ${rawResponse.length}');
          print('[BLE] Raw response: ${rawResponse.map((e) => e.toRadixString(16)).join(' ')}');
        }
        
        if (rawResponse.isEmpty) {
          throw Exception('Empty response received from device');
        }
        
        // Extract only the first 128 bytes (RSA-1024 encrypted AES key size)
        // The characteristic is 256 bytes but ESP32 only writes 128 bytes of actual data
        const int expectedEncryptedSize = 128;
        if (rawResponse.length < expectedEncryptedSize) {
          throw Exception('Response too short: expected at least $expectedEncryptedSize bytes, got ${rawResponse.length}');
        }
        
        encryptedAesKey = Uint8List.fromList(rawResponse.take(expectedEncryptedSize).toList());
        
        if (kDebugMode) {
          print('[BLE] Extracted encrypted AES key (${encryptedAesKey.length} bytes): ${encryptedAesKey.map((e) => e.toRadixString(16)).join(' ')}');
        }
        
        // Validate that we didn't get back our own RSA key (for PEM format)
        if (encryptedAesKey.length == rsaKeyBytes.length && 
            encryptedAesKey.take(32).join() == rsaKeyBytes.take(32).join()) {
          throw Exception('Received encrypted AES key matches RSA key, ESP32 may not have processed the key correctly');
        }
        
        // Check if response is all zeros (error indication)
        if (encryptedAesKey.every((byte) => byte == 0)) {
          throw Exception('Received all-zero response, ESP32 encryption failed');
        }
        
        // Success! Break out of retry loop
        if (kDebugMode) {
          print('[BLE] Successfully received valid encrypted AES key');
        }
        break;
        
      } catch (e) {
        if (kDebugMode) {
          print('[BLE] Attempt $attempt failed: $e');
        }
        
        if (attempt == maxRetries) {
          // Last attempt failed
          throw Exception('Failed to read encrypted AES key from device after $maxRetries attempts: $e');
        } else {
          // Wait before retrying
          if (kDebugMode) {
            print('[BLE] Waiting ${retryDelay}ms before retry...');
          }
          await Future.delayed(Duration(milliseconds: retryDelay));
          retryDelay += 100; // Increase delay for each retry
        }
      }
    }
    
    // Ensure we have a valid encrypted AES key before proceeding
    if (encryptedAesKey == null) {
      throw Exception('Failed to receive encrypted AES key from device after $maxRetries attempts');
    }
    
    // Set the AES key in the crypto client
    final success = crypto.setEncryptedAesKey(encryptedAesKey);
    if (!success || crypto.aesKeyStatus != AesKeyStatus.set) {
      throw Exception('Failed to set up crypto connection: AES key decryption failed');
    }
    
    if (kDebugMode) {
      print('[BLE] ✅ Key exchange completed successfully!');
      print('[BLE] AES-256 session established and ready for encrypted communication');
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

    // Old unencrypted method - commented out
    /*
    await adminChar.write(Uint8List.fromList(utf8.encode(admin.userName)));
    await adminPassChar.write(Uint8List.fromList(utf8.encode(admin.password)));
    await addUserChar.write(Uint8List.fromList(utf8.encode(newUser.userName)));
    await addPassChar.write(Uint8List.fromList(utf8.encode(newUser.password)));
    await adminActionChar.write(Uint8List.fromList(utf8.encode('1')));
    */

    final crypto = _getCrypto(admin);
    final encryptedAdminName = crypto.prepareBLEData(admin.userName);
    final encryptedAdminPassword = crypto.prepareBLEData(admin.password);
    final encryptedUserName = crypto.prepareBLEData(newUser.userName);
    final encryptedPassword = crypto.prepareBLEData(newUser.password);
    final encryptedAction = crypto.prepareBLEData('1');
    
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

  /// Writes large data in chunks to handle BLE MTU limitations
  /// Uses a simple header protocol: [HEADER][CHUNK_NUM][DATA...]
  /// Header format: 0xFF (magic), total_size_low, total_size_high, chunk_num
  Future<void> _writeDataInChunks(BluetoothCharacteristic characteristic, Uint8List data) async {
    const int headerSize = 4; // magic(1) + size(2) + chunk_num(1)
    const int maxChunkSize = 20;
    const int dataPerChunk = maxChunkSize - headerSize; // 16 bytes of data per chunk
    
    final int totalChunks = (data.length / dataPerChunk).ceil();
    
    if (kDebugMode) {
      print('[BLE] 📦 Starting chunked transfer: ${data.length} bytes in $totalChunks chunks');
      print('[BLE] Each chunk: ${headerSize} header + ${dataPerChunk} data bytes = ${maxChunkSize} total');
    }
    
    for (int chunkNum = 0; chunkNum < totalChunks; chunkNum++) {
      final int dataOffset = chunkNum * dataPerChunk;
      final int dataEnd = (dataOffset + dataPerChunk > data.length) ? data.length : dataOffset + dataPerChunk;
      final int actualDataSize = dataEnd - dataOffset;
      
      // Create chunk with header
      final chunk = Uint8List(headerSize + actualDataSize);
      
      // Header: [0xFF][size_low][size_high][chunk_num]
      chunk[0] = 0xFF; // Magic byte
      chunk[1] = data.length & 0xFF; // Total size low byte
      chunk[2] = (data.length >> 8) & 0xFF; // Total size high byte  
      chunk[3] = chunkNum; // Chunk number
      
      // Data
      chunk.setRange(headerSize, headerSize + actualDataSize, data, dataOffset);
      
      if (kDebugMode) {
        print('[BLE] 📤 Sending chunk ${chunkNum + 1}/$totalChunks: ${chunk.length} bytes (${actualDataSize} data)');
        if (chunkNum == 0) {
          // Show header details for first chunk
          print('[BLE] Header: [0x${chunk[0].toRadixString(16)}][0x${chunk[1].toRadixString(16)}][0x${chunk[2].toRadixString(16)}][0x${chunk[3].toRadixString(16)}]');
        }
      }
      
      try {
        await characteristic.write(chunk, withoutResponse: false);
        
        if (kDebugMode) {
          print('[BLE] ✅ Chunk ${chunkNum + 1}/$totalChunks sent successfully');
        }
        
      } catch (e) {
        print('[BLE] ❌ Error writing chunk ${chunkNum + 1}: $e');
        throw Exception('Failed to write chunk ${chunkNum + 1}: $e');
      }
      
      // Adaptive delay based on chunk number and total chunks
      int delay = 25;
      if (totalChunks > 10) {
        // For large transfers, use longer delays
        delay = 30;
      }
      if (chunkNum == totalChunks - 1) {
        // Last chunk gets extra time to ensure ESP32 processes it
        delay = 50;
      }
      
      await Future.delayed(Duration(milliseconds: delay));
    }
    
    if (kDebugMode) {
      print('[BLE] 📦✅ Chunked transfer completed: $totalChunks chunks sent successfully');
      print('[BLE] Total data transferred: ${data.length} bytes');
    }
  }
}
