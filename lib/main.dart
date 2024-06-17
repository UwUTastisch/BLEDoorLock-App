import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

bool get enablePeripheral => !Platform.isLinux && !Platform.isWindows;

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
    _initialize();
  }

  void _initialize() async {
    state.value = await CentralManager.instance.getState();
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
      valueListenable: discoveredEventArgs,
      builder: (context, discoveredEventArgs, child) {
        final items = discoveredEventArgs
            .where((eventArgs) => eventArgs.advertisement.name != null)
            .toList();
        return ListView.separated(
          itemBuilder: (context, i) {
            final theme = Theme.of(context);
            final item = items[i];
            final uuid = item.peripheral.uuid;
            final rssi = item.rssi;
            final advertisement = item.advertisement;
            final name = advertisement.name;
            return Column(children: [
              Text(
                  "Name -> $name, \n UUID -> $uuid, \n RSSI -> $rssi, \n Advertisment -> $advertisement"),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange // foreground
                      ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: uuid.toString()));
                  },
                  child: const Text("Copy ID")),
              ElevatedButton(
                  child: const Text("Connect"),
                  onPressed: () async {
                    await CentralManager.instance
                        .connect(item.peripheral)
                        .whenComplete(
                      () {
                        CentralManager.instance
                            .discoverGATT(item.peripheral)
                            .then((value) {
                          print("OwO4.1 $value");
                          value.forEach((element) {
                            print("OwO4.2 ${element.uuid}");
                            print("OwO4.3 ${element.characteristics}");
                            element.characteristics.forEach((element) {
                              print("OwO4.4 ${element.uuid}");
                              if(element.uuid == uuidLockStateCharacteristic) {
                                print("OwO4.5 ${element.uuid}");
                                CentralManager.instance.writeCharacteristic(element, value: Uint8List.fromList(utf8.encode("1")), type: GattCharacteristicWriteType.withoutResponse);
                              } else if (element.uuid == uuidUserCharacteristic) {
                                print("OwO4.6 ${element.uuid}");
                                CentralManager.instance.writeCharacteristic(element, value: Uint8List.fromList(utf8.encode("spr")), type: GattCharacteristicWriteType.withoutResponse);
                              } else if (element.uuid == uuidPassCharacteristic) {
                                print("OwO4.7 ${element.uuid}");
                                CentralManager.instance.writeCharacteristic(element, value: Uint8List.fromList(utf8.encode("spr")), type: GattCharacteristicWriteType.withoutResponse);
                              }
                            }
                            );
                          });
                        });
                      },
                    );
                  })
            ]);
          },
          separatorBuilder: (BuildContext context, int index) {
            return const Divider(
              height: 0.0,
            );
          },
          itemCount: items.length,
        );
      },
    );
  }

  Widget buildKnown(BuildContext context) {
    return const OpenerPage(
      bleDeviceName: "SPR-Door2",
      bleSharedKey: "Key",
      bleDeviceInfoText:
          'OwO this device is doing things i cant understand QwQ',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text("Door Opener"),
          actions: [
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange // foreground
                    ),
                onPressed: () async {},
                child: const Text("Add Opener"))
          ],
        ),
        body: buildShowAll(context));
  }
}

class OpenerPage extends StatefulWidget {
  const OpenerPage(
      {super.key,
      required this.bleDeviceName,
      required this.bleSharedKey,
      required this.bleDeviceInfoText});

  final String bleDeviceName;
  final String bleDeviceInfoText;
  final String bleSharedKey;

  @override
  State<OpenerPage> createState() {
    return _OpenerPageState();
  }
}

class _OpenerPageState extends State<OpenerPage> {
  DateTime tryConnect = DateTime.now().add(const Duration(days: 1));

  bool isConnected() {
    var abs = tryConnect.difference(DateTime.now()).inSeconds.abs();
    bool b = abs > 5;

    if (kDebugMode) {
      print("OwO3 time $tryConnect, difference $abs, boolean $b");
    }

    return b;
  }

  //bool isConnected() {
  //  tryConnect.difference(DateTime.now()).inSeconds > 5;
  //}

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          color: Colors.black12,
          child: Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 5),
                  Expanded(
                      child: Text(
                    widget.bleDeviceName,
                    style: Theme.of(context).textTheme.displaySmall,
                  )),
                  (isConnected())
                      ? const SizedBox()
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange // foreground
                              ),
                          onPressed: () {
                            setState(() {});
                          },
                          child: const Text("Open")),
                  Container(
                    margin: const EdgeInsets.all(5),
                    child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange // foreground
                            ),
                        onPressed: () {
                          setState(() {
                            tryConnect = DateTime.now();
                          });
                        },
                        child: const Text("Connect")),
                  )
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
                  Text(widget.bleDeviceInfoText),
                ],
              ),
              Text(tryConnect.toString())
            ],
          ),
        ),
      ],
    );
  }
}

/*
                  print("OwO4.09 ${discoveredSubscription}");
                  ValueNotifier<BluetoothLowEnergyState> state;
                  state = ValueNotifier(BluetoothLowEnergyState.unknown);
                  state.value = await CentralManager.instance.getState();
                  //discoveredEventArgs.value = [];
                  await CentralManager.instance.startDiscovery();
                  print("OwO4.1 ${discoveredSubscription}");
                  //discovering.value = true;
 */
