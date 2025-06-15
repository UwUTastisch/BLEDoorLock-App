// lib/features/ble_door/controllers/ble_door_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../storage/ble_door_storage.dart';
import '../../../utils/dialogs.dart';
import '../models/ble_door.dart';
import '../services/ble_service.dart';
import '../widgets/ble_device_list.dart';

class BleDoorController {
  final ValueNotifier<List<BleDoor>> bleDoors = ValueNotifier([]);
  final ValueNotifier<Map<String, ScanResult>> devices = ValueNotifier({});
  final ValueNotifier<bool> showAllBLEDevices = ValueNotifier(false);

  final BleService _bleService = BleService();
  Timer? _scanTimer;

  /// Tracks in-flight open requests by door ID
  final Map<String, Future<void>?> statesController = {};

  BleDoorController() {
    _loadBleDoors();
    _startScan();
  }

  Future<void> _loadBleDoors() async {
    bleDoors.value = await BleDoorStorage.loadBleDoors();
  }

  void _startScan() {
    FlutterBluePlus.scanResults.listen((results) {
      final map = { for (var r in results) r.device.id.id: r };
      devices.value = map;
    });
    _scanTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) => FlutterBluePlus.startScan(timeout: const Duration(seconds: 25)),
    );
  }

  void toggleShowAllDevices() {
    showAllBLEDevices.value = !showAllBLEDevices.value;
  }

  void showAddOpenerDialog(BuildContext ctx) =>
      Dialogs.showAddOpener(ctx, this);

  void showAdminMenu(BuildContext ctx, BleDoor door) =>
      Dialogs.showAdminMenu(ctx, this, door);

  void showEditDoorDialog(BuildContext ctx, BleDoor door) =>
      Dialogs.showEditDoorDialog(ctx, this, door);

  void showAddUserDialog(BuildContext ctx, BleDoor door) =>
      Dialogs.showAddUserDialog(ctx, this, door);

  void showConfirmRemoveDialog(BuildContext ctx, BleDoor door) =>
      Dialogs.showConfirmRemoveDialog(ctx, this, door);

  Future<void> addBleDoor(BleDoor door) async {
    await BleDoorStorage.addBleDoor(door);
    await _loadBleDoors();
  }

  Future<void> updateBleDoor(BleDoor door) async {
    await BleDoorStorage.updateBleDoor(door);
    await _loadBleDoors();
  }

  Future<void> removeBleDoor(BleDoor door) async {
    await BleDoorStorage.removeBleDoor(door);
    await _loadBleDoors();
  }


  bool isConnecting(BleDoor door) =>
      statesController[door.peripheralMacAddress] != null;


  Future<void> connectAndOpenDoor(BuildContext ctx, BleDoor door) async {
    final id = door.peripheralMacAddress;
    if (isConnecting(door)) return;
    final scan = devices.value[id];
    if (scan == null) {
      Dialogs.showErrorDialog(ctx, 'Device not in range');
      return;
    }

    // wrap the BLE call in a tracked Future
    final f = _bleService.connectAndOpen(scan.device, door)
        .timeout(const Duration(seconds: 10), onTimeout: () {
      throw Exception('Timeout while connecting to ${door.lockName}');
    })
        .then((_) {
      Dialogs.showSuccessDialog(ctx, 'Door opened successfully');
    })
        .catchError((e) {
      Dialogs.showErrorDialog(ctx, e);
    })
        .whenComplete(() {
      statesController[id] = null;
    });

    statesController[id] = f;
    await f;
  }

  Future<void> connectAndAddUser(BuildContext ctx,
      BleDoor admin, BleDoor newUser) async {
    final scan = devices.value[admin.peripheralMacAddress];
    if (scan == null) {
      Dialogs.showErrorDialog(ctx, 'Device not in range');
      return;
    }
    try {
      await _bleService.addUser(scan.device, admin, newUser);
      Dialogs.showSuccessDialog(ctx, 'User added successfully');
    } catch (e) {
      Dialogs.showErrorDialog(ctx, e);
    }
  }

  Widget buildDeviceList() =>
      BleDeviceList(controller: this);

  void dispose() {
    _scanTimer?.cancel();
    bleDoors.dispose();
    devices.dispose();
    showAllBLEDevices.dispose();
  }

}
