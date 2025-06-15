// lib/features/ble_door/widgets/ble_device_list.dart
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../controllers/ble_door_controller.dart';
import '../models/ble_door.dart';
import 'ble_door_card.dart';
import 'ble_scan_item.dart';

class BleDeviceList extends StatelessWidget {
  final BleDoorController controller;

  const BleDeviceList({Key? key, required this.controller})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.showAllBLEDevices,
      builder: (ctx, showAll, _) {
        return ValueListenableBuilder<List<BleDoor>>(
          valueListenable: controller.bleDoors,
          builder: (ctx, doors, _) {
            return ValueListenableBuilder<Map<String, ScanResult>>(
              valueListenable: controller.devices,
              builder: (ctx, devices, _) {
                final doorCards = doors.map((door) {
                  final near = devices.containsKey(door.peripheralMacAddress);
                  return BleDoorCard(
                    door: door,
                    isNearBy: near,
                    isConnecting: controller.isConnecting(door),
                    onOpen: () =>
                        controller.connectAndOpenDoor(context, door),
                    onShowAdminMenu: () =>
                        controller.showAdminMenu(context, door),
                  );
                }).toList();

                final scanWidgets = showAll
                    ? devices.values
                    .map((r) => BleScanItem(result: r))
                    .toList()
                    : <Widget>[];

                final List<Widget> allItems = [...doorCards, if (controller.showAllBLEDevices.value)
                  Text("BLE-Devices in reach: ${scanWidgets.length}"),
                  if (controller.showAllBLEDevices.value) ...scanWidgets];

                return ListView.separated(
                  itemCount: allItems.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (_, i) => allItems[i],
                );
              },
            );
          },
        );
      },
    );
  }
}

