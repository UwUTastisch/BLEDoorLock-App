import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:ble_doorlock_opener/storage/ble-door-storage.dart';
import 'package:ble_doorlock_opener/utils.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'custom-theme.dart';
import 'models/ble-door.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

Future<void> checkPermissions() async {
  if (await Permission.bluetoothScan.request().isGranted &&
      await Permission.bluetoothConnect.request().isGranted &&
      await Permission.location.request().isGranted) {
  } 
}

bool get enablePeripheral => !Platform.isLinux && !Platform.isWindows;

final ValueNotifier<bool> showAllBLEDevices = ValueNotifier(false);
// UUIDs for the BLE services
final Guid uuidUserService = Guid("2ff7c135-5010-497b-a054-cea3984c7cc9");
final Guid uuidAdminService = Guid("be527357-c722-4367-aac3-bddef6a6f6e2");
final Guid uuidCryptoService = Guid("1c970e06-8094-4b83-a54b-a465396ebaa8");

// UUIDs for the BLE characteristics for the door opener
final Guid uuidUserCharacteristic =
    Guid("5d3932fa-2901-4b6b-9f41-7720976a85d4");
final Guid uuidPassCharacteristic =
    Guid("dd16cad0-a66a-402f-9183-201c20753647");
final Guid uuidLockStateCharacteristic =
    Guid("05c5653a-7279-406c-9f9e-df72aa99ca2d");

// UUID for the BLE characteristics for encryption
final Guid uuidKeyCharacteristic = Guid("df5ba2aa-c90c-4c90-8c5f-059f62ff51a1");

// UUIDs for the BLE characteristics for adding a user as admin
final Guid uuidAdminCharacteristic =
    Guid("68f2b041-dc1e-42af-af96-773a2386b08b");
final Guid uuidAdminPassCharacteristic =
    Guid("394e8790-109b-47c0-aa67-1aa61c02188b");
final Guid uuidAddUserCharacteristic =
    Guid("92acb83b-ff02-43ec-9adb-16755eb8ce9b");
final Guid uuidAddPassCharacteristic =
    Guid("8de8c0c0-0568-40a0-a52b-520a6e772503");
final Guid uuidAdminActionCharacteristic =
    Guid("b1d86fdf-7d5d-49b7-8da7-b02bd53bdb0a");

/*
  BluetoothCharacteristic UserCharacteristic;
  BluetoothCharacteristic PassCharacteristic;
  BluetoothCharacteristic LockStateCharacteristic;

  BluetoothCharacteristic KeyCharacteristic;

  BluetoothCharacteristic AdminCharacteristic;
  BluetoothCharacteristic AdminPassCharacteristic;
  BluetoothCharacteristic AddUserCharacteristic;
  BluetoothCharacteristic AddPassCharacteristic;
  BluetoothCharacteristic AdminActionCharacteristic;
  */

late final PackageInfo packageInfo;

void main() {
  runZonedGuarded(onStartUp, onCrashed);
}

class DeviceNotifier extends ValueNotifier<Map<String, ScanResult>> {
  DeviceNotifier() : super({});

  void addItem(String sKey, ScanResult srValue) {
    value = {...value, sKey: srValue}; // Neue Map zuweisen
    notifyListeners(); // Listener benachrichtigen
  }

  void removeItem(String key) {
    if (value.containsKey(key)) {
      value = {...value}..remove(key);
      notifyListeners();
    }
  }

  void cleanUpDevices(List<String> activeDeviceIds) {
    Map<String, ScanResult> newMap = {};

    // Behalte nur Geräte, die im aktuellen Scan sind
    value.forEach((key, scanResult) {
      if (activeDeviceIds.contains(key)) {
        newMap[key] = scanResult;
      }
    });

    // Wenn sich etwas geändert hat, die neue Map setzen
    if (!mapEquals(value, newMap)) {
      value = newMap;
      notifyListeners();
    }
  }
}

void onStartUp() async {
  Logger.root.onRecord.listen(onLogRecord);
  // hierarchicalLoggingEnabled = true;
  // CentralManager.instance.logLevel = Level.WARNING;
  WidgetsFlutterBinding.ensureInitialized();
  packageInfo = await PackageInfo.fromPlatform();
  runApp(const MyApp());
}

