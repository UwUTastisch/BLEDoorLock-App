import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:ble_doorlock_opener/storage/ble-door-storage.dart';
import 'package:ble_doorlock_opener/utils.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'custom-theme.dart';
import 'models/ble-door.dart';
import 'package:logging/logging.dart';

bool get enablePeripheral => !Platform.isLinux && !Platform.isWindows;

final ValueNotifier<bool> showAllBLEDevices = ValueNotifier(false);

// UUIDs for the BLE characteristics for the door opener
final uuidUserCharacteristic =
    UUID.fromString("5d3932fa-2901-4b6b-9f41-7720976a85d4");
final uuidPassCharacteristic =
    UUID.fromString("dd16cad0-a66a-402f-9183-201c20753647");
final uuidLockStateCharacteristic =
    UUID.fromString("05c5653a-7279-406c-9f9e-df72aa99ca2d");

// UUIDs for the BLE characteristics for adding a user as admin
final uuidAdminCharacteristic =
    UUID.fromString("68f2b041-dc1e-42af-af96-773a2386b08b");
final uuidAdminPassCharacteristic =
    UUID.fromString("394e8790-109b-47c0-aa67-1aa61c02188b");
final uuidAddUserCharacteristic =
    UUID.fromString("92acb83b-ff02-43ec-9adb-16755eb8ce9b");
final uuidAddPassCharacteristic =
    UUID.fromString("8de8c0c0-0568-40a0-a52b-520a6e772503");
final uuidAdminActionCharacteristic =
    UUID.fromString("b1d86fdf-7d5d-49b7-8da7-b02bd53bdb0a");

late final PackageInfo packageInfo;

late final CentralManager centralManager;

void main() {
  runZonedGuarded(onStartUp, onCrashed);
}

void onStartUp() async {
  Logger.root.onRecord.listen(onLogRecord);
  // hierarchicalLoggingEnabled = true;
  // CentralManager.instance.logLevel = Level.WARNING;
  WidgetsFlutterBinding.ensureInitialized();
  centralManager = CentralManager();
  packageInfo = await PackageInfo.fromPlatform();
  runApp(const MyApp());
}

