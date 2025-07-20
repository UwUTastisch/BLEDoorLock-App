import 'dart:typed_data';
import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'dart:convert';
// import 'package:flutter/foundation.dart'; // For kDebugMode if needed

enum AesKeyStatus {
  unset,
  set,
  expired,
}

class HybridEncryptionClient {

  final AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> rsaKeyPair;
  Uint8List? _aesKey;
  AesKeyStatus _aesKeyStatus = AesKeyStatus.unset;


  static final Uint8List _fixedIV = Uint8List.fromList([
    0x46, 0x61, 0x63, 0x68, 0x73, 0x63,
    0x68, 0x61, 0x66, 0x74, 0x45, 0x54
  ]);

  HybridEncryptionClient({required this.rsaKeyPair});

  factory HybridEncryptionClient.generate() {
    return HybridEncryptionClient(rsaKeyPair: _generateRSAKeyPair());
  }

  AesKeyStatus get aesKeyStatus => _aesKeyStatus;

  // Entschlüsselt den AES-Schlüssel
  bool setEncryptedAesKey(Uint8List encryptedAesKey) {
    if (_aesKeyStatus == AesKeyStatus.expired) {
      throw StateError('AES key is expired, please refresh it');
    }
    
    try {
      print('[CRYPTO] Attempting to decrypt ${encryptedAesKey.length}-byte encrypted AES key');
      print('[CRYPTO] First 32 bytes: ${encryptedAesKey.take(32).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      // Try multiple RSA/OAEP configurations to match ESP32
      print('[CRYPTO] Trying RSA/OAEP with SHA-256...');
      
      try {
        // Method 1: RSA/OAEP with SHA-256 - correct parameter order for PointyCastle
        final oaep = OAEPEncoding.withCustomDigest(() => SHA256Digest(), RSAEngine());
        oaep.init(false, PrivateKeyParameter<RSAPrivateKey>(rsaKeyPair.privateKey));
        _aesKey = oaep.process(encryptedAesKey);
        
        if (_aesKey != null && _aesKey!.length == 32) {
          print('[CRYPTO] Success with RSA/OAEP SHA-256');
        } else {
          throw Exception('Invalid result length: ${_aesKey?.length}');
        }
      } catch (e1) {
        print('[CRYPTO] RSA/OAEP SHA-256 failed: $e1');
        print('[CRYPTO] Trying RSA/OAEP with default settings...');
        
        try {
          // Method 2: RSA/OAEP with default settings (SHA-1)
          final oaep = OAEPEncoding(RSAEngine());
          oaep.init(false, PrivateKeyParameter<RSAPrivateKey>(rsaKeyPair.privateKey));
          _aesKey = oaep.process(encryptedAesKey);
          
          if (_aesKey != null && _aesKey!.length == 32) {
            print('[CRYPTO] Success with RSA/OAEP default (SHA-1)');
          } else {
            throw Exception('Invalid result length: ${_aesKey?.length}');
          }
        } catch (e2) {
          print('[CRYPTO] RSA/OAEP default failed: $e2');
          print('[CRYPTO] Trying basic RSA decryption...');
          
          // Method 3: Basic RSA without OAEP (last resort)
          final rsa = RSAEngine();
          rsa.init(false, PrivateKeyParameter<RSAPrivateKey>(rsaKeyPair.privateKey));
          final result = rsa.process(encryptedAesKey);
          
          print('[CRYPTO] Basic RSA result length: ${result.length}');
          print('[CRYPTO] Basic RSA result: ${result.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
          
          // For basic RSA, we need to extract the actual data (last 32 bytes typically)
          if (result.length >= 32) {
            _aesKey = result.sublist(result.length - 32);
            print('[CRYPTO] Success with basic RSA, extracted last 32 bytes');
          } else {
            throw Exception('Basic RSA result too short: ${result.length}');
          }
        }
      }

      if (_aesKey == null || _aesKey!.isEmpty) {
        throw StateError('All decryption methods failed');
      }
      
      print('[CRYPTO] Successfully decrypted AES key: ${_aesKey!.length} bytes');
      print('[CRYPTO] Decrypted AES key: ${_aesKey!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      
      // Validate AES key size (should be 32 bytes for AES-256)
      if (_aesKey!.length != 32) {
        throw StateError('Invalid AES key size: expected 32 bytes, got ${_aesKey!.length}');
      }
      
      _aesKeyStatus = AesKeyStatus.set;
      print('[CRYPTO] AES-256 key successfully set: ${_aesKey!.length} bytes');
      return true;
    } catch (e) {
      print('[CRYPTO] AES key decryption failed: $e');
      _aesKeyStatus = AesKeyStatus.unset;
      return false;
    }
  }


  // Verschlüsselt Daten mit AES-GCM
  Uint8List encryptAesData(Uint8List plaintext) {
    if (_aesKey == null) throw StateError('AES key not set');

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
        KeyParameter(_aesKey!),
        128, // 128-bit tag (16 bytes)
        _fixedIV,
        Uint8List(0) // Associated Data
    );
    cipher.init(true, params);

    return cipher.process(plaintext);
  }

  // Entschlüsselt Daten mit AES-GCM
  Uint8List decryptAesData(Uint8List encryptedDataWithTag) {
    if (_aesKey == null) throw StateError('AES key not set');

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
        KeyParameter(_aesKey!),
        128, // 128-bit tag (16 bytes)
        _fixedIV,
        Uint8List(0) // Associated Data
    );
    cipher.init(false, params);

    return cipher.process(encryptedDataWithTag);
  }

  // Hilfsfunktionen
  static String _encodeBigInt(BigInt number) {
    var bytes = _bigIntToBytes(number);
    return base64.encode(bytes);
  }

  static Uint8List _bigIntToBytes(BigInt number) {
    var data = number.toRadixString(16);
    if (data.length % 2 == 1) data = '0$data';

    final result = Uint8List(data.length ~/ 2);
    for (var i = 0; i < data.length; i += 2) {
      final byte = int.parse(data.substring(i, i + 2), radix: 16);
      result[i ~/ 2] = byte;
    }
    return result;
  }

  static AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateRSAKeyPair() {
    final keyParams = RSAKeyGeneratorParameters(BigInt.parse('65537'), 1024, 64);
    final random = FortunaRandom()..seed(KeyParameter(Uint8List(32)));
    final params = ParametersWithRandom(keyParams, random);

    final keyGen = RSAKeyGenerator();
    keyGen.init(params);
    
    // Generate the key pair ONCE
    final keyPair = keyGen.generateKeyPair();
    
    print('[CRYPTO] Generating RSA key pair...');
    print('[CRYPTO] Public Key: ${CryptoUtils.encodeRSAPublicKeyToPemPkcs1(keyPair.publicKey)}');
    print('[CRYPTO] Private Key: ${CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(keyPair.privateKey)}');
    
    return keyPair;
  }

  String get publicKey {
    return CryptoUtils.encodeRSAPublicKeyToPemPkcs1(rsaKeyPair.publicKey);
  }

  // Commented out - not needed for production
  // String get privateKey {
  //   return CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(rsaKeyPair.privateKey);
  // }

  // Add this method to convert PEM to DER
  Uint8List get publicKeyDER {
    final pem = CryptoUtils.encodeRSAPublicKeyToPemPkcs1(rsaKeyPair.publicKey);
    return CryptoUtils.getBytesFromPEMString(pem);
  }

// Update your encrypt method to return separate ciphertext and tag
  Map<String, Uint8List> encryptAesDataSeparated(Uint8List plaintext) {
    if (_aesKey == null) throw StateError('AES key not set');

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
        KeyParameter(_aesKey!),
        128, // 128-bit tag
        _fixedIV,
        Uint8List(0)
    );
    cipher.init(true, params);

    final result = cipher.process(plaintext);
    final ciphertext = result.sublist(0, result.length - 16);
    final tag = result.sublist(result.length - 16);

    return {
      'ciphertext': ciphertext,
      'tag': tag,
    };
  }

// Method to prepare data for BLE transmission (16 bytes plaintext → 32 bytes)
  Uint8List prepareBLEData(String text) {
    if (_aesKey == null) throw StateError('AES key not set');
    
    print('[BLE] Preparing BLE data for: "$text"');
    
    // Pad or truncate to exactly 16 bytes
    final bytes = utf8.encode(text);
    final paddedBytes = Uint8List(16);

    if (bytes.length <= 16) {
      paddedBytes.setRange(0, bytes.length, bytes);
    } else {
      paddedBytes.setRange(0, 16, bytes);
    }

    print('[BLE] Padded bytes (16): ${paddedBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    final encrypted = encryptAesDataSeparated(paddedBytes);
    final result = Uint8List(32);
    result.setRange(0, 16, encrypted['ciphertext']!);
    result.setRange(16, 32, encrypted['tag']!);

    print('[BLE] Encrypted result (32): ${result.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('[BLE] Ciphertext (16): ${encrypted['ciphertext']!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('[BLE] Tag (16): ${encrypted['tag']!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

    return result;
  }

  // Reset AES key status (for new sessions)
  void resetAesKey() {
    _aesKey = null;
    _aesKeyStatus = AesKeyStatus.unset;
  }

  // Expire current AES key (force new key exchange)
  void expireAesKey() {
    _aesKeyStatus = AesKeyStatus.expired;
  }

  // Method to prepare RSA public key for BLE transmission (single write, padded to 256 bytes)
  Uint8List preparePublicKeyForBLE() {
    final derBytes = publicKeyDER;
    print('[BLE] DER key size: ${derBytes.length} bytes');
    //print('[BLE] DER key: ${derBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    // Pad to exactly 256 bytes as expected by ESP32
    final paddedKey = Uint8List(256);
    if (derBytes.length <= 256) {
      paddedKey.setRange(0, derBytes.length, derBytes);
      //paddedKey = Uint8List.fromList(derBytes);
      //print('[BLE] Padded key size: ${paddedKey.length} bytes');
      print('[BLE] Padded key: ${paddedKey.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
      // Rest remains zero-padded
    } else {
      throw StateError('DER key too large: ${derBytes.length} bytes > 256');
    }

    //print('[BLE] Padded key for BLE: ${paddedKey.sublist(0, derBytes.length).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    return paddedKey;
  }

  // Legacy method for chunked transmission (if needed)
  // Commented out - not used in current implementation
  /*
  List<Uint8List> preparePublicKeyForBLEChunked() {
    final derBytes = publicKeyDER;
    final chunks = <Uint8List>[];
    
    // Split into 32-byte chunks for BLE transmission
    for (int i = 0; i < derBytes.length; i += 32) {
      final end = (i + 32 < derBytes.length) ? i + 32 : derBytes.length;
      chunks.add(derBytes.sublist(i, end));
    }
    
    return chunks;
  }
  */

  // Decrypt received BLE data (32 bytes = 16 ciphertext + 16 tag)
  String decryptBLEData(Uint8List bleData) {
    if (_aesKey == null) throw StateError('AES key not set');
    
    if (bleData.length != 32) {
      throw ArgumentError('BLE data must be exactly 32 bytes, got ${bleData.length}');
    }
    
    print('[BLE] Decrypting BLE data (32): ${bleData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    final ciphertext = bleData.sublist(0, 16);
    final tag = bleData.sublist(16, 32);
    
    print('[BLE] Ciphertext (16): ${ciphertext.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('[BLE] Tag (16): ${tag.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    // Reconstruct the format expected by decryptAesData
    final combined = Uint8List(32);
    combined.setRange(0, 16, ciphertext);
    combined.setRange(16, 32, tag);
    
    final decrypted = decryptAesData(combined);
    
    print('[BLE] Decrypted bytes: ${decrypted.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    
    // Remove null padding and convert to string
    int nullIndex = decrypted.indexOf(0);
    if (nullIndex == -1) nullIndex = decrypted.length;
    
    final result = utf8.decode(decrypted.sublist(0, nullIndex));
    print('[BLE] Decrypted text: "$result"');
    
    return result;
  }

  // ===============================================
  // TESTING & DEBUG METHODS - Comment out for production
  // ===============================================
  
  /*
  // Test method to verify encryption/decryption compatibility
  bool testEncryptionCompatibility() {
    print('\n=== Testing Encryption Compatibility ===');
    
    try {
      // Test data
      final testStrings = ['admin', 'user123', 'password', 'test'];
      
      for (final testString in testStrings) {
        print('\nTesting: "$testString"');
        
        // Encrypt
        final encrypted = prepareBLEData(testString);
        
        // Decrypt
        final decrypted = decryptBLEData(encrypted);
        
        final success = decrypted == testString;
        print('Result: ${success ? "✓ PASS" : "✗ FAIL"}');
        print('Expected: "$testString"');
        print('Got: "$decrypted"');
        
        if (!success) {
          print('❌ Encryption/Decryption test failed for "$testString"');
          return false;
        }
      }
      
      print('\n✅ All encryption/decryption tests passed!');
      return true;
    } catch (e) {
      print('❌ Encryption test failed with error: $e');
      return false;
    }
  }

  // Complete integration test method
  bool testCompleteIntegration() {
    print('\n=== Testing Complete Integration ===');
    
    try {
      // Test RSA key preparation
      print('1. Testing RSA key preparation...');
      final rsaKeyData = preparePublicKeyForBLE();
      print('✓ RSA key prepared: ${rsaKeyData.length} bytes');
      
      // Mock setting an AES key (in real scenario, this comes from ESP32)
      print('2. Testing AES key setup...');
      _aesKey = Uint8List.fromList(List.generate(32, (i) => i + 1)); // Mock 32-byte key
      _aesKeyStatus = AesKeyStatus.set;
      print('✓ AES key set: ${_aesKey!.length} bytes');
      
      // Test data encryption/decryption
      print('3. Testing BLE data format...');
      final testData = ['admin', 'user123', 'password', '2', '1', '0'];
      
      for (final data in testData) {
        final encrypted = prepareBLEData(data);
        final decrypted = decryptBLEData(encrypted);
        
        if (decrypted != data) {
          print('❌ Failed for "$data": got "$decrypted"');
          return false;
        }
        print('✓ "$data" -> ${encrypted.length} bytes -> "$decrypted"');
      }
      
      print('\n✅ Complete integration test PASSED!');
      print('Ready for ESP32 communication.');
      return true;
      
    } catch (e) {
      print('❌ Integration test failed: $e');
      return false;
    }
  }

  // Debug method to print key information
  void debugKeyInfo() {
    print('\n=== Debug Key Information ===');
    print('AES Key Status: $_aesKeyStatus');
    if (_aesKey != null) {
      print('AES Key Size: ${_aesKey!.length} bytes');
      print('AES Key: ${_aesKey!.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    }
    print('Fixed IV: ${_fixedIV.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');
    print('RSA Key Modulus Size: ${rsaKeyPair.publicKey.modulus!.bitLength} bits');
  }
  */

}