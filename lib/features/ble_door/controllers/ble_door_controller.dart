// lib/features/ble_door/controllers/ble_door_controller.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../storage/ble_door_storage.dart';
import '../../../utils/dialogs.dart';
import '../models/ble_door.dart';
import '../services/ble_service.dart';
import '../widgets/ble_device_list.dart';
import 'package:permission_handler/permission_handler.dart';

class BleDoorController {
  final ValueNotifier<List<BleDoor>> bleDoors = ValueNotifier([]);
  late final ValueNotifier<Map<String, ScanResult>> devices = ValueNotifier({});
  final ValueNotifier<bool> showAllBLEDevices = ValueNotifier(false);
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final ValueNotifier<BluetoothAdapterState> mState = ValueNotifier(BluetoothAdapterState.unknown);
  late StreamSubscription<BluetoothAdapterState> _stateChangedSubscription;
  final BleService _bleService = BleService();
  Timer? _scanTimer;
  /// Tracks in-flight open requests by door ID
  final Map<String, Future<void>?> statesController = {};

  BleDoorController() {
    _loadBleDoors();
    _checkPermissions();

    if (Platform.isAndroid) {
      FlutterBluePlus.turnOn(); // Request the user to turn on Bluetooth
    }
    _stateChangedSubscription =
        FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
          if (kDebugMode) {
            print("Bluetooth state changed: $state");
          }
          if (state == BluetoothAdapterState.on) {
            // Bluetooth is enabled, proceed with BLE operations
            if (_scanSubscription == null || _scanSubscription!.isPaused) {
              _startScan(); // Start scanning for devices
            }

          } else {
            if (Platform.isAndroid && state == BluetoothAdapterState.off) {
              FlutterBluePlus.turnOn(); // Request the user to turn on Bluetooth
            }
            // Bluetooth is off or in an error state, handle appropriately
          }
          mState.value = state;
        });

    _startScan();
  }

  Future<void> _checkPermissions() async {
    if(Platform.isAndroid) {
      if (await Permission.bluetoothScan
          .request()
          .isGranted &&
          await Permission.bluetoothConnect
              .request()
              .isGranted &&
          await Permission.location
              .request()
              .isGranted) {}
    }
  }

  Future<void> _loadBleDoors() async {
    bleDoors.value = await BleDoorStorage.loadBleDoors();
  }

  void _startScan() {
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (kDebugMode) {
        print("Scan results received: ${results.length} devices found");
      }
       var map = { for (var r in results) r.device.remoteId.toString(): r };
      // Filter devices where name == address
      //map.removeWhere((key, value) => value.device.platformName == value.device.remoteId.toString());
      //order the map by rssi in descending order
      map = Map.fromEntries(
        map.entries.toList()
          ..sort((a, b) => b.value.rssi.compareTo(a.value.rssi)),
      );
      devices.value = map;
      if (kDebugMode) {
        print("mState: ${mState.value} and Scan results updated: ${map.keys.join(', ')}");
      }
    });
    _scanTimer = Timer.periodic(
      const Duration(seconds: 10),
          (_) {
            _checkPermissions();
            if (kDebugMode) {
              print("Periodic scan started mState: ${mState.value}");
            }
            FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
          },
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
