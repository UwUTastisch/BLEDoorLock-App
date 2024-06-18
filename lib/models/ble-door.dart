//Model that knows Lock-Id, Password and Name of the user

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

class BleDoor {
  UUID lockId;
  String lockName;
  String userName;
  String password;
  bool isAdmin;

  BleDoor({required this.lockId, required this.lockName, required this.userName , required this.password, this.isAdmin = false});

  Map<String, dynamic> toJson() {
    return {
      'lockId': lockId.toString(),
      'password': password,
      'userName': userName,
      'lockName': lockName,
      'isAdmin': isAdmin
    };
  }

  static BleDoor fromJson(Map<String, dynamic> json) {
    return BleDoor(
      lockId: UUID.fromString(json['lockId']),
      lockName: json['lockName'],
      userName: json['userName'],
      password: json['password'],
      isAdmin: json['isAdmin'],
    );
  }
}