// lib/features/ble_door/widgets/ble_door_card.dart
import 'package:flutter/material.dart';
import '../models/ble_door.dart';
import '../../../utils/utils.dart';

class BleDoorCard extends StatefulWidget {
  final BleDoor door;
  final bool isConnecting;
  final bool isNearBy;
  final bool isPreview;
  final VoidCallback onOpen;
  final VoidCallback onShowAdminMenu;

  const BleDoorCard({
    Key? key,
    required this.door,
    this.isConnecting = false,
    this.isNearBy = false,
    this.isPreview = false,
    required this.onOpen,
    required this.onShowAdminMenu,
  }) : super(key: key);

  @override
  _BleDoorCardState createState() => _BleDoorCardState();
}

class _BleDoorCardState extends State<BleDoorCard> {
  bool isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.door.color ?? Colors.black12;
    final detailColor = adjustBrightness(
      baseColor,
      Theme.of(context).brightness == Brightness.dark ? -0.2 : 0.2,
    );

    return GestureDetector(
      onLongPress: widget.isPreview ? null : widget.onShowAdminMenu,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(15),
                  topRight: const Radius.circular(15),
                  bottomLeft:
                  isExpanded ? Radius.zero : const Radius.circular(15),
                  bottomRight:
                  isExpanded ? Radius.zero : const Radius.circular(15),
                ),
              ),
              child: ListTile(
                title: Text(
                  widget.door.lockName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    widget.isNearBy || widget.isPreview
                        ? Colors.green
                        : Colors.grey,
                  ),
                  onPressed: (!widget.isPreview &&
                      widget.isNearBy &&
                      !widget.isConnecting)
                      ? widget.onOpen
                      : null,
                  child: widget.isConnecting
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                      : const Text('Open'),
                ),
                onTap: () => setState(() => isExpanded = !isExpanded),
              ),
            ),
            if (isExpanded)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: detailColor,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(15),
                    bottomRight: Radius.circular(15),
                  ),
                ),
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Info:', style: TextStyle(color: Colors.black)),
                    Text('Lock ID: ${widget.door.peripheralMacAddress}'),
                    Text('User: ${widget.door.userName}'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
