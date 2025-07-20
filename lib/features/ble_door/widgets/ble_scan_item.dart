// lib/features/ble_door/widgets/ble_scan_item.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/ble_door.dart';

class BleScanItem extends StatelessWidget {
  final ScanResult result;

  const BleScanItem({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final id = result.device.remoteId.toString();
    var name = result.device.platformName;
    if (name.isEmpty) name = result.advertisementData.localName;
    if (name.isEmpty) name = result.device.advName;
    if (name.isEmpty) name = result.device.name;
    if (name.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        Text('Name -> $name\nUUID -> $id\nRSSI -> ${result.rssi}'),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () {
            final stub = BleDoor(
              peripheralMacAddress: id,
              lockName: name,
              userName: '',
              password: '',
            );
            Clipboard.setData(
              ClipboardData(text: jsonEncode(stub.toJson())),
            );
          },
          child: const Text('Copy ID'),
        ),
      ],
    );
  }
}
