import 'package:flutter/cupertino.dart';

import '../theme.dart';
import '../tokens.dart';

class AppWheel extends StatefulWidget {
  const AppWheel({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.text,
    required this.onChanged,
  });
  final String label;
  final int count;
  final int selected;
  final String Function(int) text;
  final ValueChanged<int> onChanged;
  @override
  State<AppWheel> createState() => _AppWheelState();
}

class _AppWheelState extends State<AppWheel> {
  bool correctingSelection = false;
  late final controller = FixedExtentScrollController(
    initialItem: widget.selected,
  );
  @override
  void didUpdateWidget(covariant AppWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected &&
        controller.hasClients &&
        controller.selectedItem != widget.selected) {
      correctingSelection = true;
      try {
        controller.jumpToItem(widget.selected);
      } finally {
        correctingSelection = false;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: SizedBox(
      height: AppTokens.wheelHeight,
      child: CupertinoPicker.builder(
        scrollController: controller,
        itemExtent:
            AppTokens.touch *
            MediaQuery.textScalerOf(context).scale(AppTokens.body) /
            AppTokens.body,
        childCount: widget.count,
        onSelectedItemChanged: (value) {
          if (!correctingSelection) widget.onChanged(value);
        },
        itemBuilder: (_, i) => Center(
          child: Text(
            widget.text(i),
            style: AppTheme.of(context).text.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
