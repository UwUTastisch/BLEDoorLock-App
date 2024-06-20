import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:ble_doorlock_opener/storage/ble-door-storage.dart';
import 'package:ble_doorlock_opener/utils.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'models/ble-door.dart';

bool get enablePeripheral => !Platform.isLinux && !Platform.isWindows;

final ValueNotifier<bool> showAllBLEDevices = ValueNotifier(false);
final uuidUserCharacteristic =
    UUID.fromString("5d3932fa-2901-4b6b-9f41-7720976a85d4");
final uuidPassCharacteristic =
    UUID.fromString("dd16cad0-a66a-402f-9183-201c20753647");
final uuidLockStateCharacteristic =
    UUID.fromString("05c5653a-7279-406c-9f9e-df72aa99ca2d");

void main() {
  runZonedGuarded(onStartUp, onCrashed);
}

void onStartUp() async {
  Logger.root.onRecord.listen(onLogRecord);
  // hierarchicalLoggingEnabled = true;
  // CentralManager.instance.logLevel = Level.WARNING;
  WidgetsFlutterBinding.ensureInitialized();
  await CentralManager.instance.setUp();
  if (enablePeripheral) {
    await PeripheralManager.instance.setUp();
  }

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

// Show widgets

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'BLE-Door-Opener',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
          ),
        ),
        home: BodyView());
  }
}

class BodyView extends StatefulWidget {
  const BodyView({super.key});

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

  @override
  void initState() {
    super.initState();
    state = ValueNotifier(BluetoothLowEnergyState.unknown);
    discovering = ValueNotifier(false);
    discoveredEventArgs = ValueNotifier([]);
    stateChangedSubscription = CentralManager.instance.stateChanged.listen(
      (eventArgs) {
        state.value = eventArgs.state;
      },
    );
    discoveredSubscription = CentralManager.instance.discovered.listen(
      (eventArgs) {
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
      },
    );
    bleDoors = ValueNotifier([]);
    _initialize();
  }

  void _initialize() async {
    state.value = await CentralManager.instance.getState();
    List<BleDoor> loadedBleDoors = await BleDoorStorage.loadBleDoors();
    loadedBleDoors.forEach((door) {
      print('Loaded BleDoor: ${door.toJson()}');
    });
    bleDoors.value = loadedBleDoors;

    startDiscovery();
  }

  Future<void> startDiscovery() async {
    discoveredEventArgs.value = [];
    await CentralManager.instance.startDiscovery();
    discovering.value = true;
  }

  Future<void> stopDiscovery() async {
    await CentralManager.instance.stopDiscovery();
    discovering.value = false;
  }

  Widget buildShowAll(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: showAllBLEDevices,
      builder: (context, showble, child) => ValueListenableBuilder(
        valueListenable: discoveredEventArgs,
        builder: (context, eventargs, child) {
          List<Widget> widgets = [
            for (var bleDoor in bleDoors.value) bleDoorWidget(context, bleDoor)
          ];
          if (showble) {
            widgets.addAll(
                bleListeningWidgets(context, discoveredEventArgs.value));
          }

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
    // List<Widget> bleListeningWidgets(BuildContext context, List<DiscoveredEventArgs> discoveredEventArgs) {
    List<Widget> widgets = [];

    for (var item in discoveredEventArgs) {
      final uuid = item.peripheral.uuid;
      final rssi = item.rssi;
      final advertisement = item.advertisement;
      final name = advertisement.name;
      if(advertisement.name == null) {
        continue;
      }
      widgets.add(Column(children: [
        Text(
            "Name -> $name, \n UUID -> $uuid, \n RSSI -> $rssi, \n Advertisment -> $advertisement"),
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
              print("Example door $bleDoorJson");
            },
            child: const Text("Copy ID")),
      ]));
    }
    return widgets;
  }

