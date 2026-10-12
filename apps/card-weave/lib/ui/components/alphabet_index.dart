import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../theme.dart';

class AppAlphabetIndex extends StatelessWidget {
  final List<String> letters;
  final String? selected;
  final ValueChanged<String> onSelected;
  const AppAlphabetIndex({
    super.key,
    required this.letters,
    this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    if (letters.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(20.0, constraints.maxHeight / letters.length);
        void select(Offset position) {
          final index = (position.dy / height).floor().clamp(
            0,
            letters.length - 1,
          );
          onSelected(letters[index]);
        }

        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (event) => select(event.localPosition),
            onVerticalDragStart: (event) => select(event.localPosition),
            onVerticalDragUpdate: (event) => select(event.localPosition),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final letter in letters)
                  Semantics(
                    button: true,
                    label: '跳转到 $letter',
                    selected: selected == letter,
                    onTap: () => onSelected(letter),
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 32,
                        height: height,
                        child: Center(
                          child: Text(
                            letter,
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.of(context).colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