void onCrashed(Object error, StackTrace stackTrace) {
  Logger.root.shout('App crached.', error, stackTrace);
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
        WidgetsBinding.instance!.window.platformBrightness;
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
  late final ValueNotifier<bool> discovering;
  late final ValueNotifier<BluetoothLowEnergyState> state;
  late final ValueNotifier<List<DiscoveredEventArgs>> discoveredEventArgs;
  late final StreamSubscription stateChangedSubscription;
  late final StreamSubscription discoveredSubscription;
  late final ValueNotifier<List<BleDoor>> bleDoors;
  Map<String, bool> expansionState = {};

  @override
  void initState() {
    super.initState();
    state = ValueNotifier(BluetoothLowEnergyState.unknown);
    discovering = ValueNotifier(false);
    discoveredEventArgs = ValueNotifier([]);
    stateChangedSubscription =
        centralManager.stateChanged.listen((eventArgs) async {
      final state = eventArgs.state;
      if (kDebugMode) {
        print("Bluetooth state changed: $state");
      }
      if (Platform.isAndroid && state == BluetoothLowEnergyState.unauthorized) {
        await centralManager.authorize();
      }
      this.state.value = state;
    });
    discoveredSubscription = centralManager.discovered.listen(
      (eventArgs) async {
        final items = discoveredEventArgs.value;
        final i = items.indexWhere(
          (item) => item.peripheral == eventArgs.peripheral,
        );
        if (i < 0) {
          discoveredEventArgs.value = [...items, eventArgs];
        } else {
          items[i] = eventArgs;
          discoveredEventArgs.value = [...items];
        }
        if (Platform.isAndroid && state == BluetoothLowEnergyState.unauthorized) {
          await centralManager.authorize();
        }
      },

    );
    bleDoors = ValueNotifier([]);
    _initialize();
  }

  void _initialize() async {
    state.value = centralManager.state;
    List<BleDoor> loadedBleDoors = await BleDoorStorage.loadBleDoors();
    bleDoors.value = loadedBleDoors;

    startDiscovery();
  }

  Future<void> startDiscovery() async {
    discoveredEventArgs.value = [];
    await centralManager.startDiscovery();
    discovering.value = true;
  }

  Future<void> stopDiscovery() async {
    await centralManager.stopDiscovery();
    discovering.value = false;
  }

  Widget buildShowAll(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: showAllBLEDevices,
      builder: (context, showble, child) => ValueListenableBuilder(
        valueListenable: discoveredEventArgs,
        builder: (context, eventargs, child) {
          List<Widget> availableBLEDevices =
              bleListeningWidgets(context, discoveredEventArgs.value);
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
                return const Divider(
                  height: 0.0,
                );
              },
              itemCount: widgets.length);
        },
      ),
    );
  }

  List<Widget> bleListeningWidgets(
      BuildContext context, List<DiscoveredEventArgs> discoveredEventArgs) {
    List<Widget> widgets = [];

    for (var item in discoveredEventArgs) {
      final uuid = item.peripheral.uuid;
      final rssi = item.rssi;
      final advertisement = item.advertisement;
      final name = advertisement.name;
      if (advertisement.name == null) {
        continue;
      }
      widgets.add(Column(children: [
        Text(
            "Name -> $name, \n UUID -> $uuid, \n RSSI -> $rssi, \n Advertisement -> $advertisement"),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange // foreground
                ),
            onPressed: () {
              BleDoor bleDoor = BleDoor(
                  lockId: uuid,
                  lockName: name ?? "Unknown",
                  password: "spr",
                  userName: "spr");
              String bleDoorJson = jsonEncode(bleDoor.toJson());
              Clipboard.setData(ClipboardData(text: bleDoorJson));
            },
            child: const Text("Copy ID")),
      ]));
    }
    return widgets;
  }

  Map<BleDoor, Future<void>?> statesController = {};

  bool isConnectingAndOpening(BleDoor bleDoor) {
    return statesController[bleDoor] != null;
  }

  Widget bleDoorWidget(BuildContext context, BleDoor bleDoor,
      {bool isInteractable = true}) {
    final String key = BleDoor(
            lockId: bleDoor.lockId,
            lockName: bleDoor.lockName,
            userName: bleDoor.userName,
            password: bleDoor.password,
            isAdmin: bleDoor.isAdmin,
            color: null)
        .toJson()
        .toString();
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

      Future<void> f = this
          .connectAndOpenBleDoor(context, bleDoor)
          .timeout(timeout, onTimeout: () {
        errorDialog(context, "Timeout while connecting to ${bleDoor.lockName}");
        statesController[bleDoor] = null;
      }).catchError((error) {
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
                      color: Colors.white, fontWeight: FontWeight.bold),
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
                                "Opening door ${bleDoor.lockName}, $isInteractable and ${!isConnectingAndOpening()}");
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
                              : 0.2),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(15.0),
                        bottomRight: Radius.circular(15.0),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Info:",
                            style: TextStyle(color: Colors.black)),
                        Text("Lock ID: ${bleDoor.lockId}"),
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
              title: Text('Settings: ${bleDoor.lockName}',
                  style: Theme.of(context).textTheme.titleLarge),
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
    TextEditingController controller =
        TextEditingController(text: bleDoor.lockName);
    ValueNotifier<bool> isValidDoorNameBool =
        ValueNotifier<bool>(isValidUsername(controller.text));

    controller.addListener(() {
      isValidDoorNameBool.value = isValidUsername(controller.text);
    });

    BleDoor previewBuild() {
      return BleDoor(
        lockId: bleDoor.lockId,
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
          appBar: AppBar(
            title: const Text('Edit Door'),
          ),
          body: Column(
            children: [
              //Colorpicker
              const SizedBox(height: 20),
              Text("Color", style: Theme.of(context).textTheme.titleLarge),
              ColorPicker(
                color: color,
              ),
              const SizedBox(height: 20),
              //Name
              Text("Door name", style: Theme.of(context).textTheme.titleLarge),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15),
                color: Colors.black12,
                child: TextField(
                  controller: controller,
                  decoration:
                      const InputDecoration(hintText: "Enter door name"),
                ),
              ),
              const SizedBox(height: 20),
              Text("Preview", style: Theme.of(context).textTheme.titleLarge),
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, bleName, child) => ValueListenableBuilder(
                  valueListenable: color,
                  builder: (context, color, child) {
                    return bleDoorWidget(context, previewBuild(),
                        isInteractable: false);
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
                          await BleDoorStorage.updateBleDoor(previewBuild());
                          await BleDoorStorage.loadBleDoors().then((value) {
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
            appBar: AppBar(
              title: const Text('Add Door User'),
            ),
            body: Column(
              children: [
                Container(
                  margin: const EdgeInsets.all(15),
                  child: TextField(
                    controller: controller,
                    decoration:
                        const InputDecoration(hintText: "Enter user name"),
                  ),
                ),
                ValueListenableBuilder(
                    valueListenable: isValidUserNameBool,
                    builder: (context, value, child) => ElevatedButton(
                          onPressed: value
                              ? () {
                                  addUserDialog2(
                                      context, bleDoor, controller.text);
                                }
                              : null,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: (isValidUserNameBool.value)
                                ? Colors.green
                                : Colors.grey, // text color
                          ),
                          child: const Text('Next'),
                        )),
              ],
            ),
          );
        });
  }

  void addUserDialog2(BuildContext context, BleDoor bleDoor, String username) {
    //gen a new BleDoor object and show the json as qrCode
    BleDoor newBleDoor = BleDoor(
        lockId: bleDoor.lockId,
        lockName: bleDoor.lockName,
        password: generateRandomString(32),
        userName: username,
        isAdmin: false);

    String bleDoorJson = jsonEncode(newBleDoor.toJson());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Add Door User'),
          ),
          body: Column(
            children: [
              Text("User: $username"),
              QrImageView(data: bleDoorJson, version: QrVersions.auto),
              ElevatedButton(
                  onPressed: () async {
                    await connectAndAddUser(context, bleDoor, newBleDoor);
                    Navigator.of(context).pop();
                  },
                  child: const Text("Add User"))
            ],
          ),
        );
      },
    );
  }

  bool doorIsNearBy(BleDoor bleDoor) {
    return discoveredEventArgs.value.where((element) {
      return element.peripheral.uuid == bleDoor.lockId;
    }).isNotEmpty;
  }

  Future<void> connectAndOpenBleDoor(
      BuildContext context, BleDoor bleDoor) async {
    try {
      var peripheral = discoveredEventArgs.value
          .where((element) {
            return element.peripheral.uuid == bleDoor.lockId;
          })
          .first
          .peripheral;
      await centralManager.connect(peripheral);

      await centralManager.authorize();
      var discoverGATT = await centralManager.discoverGATT(peripheral);
      /*
      print("is android: ${Platform.isAndroid}");
      print(
          "is state unauthorized: ${state.value == BluetoothLowEnergyState.unauthorized}");
      while (!(Platform.isAndroid &&
          state == BluetoothLowEnergyState.unauthorized)) {
        if (!isConnectingAndOpening(bleDoor)) return;
        print("is android: ${Platform.isAndroid}");
        print(
            "is state unauthorized: ${state.value == BluetoothLowEnergyState.unauthorized}");
        print("Authorize BLE-Connections");
        await centralManager.authorize();
        state.value = centralManager.state;
      }*/

      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT
              .expand((element) => element.characteristics)
              .firstWhere((element) => element.uuid == uuidUserCharacteristic),
          value: Uint8List.fromList(utf8.encode(bleDoor.userName)),
          type: GATTCharacteristicWriteType.withoutResponse);

      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT
              .expand((element) => element.characteristics)
              .firstWhere((element) => element.uuid == uuidPassCharacteristic),
          value: Uint8List.fromList(utf8.encode(bleDoor.password)),
          type: GATTCharacteristicWriteType.withoutResponse);

      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT.expand((element) => element.characteristics).firstWhere(
              (element) => element.uuid == uuidLockStateCharacteristic),
          value: Uint8List.fromList(utf8.encode("2")),
          type: GATTCharacteristicWriteType.withoutResponse);
    } catch (error) {
      errorDialog(context, error);
      rethrow;
    }
  }

  Future<void> connectAndAddUser(
      BuildContext context, BleDoor admin, BleDoor newUser) async {
    try {
      var peripheral = discoveredEventArgs.value
          .where((element) {
            return element.peripheral.uuid == admin.lockId;
          })
          .first
          .peripheral;
      await centralManager.connect(peripheral);
      var discoverGATT = await centralManager.discoverGATT(peripheral);
      print(
          "Connected to ${admin.lockName} with UUID ${admin.lockId} and following characteristics: ${discoverGATT.expand((element) => element.characteristics).map((e) => e.uuid).toList()}");
      for (var characteristic
          in discoverGATT.expand((element) => element.characteristics)) {
        print(
            "Characteristic: ${characteristic.uuid} and ${characteristic.properties}");
      }
      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT
              .expand((element) => element.characteristics)
              .firstWhere((element) => element.uuid == uuidAdminCharacteristic),
          value: Uint8List.fromList(utf8.encode(admin.userName)),
          type: GATTCharacteristicWriteType.withoutResponse);
      print("Wrote Admin User");
      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT.expand((element) => element.characteristics).firstWhere(
              (element) => element.uuid == uuidAdminPassCharacteristic),
          value: Uint8List.fromList(utf8.encode(admin.password)),
          type: GATTCharacteristicWriteType.withoutResponse);
      print("Wrote Admin Pass");
      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT.expand((element) => element.characteristics).firstWhere(
              (element) => element.uuid == uuidAddUserCharacteristic),
          value: Uint8List.fromList(utf8.encode(newUser.userName)),
          type: GATTCharacteristicWriteType.withoutResponse);
      print("Wrote New User");
      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT.expand((element) => element.characteristics).firstWhere(
              (element) => element.uuid == uuidAddPassCharacteristic),
          value: Uint8List.fromList(utf8.encode(newUser.password)),
          type: GATTCharacteristicWriteType.withoutResponse);
      print("Wrote New Pass");
      await centralManager.writeCharacteristic(
          peripheral,
          discoverGATT.expand((element) => element.characteristics).firstWhere(
              (element) => element.uuid == uuidAdminActionCharacteristic),
          value: Uint8List.fromList(utf8.encode("1")),
          type: GATTCharacteristicWriteType.withoutResponse);
      print("Wrote Admin Action");
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
                      hintText: "Enter JSON Payload here"),
                )),
            bottomNavigationBar: BottomAppBar(
              child: Row(
                children: [
                  const Expanded(
                      child: SizedBox(
                    width: 10,
                  )),
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
                  const SizedBox(
                    width: 10,
                  ),
                  ValueListenableBuilder(
                    valueListenable: isJsonValid,
                    builder: (context, value, child) {
                      return TextButton(
                        onPressed: value
                            ? () async {
                                Navigator.of(context).pop();
                                //save opener
                                String bleDoorJson = controller.text;
                                BleDoor deserializedBleDoor =
                                    BleDoor.fromJson(jsonDecode(bleDoorJson));
                                await BleDoorStorage.addBleDoor(
                                    deserializedBleDoor);
                                await BleDoorStorage.loadBleDoors()
                                    .then((value) {
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
                  )
                ],
              ),
            ));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black
            : Theme.of(context).colorScheme.primary,
        title: GestureDetector(
          onLongPress: () => showAllBLEDevices.value = !showAllBLEDevices.value,
          child: Row(children: [
            const Text("Door Opener "),
            Text("v${packageInfo.version}",
                style: const TextStyle(fontSize: 10))
          ]),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: () {
              widget.toggleDarkMode();
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
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
