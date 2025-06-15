// lib/utils/dialogs.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_code_dart_scan/qr_code_dart_scan.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/utils.dart';
import '../features/ble_door/controllers/ble_door_controller.dart';
import '../features/ble_door/models/ble_door.dart';
import '../features/ble_door/widgets/color_picker.dart';
import '../features/ble_door/widgets/ble_door_card.dart';

class Dialogs {
  static void showErrorDialog(BuildContext context, Object error) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Error'),
        content: Text(error.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static void showSuccessDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Success'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static void showAddOpener(
      BuildContext context, BleDoorController controller) {
    final jsonCtrl = TextEditingController();
    final isValidJson = ValueNotifier(false);
    final qrCtrl = QRCodeDartScanController();

    jsonCtrl.addListener(() {
      try {
        BleDoor.fromJson(jsonDecode(jsonCtrl.text));
        isValidJson.value = true;
      } catch (_) {
        isValidJson.value = false;
      }
    });

    showDialog(
      context: context,
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Add Door Opener')),
        body: Column(
          children: [
            Expanded(
              child: QRCodeDartScanView(
                controller: qrCtrl,
                typeCamera: TypeCamera.back,
                typeScan: TypeScan.live,
                onCapture: (res) {
                  jsonCtrl.text = res.text;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: TextField(
                controller: jsonCtrl,
                decoration:
                    const InputDecoration(hintText: 'Enter JSON Payload'),
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          child: Row(
            children: [
              const Expanded(child: SizedBox(width: 10)),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.red, // text color
                ),
                child: const Text('Close'),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<bool>(
                valueListenable: isValidJson,
                builder: (c, valid, _) => TextButton(
                  onPressed: valid
                      ? () async {
                          final payload = jsonDecode(jsonCtrl.text);
                          final door = BleDoor.fromJson(payload);
                          Navigator.of(ctx).pop();
                          await controller.addBleDoor(door);
                        }
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: (isValidJson.value)
                        ? Colors.green
                        : Colors.grey, // text color
                  ),
                  child: const Text('Add Opener'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void showAdminMenu(
      BuildContext context, BleDoorController controller, BleDoor door) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Settings: ${door.lockName}'),
          ),
          const Divider(height: 0),
          if (door.isAdmin)
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add Door User'),
              onTap: () {
                Navigator.of(context).pop();
                showAddUserDialog(context, controller, door);
              },
            ),
          if (door.isAdmin) const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit Door'),
            onTap: () {
              Navigator.of(context).pop();
              showEditDoorDialog(context, controller, door);
            },
          ),
          const Divider(height: 0),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete Door'),
            onTap: () {
              Navigator.of(context).pop();
              showConfirmRemoveDialog(context, controller, door);
            },
          ),
        ],
      ),
    );
  }

  static void showEditDoorDialog(
      BuildContext context, BleDoorController controller, BleDoor door) {
    final nameCtrl = TextEditingController(text: door.lockName);
    final isValidName = ValueNotifier(isValidUsername(nameCtrl.text));
    final colorNot = ValueNotifier<Color?>(door.color);

    nameCtrl
        .addListener(() => isValidName.value = isValidUsername(nameCtrl.text));

    showDialog(
      context: context,
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Edit Door')),
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 16),
              const Text('Choose Color'),
              ColorPicker(color: colorNot),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Door Name'),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Preview'),
              BleDoorCard(
                door: BleDoor(
                  peripheralMacAddress: door.peripheralMacAddress,
                  lockName: nameCtrl.text,
                  userName: door.userName,
                  password: door.password,
                  isAdmin: door.isAdmin,
                  color: colorNot.value,
                ),
                onOpen: () {},
                onShowAdminMenu: () {},
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ValueListenableBuilder<bool>(
              valueListenable: isValidName,
              builder: (c, valid, _) => TextButton(
                onPressed: valid
                    ? () async {
                        final updated = BleDoor(
                          peripheralMacAddress: door.peripheralMacAddress,
                          lockName: nameCtrl.text,
                          userName: door.userName,
                          password: door.password,
                          isAdmin: door.isAdmin,
                          color: colorNot.value,
                        );
                        Navigator.of(ctx).pop();
                        await controller.updateBleDoor(updated);
                      }
                    : null,
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void showAddUserDialog(
      BuildContext context, BleDoorController controller, BleDoor door) {
    final userCtrl = TextEditingController();
    final isValid = ValueNotifier(false);

    userCtrl.addListener(() => isValid.value = isValidUsername(userCtrl.text));

    showDialog(
      context: context,
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Add Door User')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: userCtrl,
            decoration: const InputDecoration(labelText: 'User Name'),
          ),
        ),
        bottomNavigationBar: BottomAppBar(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ValueListenableBuilder<bool>(
              valueListenable: isValid,
              builder: (c, valid, _) => TextButton(
                onPressed: valid
                    ? () {
                        Navigator.of(ctx).pop();
                        showAddUserPasswordDialog(
                            context, controller, door, userCtrl.text);
                      }
                    : null,
                child: const Text('Next'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void showAddUserPasswordDialog(BuildContext context,
      BleDoorController controller, BleDoor door, String userName) {
    final password = generateRandomString(32);
    final newUser = BleDoor(
      peripheralMacAddress: door.peripheralMacAddress,
      lockName: door.lockName,
      userName: userName,
      password: password,
      isAdmin: false,
    );
    final payload = jsonEncode(newUser.toJson());

    showDialog(
      context: context,
      builder: (ctx) => Scaffold(
        appBar: AppBar(title: const Text('Add Door User')),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('User: $userName'),
            QrImageView(data: payload, version: QrVersions.auto),
          ],
        ),
        bottomNavigationBar: BottomAppBar(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await controller.connectAndAddUser(context, door, newUser);
              },
              child: const Text('Add User'),
            ),
          ),
        ),
      ),
    );
  }

  static void showConfirmRemoveDialog(
      BuildContext context, BleDoorController controller, BleDoor door) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm'),
        content: const Text('Do you really want to remove this door?'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await controller.removeBleDoor(door);
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
      ),
    );
  }
}
