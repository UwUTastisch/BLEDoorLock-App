import 'dart:typed_data';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/asymmetric/api.dart';
import 'package:pointycastle/asymmetric/oaep.dart';
import 'package:pointycastle/asymmetric/rsa.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';
import 'dart:convert';

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

  // Public key im PEM-Format
  String get publicKeyPem {
    final modulus = rsaKeyPair.publicKey.modulus!;
    final exponent = rsaKeyPair.publicKey.exponent!;
    return '-----BEGIN PUBLIC KEY-----\n'
        '${_encodeBigInt(modulus)}\n'
        '${_encodeBigInt(exponent)}\n'
        '-----END PUBLIC KEY-----';
  }

  AesKeyStatus get aesKeyStatus => _aesKeyStatus;

  // Entschlüsselt den AES-Schlüssel
  bool setEncryptedAesKey(Uint8List encryptedAesKey) {
    if (_aesKeyStatus == AesKeyStatus.set) {
      //compare with previous key
      
      _aesKeyStatus = AesKeyStatus.expired;
      return false;
    }
    if (_aesKeyStatus == AesKeyStatus.expired) {;
      throw StateError('AES key is expired, please refresh it');
    }
    final oaep = AsymmetricBlockCipher('RSA/ECB/OAEPPadding') as OAEPEncoding;

    oaep.init(false, PrivateKeyParameter(rsaKeyPair.privateKey));
    _aesKey = oaep.process(encryptedAesKey);
    return true;
  }


  // Verschlüsselt Daten mit AES-GCM
  Uint8List encryptAesData(Uint8List plaintext) {
    if (_aesKey == null) throw StateError('AES key not set');

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
        KeyParameter(_aesKey!),
        128,
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
        128,
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
    final keyParams = RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64);
    final random = FortunaRandom()..seed(KeyParameter(Uint8List(32)));
    final params = ParametersWithRandom(keyParams, random);

    final keyGen = RSAKeyGenerator();
    keyGen.init(params);

    return keyGen.generateKeyPair();
  }

}