  Widget bleDoorWidget(BuildContext context, BleDoor bleDoor) {
    return GestureDetector(
      onLongPress: () {
        showAdminMenu(context, bleDoor);
      },
      child: Card(
        color: Colors.black12,
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 5),
                Expanded(
                    child: Text(
                  bleDoor.lockName,
                  style: Theme.of(context).textTheme.displaySmall,
                )),
                Container(
                  margin: const EdgeInsets.all(5),
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            doorIsNearBy(bleDoor) ? Colors.green : Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        connectAndOpenBleDoor(bleDoor);
                      },
                      child: const Text("Open")),
                )
                //Container(
                //  margin: const EdgeInsets.all(5),
                //  child: ElevatedButton(
                //      style: TextButton.styleFrom(
                //        foregroundColor: Colors.white,
                //        backgroundColor: Colors.red, // text color
                //      ),
                //      onPressed: () async {
                //        sureYouWantToRemoveDialog(context, bleDoor);
                //      },
                //      child: Icon(Icons.delete)),
                //)
              ],
            ),
            const Divider(
              color: Colors.black12,
              thickness: 2,
              height: 2,
            ),
            Row(
              children: [
                const SizedBox(width: 5),
                Text("Info:", style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 5),
                Text("Lock ID: ${bleDoor.lockId}"),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 5),
                Text("User: ${bleDoor.userName}"),
              ],
            )
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
                  addUserDialog1(bleDoor);
                },
              ),
            if (bleDoor.isAdmin) const Divider(thickness: 2, height: 0),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Door'),
              onTap: () {
                sureYouWantToRemoveDialog(context, bleDoor);
                // TODO: Implement delete door functionality
              },
            ),
            // Add more admin options here
          ],
        );
      },
    );
  }

  void addUserDialog1(BleDoor bleDoor) {
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
                                  addUserDialog2(bleDoor, controller.text);
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

  void addUserDialog2(BleDoor bleDoor, String username) {
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

  Future<void> connectAndOpenBleDoor(BleDoor bleDoor) async {
    try {
    var peripheral = discoveredEventArgs.value
        .where((element) {
          return element.peripheral.uuid == bleDoor.lockId;
        })
        .first
        .peripheral;
    //await CentralManager.instance.disconnect(peripheral);
    await CentralManager.instance.connect(peripheral);
    var discoverGATT = await CentralManager.instance.discoverGATT(peripheral);

    await CentralManager.instance.writeCharacteristic(
        discoverGATT
            .expand((element) => element.characteristics)
            .firstWhere((element) => element.uuid == uuidUserCharacteristic),
        value: Uint8List.fromList(utf8.encode(bleDoor.userName)),
        type: GattCharacteristicWriteType.withoutResponse);

    await CentralManager.instance.writeCharacteristic(
    discoverGATT
        .expand((element) => element.characteristics)
        .firstWhere((element) => element.uuid == uuidPassCharacteristic),
    value: Uint8List.fromList(utf8.encode(bleDoor.password)),
    type: GattCharacteristicWriteType.withoutResponse);

    await CentralManager.instance.writeCharacteristic(
        discoverGATT
            .expand((element) => element.characteristics)
            .firstWhere((element) => element.uuid == uuidLockStateCharacteristic),
        value: Uint8List.fromList(utf8.encode("2")),
        type: GattCharacteristicWriteType.withoutResponse);
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
              title: const Text('Add Door Opener by QR-Code or JSON Payloa'),
            ),
            body: qrCodeScan(controller),
            floatingActionButton: TextField(
              controller: controller,
              decoration:
                  const InputDecoration(hintText: "Enter something here"),
            ),
            bottomNavigationBar: BottomAppBar(
              child: Row(
                children: [
                  Expanded(
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
                                print('You entered: $bleDoorJson');
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

  QRCodeDartScanView qrCodeScan(TextEditingController controller) {
    return QRCodeDartScanView(
      scanInvertedQRCode: true, // enable scan invert qr code ( default = false)

      typeScan: TypeScan.live,
      onCapture: (Result result) {
        print("OwO Result: ${result.text}");
        //update textfield
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
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: GestureDetector(
              onLongPress: () =>
                  showAllBLEDevices.value = !showAllBLEDevices.value,
              child: const Text("Door Opener")),
          actions: [
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange // foreground
                    ),
                onPressed: () async {
                  addOpenerDialog(context);
                },
                child: const Text("Add Opener"))
          ],
        ),
        body: buildShowAll(context)
        //buildShowAll(context)
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
                backgroundColor: Colors.red, // text color
              ),
              child: const Text('Yes'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('No'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.green, // text color
              ),
            ),
          ],
        );
      },
    );
  }
}
