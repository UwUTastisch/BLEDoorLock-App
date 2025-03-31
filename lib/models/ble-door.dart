//Model that knows Lock-Id, Password and Name of the user

import 'dart:ffi';

import 'package:flutter/material.dart';

class BleDoor {
  String peripheralMacAddress;
  String lockName;
  String userName;
  final String password;
  bool isAdmin;
  Color? color;

  BleDoor({required this.peripheralMacAddress, required this.lockName, required this.userName , required this.password, this.isAdmin = false, this.color});

  Map<String, dynamic> toJson() {
    return {
      'peripheralMacAddress': peripheralMacAddress.toString(),
      'password': password,
      'userName': userName,
      'lockName': lockName,
      'isAdmin': isAdmin,
      'color' : color?.g
    };
  }

  static BleDoor fromJson(Map<String, dynamic> json) {
    return BleDoor(
      peripheralMacAddress: json['peripheralMacAddress'],
      lockName: json['lockName'],
      userName: json['userName'],
      password: json['password'],
      isAdmin: json['isAdmin'],
      color: json['color'] != null ? Color(json['color'] as int) : null,  // Convert the integer back to a Color object
    );
  }
}