void onCrashed(Object error, StackTrace stackTrace) {
  Logger.root.shout('App crashed.', error, stackTrace);
}

void onLogRecord(LogRecord record) {
  log(
    record.message,
    time: record.time,
    sequenceNumber: record.sequenceNumber,
    level: record.level.value,
    name: record.loggerName,
    zone: record.zone,
    error: record.error,
    stackTrace: record.stackTrace,
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool isDarkMode = true;

  @override
  void initState() {
    super.initState();
    // Detect the current system brightness and set the theme accordingly
    final Brightness brightness =
        WidgetsBinding.instance.window.platformBrightness;
    isDarkMode = brightness == Brightness.dark;
  }

  void toggleDarkMode() {
    setState(() {
      isDarkMode = !isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE-Door-Opener',
      theme: CustomTheme.lightTheme,
      darkTheme: CustomTheme.darkTheme,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: BodyView(toggleDarkMode: toggleDarkMode),
    );
  }
}

class BodyView extends StatefulWidget {
  final Function toggleDarkMode;

  const BodyView({super.key, required this.toggleDarkMode});

  @override
  State<BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<BodyView> {
  late final ValueNotifier<BluetoothAdapterState> mState;
  late final StreamSubscription stateChangedSubscription;
  late final ValueNotifier<List<BleDoor>> bleDoors;
  late final DeviceNotifier devices;
  late final StreamSubscription _scanSubscription;
  Map<String, bool> expansionState = {};
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      FlutterBluePlus.turnOn(); // Request the user to turn on Bluetooth
    }
    mState = ValueNotifier(BluetoothAdapterState.unknown);
    devices = DeviceNotifier();
    stateChangedSubscription =
        FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (kDebugMode) {
        print("Bluetooth state changed: $state");
      }
      if (state == BluetoothAdapterState.on) {
        // Bluetooth is enabled, proceed with BLE operations
      } else {
        if (Platform.isAndroid && state == BluetoothAdapterState.off) {
          FlutterBluePlus.turnOn(); // Request the user to turn on Bluetooth
        }
        // Bluetooth is off or in an error state, handle appropriately
      }
      mState.value = state;
    });
    bleDoors = ValueNotifier([]);
    _initialize();
  }

  void _initialize() async {
    List<BleDoor> loadedBleDoors = await BleDoorStorage.loadBleDoors();
    bleDoors.value = loadedBleDoors;
    startScan();
  }

  void startScan() {
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      List<String> foundDevices = [];
      for (ScanResult result in results) {
        String macAddress = result.device.remoteId.toString();

        // Falls das Gerät noch nicht in der Liste ist, hinzufügen
        if (!devices.value.containsKey(macAddress)) {
          foundDevices.add(macAddress);
          devices.addItem(macAddress, result);
          if (kDebugMode) {
            print(
                "Neues Gerät gefunden: $macAddress - ${result.device.platformName}");
          }
        }
      }
      // Entferne Geräte, die nicht mehr im Scan sind
      devices.cleanUpDevices(foundDevices);
    });

    // Starte den Scan mit automatischen Updates
    Timer.periodic(const Duration(seconds: 10), (timer) {
      checkPermissions();
      FlutterBluePlus.startScan(
          timeout: const Duration(
              seconds: 10)); // Geräte werden kontinuierlich aktualisiert
    });
  }

  Widget buildShowAll(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: showAllBLEDevices,
      builder: (context, showble, child) => ValueListenableBuilder(
        valueListenable: devices,
        builder: (context, eventargs, child) {
          List<Widget> availableBLEDevices = bleListeningWidgets(
            context,
          );
          List<Widget> widgets = [
            for (var bleDoor in bleDoors.value) bleDoorWidget(context, bleDoor),
            if (showble)
              Text("BLE-Devices in reach: ${availableBLEDevices.length}"),
            if (showble) ...availableBLEDevices,
          ];
          return ListView.separated(
            itemBuilder: (BuildContext context, int index) {
              return widgets[index];
            },
            separatorBuilder: (BuildContext context, int index) {
              return const Divider(height: 0.0);
            },
            itemCount: widgets.length,
          );
        },
      ),
    );
  }

  List<Widget> bleListeningWidgets(BuildContext context) {
    List<Widget> widgets = [];

    for (ScanResult r in devices.value.values.toList()) {
      final uuid = r.device.remoteId.toString();
      final rssi = r.rssi;
      final name = r.device.platformName;
      widgets.add(
        Column(
          children: [
            Text(
              "Name -> $name, \n UUID -> $uuid, \n RSSI -> $rssi",
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange, // foreground
              ),
              onPressed: () {
                BleDoor bleDoor = BleDoor(
                  peripheralMacAddress: "00:00:00:00:00:00",
                  lockName: name,
                  password: "spr",
                  userName: "spr",
                );
                String bleDoorJson = jsonEncode(bleDoor.toJson());
                Clipboard.setData(ClipboardData(text: bleDoorJson));
              },
              child: const Text("Copy ID"),
            ),
          ],
        ),
      );
    }
    return widgets;
  }

  Map<BleDoor, Future<void>?> statesController = {};

  bool isConnectingAndOpening(BleDoor bleDoor) {
    return statesController[bleDoor] != null;
  }

  Widget bleDoorWidget(
    BuildContext context,
    BleDoor bleDoor, {
    bool isInteractable = true,
  }) {
    final String key = BleDoor(
      peripheralMacAddress: bleDoor.peripheralMacAddress,
      lockName: bleDoor.lockName,
      userName: bleDoor.userName,
      password: bleDoor.password,
      isAdmin: bleDoor.isAdmin,
      color: null,
    ).toJson().toString();
    expansionState.putIfAbsent(key, () => false);
    bool isExpanded = expansionState[key]!;

    bool isConnectingAndOpening() {
      return this.isConnectingAndOpening(bleDoor);
    }

    Future<void> connectAndOpenBleDoor() async {
      if (isConnectingAndOpening()) {
        return;
      }
      Duration timeout = const Duration(seconds: 10);

      Future<void> f = this.connectAndOpenBleDoor(context, bleDoor).timeout(
        timeout,
        onTimeout: () {
          errorDialog(
            context,
            "Timeout while connecting to ${bleDoor.lockName}",
          );
          statesController[bleDoor] = null;
        },
      ).catchError((error) {
        errorDialog(context, error);
        statesController[bleDoor] = null;
      }).then((value) {
        statesController[bleDoor] = null;
      });
      statesController[bleDoor] = f;
      await f;
    }

    return GestureDetector(
      onLongPress: (isInteractable)
          ? () {
              showAdminMenu(context, bleDoor);
            }
          : null,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15.0),
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: bleDoor.color ?? Colors.black12,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(15.0),
                  topRight: const Radius.circular(15.0),
                  bottomLeft:
                      isExpanded ? Radius.zero : const Radius.circular(15.0),
                  bottomRight:
                      isExpanded ? Radius.zero : const Radius.circular(15.0),
                ),
              ),
              child: ListTile(
                title: Text(
                  bleDoor.lockName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: doorIsNearBy(bleDoor) || !isInteractable
                        ? Colors.green
                        : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: (isInteractable && !isConnectingAndOpening())
                      ? () {
                          if (kDebugMode) {
                            print(
                              "Opening door ${bleDoor.lockName}, $isInteractable and ${!isConnectingAndOpening()}",
                            );
                          }
                          connectAndOpenBleDoor();
                        }
                      : null,
                  child: const Text("Open"),
                ),
                onTap: () {
                  setState(() {
                    expansionState[key] = !isExpanded;
                  });
                },
              ),
            ),
            isExpanded
                ? Container(
                    decoration: BoxDecoration(
                      color: adjustBrightness(
                        bleDoor.color ?? Colors.black12,
                        Theme.of(context).brightness == Brightness.dark
                            ? -0.2
                            : 0.2,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(15.0),
                        bottomRight: Radius.circular(15.0),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Info:",
                          style: TextStyle(color: Colors.black),
                        ),
                        Text("Lock ID: ${bleDoor.peripheralMacAddress}"),
                        Text("User: ${bleDoor.userName}"),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  void showAdminMenu(BuildContext context, BleDoor bleDoor) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                'Settings: ${bleDoor.lockName}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const Divider(height: 0, thickness: 2),
            if (bleDoor.isAdmin)
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add Door User'),
                onTap: () {
                  Navigator.of(context).pop();
                  addUserDialog1(context, bleDoor);
                },
              ),
            if (bleDoor.isAdmin) const Divider(thickness: 2, height: 0),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Door'),
              onTap: () {
                Navigator.of(context).pop();
                editDoorDialog(context, bleDoor);
              },
            ),
            const Divider(thickness: 2, height: 0),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Door'),
              onTap: () {
                Navigator.of(context).pop();
                sureYouWantToRemoveDialog(context, bleDoor);
              },
            ),
            // Add more admin options here
          ],
        );
      },
    );
  }

  void editDoorDialog(BuildContext context, BleDoor bleDoor) {
    ValueNotifier<Color?> color = ValueNotifier<Color?>(bleDoor.color);
    TextEditingController controller = TextEditingController(
      text: bleDoor.lockName,
    );
    ValueNotifier<bool> isValidDoorNameBool = ValueNotifier<bool>(
      isValidUsername(controller.text),
    );

    controller.addListener(() {
      isValidDoorNameBool.value = isValidUsername(controller.text);
    });

    BleDoor previewBuild() {
      return BleDoor(
        peripheralMacAddress: bleDoor.peripheralMacAddress,
        lockName: controller.text,
        userName: bleDoor.userName,
        password: bleDoor.password,
        isAdmin: bleDoor.isAdmin,
        color: color.value,
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return Scaffold(
          appBar: AppBar(title: const Text('Edit Door')),
          body: Column(
            children: [
              //Colorpicker
              const SizedBox(height: 20),
              Text("Color", style: Theme.of(context).textTheme.titleLarge),
              ColorPicker(color: color),
              const SizedBox(height: 20),
              //Name
              Text("Door name", style: Theme.of(context).textTheme.titleLarge),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15),
                color: Colors.black12,
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: "Enter door name",
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text("Preview", style: Theme.of(context).textTheme.titleLarge),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, bleName, child) => ValueListenableBuilder(
                  valueListenable: color,
                  builder: (context, color, child) {
                    return bleDoorWidget(
                      context,
                      previewBuild(),
                      isInteractable: false,
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              ValueListenableBuilder(
                valueListenable: isValidDoorNameBool,
                builder: (context, value, child) => ElevatedButton(
                  onPressed: value
                      ? () async {
                          //remove old door
                          await BleDoorStorage.updateBleDoor(
                            previewBuild(),
                          );
                          await BleDoorStorage.loadBleDoors().then((
                            value,
                          ) {
                            bleDoors.value = value;
                          });
                          Navigator.of(context).pop();
                        }
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: (isValidDoorNameBool.value)
                        ? Colors.green
                        : Colors.grey, // text color
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void addUserDialog1(BuildContext context, BleDoor bleDoor) {
    TextEditingController controller = TextEditingController();
    ValueNotifier<bool> isValidUserNameBool = ValueNotifier<bool>(false);

    controller.addListener(() {
      isValidUserNameBool.value = isValidUsername(controller.text);
    });

    showDialog(
      context: context,
      builder: (context) {
        return Scaffold(
          appBar: AppBar(title: const Text('Add Door User')),
          body: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(15),
                child: TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: "Enter user name",
                  ),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: isValidUserNameBool,
                builder: (context, value, child) => ElevatedButton(
                  onPressed: value
                      ? () {
                          addUserDialog2(
                            context,
                            bleDoor,
                            controller.text,
                          );
                        }
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: (isValidUserNameBool.value)
                        ? Colors.green
                        : Colors.grey, // text color
                  ),
                  child: const Text('Next'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void addUserDialog2(BuildContext context, BleDoor bleDoor, String username) {
    //gen a new BleDoor object and show the json as qrCode
    BleDoor newBleDoor = BleDoor(
      peripheralMacAddress: bleDoor.peripheralMacAddress,
      lockName: bleDoor.lockName,
      password: generateRandomString(32),
      userName: username,
      isAdmin: false,
    );

    String bleDoorJson = jsonEncode(newBleDoor.toJson());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Scaffold(
          appBar: AppBar(title: const Text('Add Door User')),
          body: Column(
            children: [
              Text("User: $username"),
              QrImageView(data: bleDoorJson, version: QrVersions.auto),
              ElevatedButton(
                onPressed: () async {
                  await connectAndAddUser(context, bleDoor, newBleDoor);
                  Navigator.of(context).pop();
                },
                child: const Text("Add User"),
              ),
            ],
          ),
        );
      },
    );
  }

  bool doorIsNearBy(BleDoor bleDoor) {
    return devices.value.containsKey(bleDoor.peripheralMacAddress);
  }

  /// Stoppt das Scannen
  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription.cancel();
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      if (kDebugMode) {
        print("Verbunden mit ${device.remoteId}");
      }
    } catch (e) {
      if (kDebugMode) {
        print("Fehler beim Verbinden: $e");
      }
    }
  }

  Future<void> connectAndOpenBleDoor(
    BuildContext context,
    BleDoor bleDoor,
  ) async {
    try {
      BluetoothCharacteristic? userCharacteristic;
      BluetoothCharacteristic? passCharacteristic;
      BluetoothCharacteristic? lockStateCharacteristic;

      //BluetoothCharacteristic KeyCharacteristic;

      if (devices.value.containsKey(bleDoor.peripheralMacAddress)) {
        BluetoothDevice d = devices.value[bleDoor.peripheralMacAddress]!.device;
        List<BluetoothService> services = await d.discoverServices();
        for (BluetoothService service in services) {
          if (service.uuid == uuidUserService) {
            for (BluetoothCharacteristic characteristic
                in service.characteristics) {
              if (characteristic.uuid == uuidUserCharacteristic) {
                userCharacteristic = characteristic;
              } else if (characteristic.uuid == uuidPassCharacteristic) {
                passCharacteristic = characteristic;
              } else if (characteristic.uuid == uuidLockStateCharacteristic) {
                lockStateCharacteristic = characteristic;
              }
            }
          } else if (service.uuid == uuidCryptoService) {
            for (BluetoothCharacteristic characteristic
                in service.characteristics) {
              if (characteristic.uuid == uuidKeyCharacteristic) {
                //KeyCharacteristic = characteristic;
              }
            }
          }
        }
        await userCharacteristic!
            .write(Uint8List.fromList(utf8.encode(bleDoor.userName)));

        await passCharacteristic!
            .write(Uint8List.fromList(utf8.encode(bleDoor.password)));

        await lockStateCharacteristic!
            .write(Uint8List.fromList(utf8.encode("2")));
      }
    } catch (e) {
      errorDialog(context, e);
      rethrow;
    }
  }

  Future<void> connectAndAddUser(
    BuildContext context,
    BleDoor admin,
    BleDoor newUser,
  ) async {
    try {
      /*peripheral = await BluetoothLowEnergy.instance.connect(bleDoor.peripheralMacAddress);
      
      // Get service and the characteristics
      List<Service> services = await peripheral!.discoverServices();
      for (Service service in services) {
        if (service.uuid == uuidAdminService) {
          for (Characteristic characteristic in service.characteristics) {
            if (characteristic.uuid == uuidAdminCharacteristic) {
              AdminCharacteristic = characteristic;
            } else if (characteristic.uuid == uuidAdminPassCharacteristic) {
              AdminPassCharacteristic = characteristic;
            } else if (characteristic.uuid == uuidAddUserCharacteristic) {
              AddUserCharacteristic = characteristic;
            } else if (characteristic.uuid == uuidAddPassCharacteristic) {
              AddPassCharacteristic = characteristic;
            } else if (characteristic.uuid == uuidAdminActionCharacteristic) {
              AdminActionCharacteristic = characteristic;
            }
          }
        } else if (service.uuid == uuidCryptoService) {
          for (Characteristic characteristic in service.characteristics) {
            if (characteristic.uuid == uuidKeyCharacteristic) {
              KeyCharacteristic = characteristic;
            }
          }
        }
      }
      await AdminCharacteristic.write(Uint8List.fromList(utf8.encode(bleDoor.userName));
      await AdminPassCharacteristic.write(Uint8List.fromList(utf8.encode(bleDoor.password));

      await AddUserCharacteristic.write(Uint8List.fromList(utf8.encode(newUser.userName));
      await AddPassCharacteristic.write(Uint8List.fromList(utf8.encode(newUser.password));

      await AdminActionCharacteristic.write(Uint8List.fromList(utf8.encode("1"));
      */
    } catch (error) {
      errorDialog(context, error);
      rethrow;
    }
  }

  void addOpenerDialog(BuildContext context) {
    TextEditingController controller = TextEditingController();
    ValueNotifier<bool> isJsonValid = ValueNotifier<bool>(false);

    void checkJsonValidity(String json) {
      try {
        BleDoor.fromJson(jsonDecode(json));
        isJsonValid.value = true;
      } catch (e) {
        isJsonValid.value = false;
      }
    }

    controller.addListener(() {
      checkJsonValidity(controller.text);
    });

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Add Door Opener by QR-Code or JSON Payload'),
          ),
          body: qrCodeScan(controller),
          floatingActionButton: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "Enter JSON Payload here",
              ),
            ),
          ),
          bottomNavigationBar: BottomAppBar(
            child: Row(
              children: [
                const Expanded(child: SizedBox(width: 10)),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red, // text color
                  ),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 10),
                ValueListenableBuilder(
                  valueListenable: isJsonValid,
                  builder: (context, value, child) {
                    return TextButton(
                      onPressed: value
                          ? () async {
                              Navigator.of(context).pop();
                              //save opener
                              String bleDoorJson = controller.text;
                              BleDoor deserializedBleDoor = BleDoor.fromJson(
                                jsonDecode(bleDoorJson),
                              );
                              await BleDoorStorage.addBleDoor(
                                deserializedBleDoor,
                              );
                              await BleDoorStorage.loadBleDoors().then((
                                value,
                              ) {
                                bleDoors.value = value;
                              });
                              successAddDoorDialog(context);
                            }
                          : null, // Disable the button if the JSON is not valid
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: (isJsonValid.value)
                            ? Colors.green
                            : Colors.grey, // text color
                      ),
                      child: const Text('Add Opener'),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget qrCodeScan(TextEditingController controller) {
    var qrCodeDartScanController = QRCodeDartScanController();
    return QRCodeDartScanView(
      typeCamera: TypeCamera.back,
      controller: qrCodeDartScanController,
      typeScan: TypeScan.live,
      onCapture: (Result result) {
        controller.text = result.text;
      },
    );
  }

  void successAddDoorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Success'),
          content: const Text('The door was added successfully'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void successDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Success'),
          content: const Text('The door was opened successfully'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void errorDialog(BuildContext context, Object error) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text('Error: $error'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

//Ist der scheiß oben links "Door Opener^(vX.X.X)"
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black
            : Theme.of(context).colorScheme.primary,
        title: GestureDetector(
          //Ist der scheiß oben links "Door Opener^(vX.X.X)"
          onLongPress: () => showAllBLEDevices.value = !showAllBLEDevices.value,
          child: Row(
            children: [
              const Text("Door Opener "),
              Text(
                "v${packageInfo.version}",
                style: const TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              widget.toggleDarkMode();
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              addOpenerDialog(context);
            },
            child: const Text("Add Opener"),
          ),
        ],
      ),
      body: buildShowAll(context),
    );
  }

  void sureYouWantToRemoveDialog(BuildContext context, BleDoor bleDoor) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Are you sure?'),
          content: const Text('Do you really want to remove this door?'),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await BleDoorStorage.removeBleDoor(bleDoor);
                await BleDoorStorage.loadBleDoors().then((value) {
                  bleDoors.value = value;
                });
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.red,
              ),
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.green,
              ),
              child: const Text('No'),
            ),
          ],
        );
      },
    );
  }
}

class ColorPicker extends StatelessWidget {
  final ValueNotifier<Color?> color;

  const ColorPicker({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: color,
      builder: (context, color, child) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var c in [
                Colors.red,
                Colors.green,
                Colors.blue,
                Colors.yellow,
                Colors.purple,
                Colors.orange,
                Colors.pink,
                Colors.teal,
                Colors.brown,
                Colors.grey,
                Colors.black,
                Colors.white,
              ])
                GestureDetector(
                  onTap: () {
                    this.color.value = c;
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      border: Border.all(
                        color: this.color.value == c
                            ? Colors.black
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    margin: const EdgeInsets.all(5),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
