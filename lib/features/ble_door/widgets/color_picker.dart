// lib/features/ble_door/widgets/color_picker.dart
import 'package:flutter/material.dart';

class ColorPicker extends StatelessWidget {
  final ValueNotifier<Color?> color;
  const ColorPicker({Key? key, required this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color?>(
      valueListenable: color,
      builder: (context, selected, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: Colors.primaries.map((c) {
              return GestureDetector(
                onTap: () => color.value = c,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(
                      color: selected == c
                          ? Colors.black
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
