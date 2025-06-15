import 'package:flutter/material.dart';
import 'package:ble_doorlock_opener/app/theme_controller.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../controllers/ble_door_controller.dart';
import '../widgets/ble_device_list.dart';


class BleDoorPage extends StatefulWidget {
  final ThemeController themeController;
  const BleDoorPage({super.key, required this.themeController});

  @override
  State<BleDoorPage> createState() => _BleDoorPageState();
}

class _BleDoorPageState extends State<BleDoorPage> {
  late final BleDoorController _controller;
  String version = '';

  @override
  void initState() {
    super.initState();
    _controller = BleDoorController();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      version = info.version;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.black
            : Theme.of(context).colorScheme.primary,
        title: GestureDetector(
          onLongPress: _controller.toggleShowAllDevices,
          child: Row(
            children: [
              const Text("Door Opener "),
              Text("v$version", style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.themeController.toggleTheme,
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => _controller.showAddOpenerDialog(context),
            child: const Text("Add Opener"),
          ),
        ],
      ),
      body: BleDeviceList(controller: _controller),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
