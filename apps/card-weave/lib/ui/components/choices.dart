import 'package:flutter/cupertino.dart';

import 'actions.dart';
import 'groups.dart';
import 'rows.dart';
import '../tokens.dart';

Future<T?> chooseOption<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  required T selected,
  bool Function(T)? enabled,
  Rect? anchor,
}) {
  final media = MediaQuery.of(context);
  Widget option(BuildContext c, MapEntry<T, String> entry) => AppRow(
    title: Text(entry.value),
    subtitle: enabled != null && !enabled(entry.key) ? const Text('已使用') : null,
    trailing: entry.key == selected
        ? const Icon(CupertinoIcons.check_mark)
        : null,
    onTap: enabled != null && !enabled(entry.key)
        ? null
        : () => Navigator.pop(c, entry.key),
  );
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (c) {
      if (anchor == null ||
          media.size.width < 350 ||
          media.textScaler.scale(AppTokens.body) > 22) {
        return SafeArea(
          child: Padding(
            padding: AppTokens.pagePadding,
            child: SurfaceBox(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: media.size.height * .65),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SectionLabel(title),
                      for (final entry in options.entries) option(c, entry),
                      AppButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('取消'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final available =
          media.size.height - media.padding.vertical - 2 * AppTokens.page;
      final height = (options.length * AppTokens.row).clamp(
        0.0,
        available < 360 ? available : 360.0,
      );
      final top =
          (anchor.bottom + AppTokens.tiny + height <
                      media.size.height - media.padding.bottom
                  ? anchor.bottom + AppTokens.tiny
                  : anchor.top - height - AppTokens.tiny)
              .clamp(
                media.padding.top + AppTokens.page,
                media.size.height -
                    media.padding.bottom -
                    height -
                    AppTokens.page,
              );
      final left = anchor.left.clamp(
        AppTokens.page,
        media.size.width - 280 - AppTokens.page,
      );
      return SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              width: 280,
              height: height,
              child: Semantics(
                namesRoute: true,
                label: title,
                child: SurfaceBox(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      for (final entry in options.entries) option(c, entry),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class AppChoice<T> extends StatelessWidget {
  final String title;
  final T selected;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  final bool Function(T)? enabled;
  final String? label;
  const AppChoice({
    super.key,
    required this.title,
    required this.selected,
    required this.options,
    required this.onChanged,
    this.enabled,
    this.label,
  });
  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchorContext) => AppButton(
      onPressed: () async {
        FocusScope.of(context).unfocus();
        final box = anchorContext.findRenderObject() as RenderBox?;
        final value = await chooseOption<T>(
          context,
          title: title,
          options: options,
          selected: selected,
          enabled: enabled,
          anchor: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
        if (value != null && context.mounted) onChanged(value);
      },
      child: TypeLabel(label ?? options[selected] ?? title),
    ),
  );
}

class TypeLabel extends StatelessWidget {
  final String text;
  const TypeLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppTokens.body,
            height: 1.3,
            color: CupertinoTheme.of(context).primaryColor,
          ),
        ),
      ),
      const SizedBox(width: AppTokens.labelGap),
      Icon(
        CupertinoIcons.chevron_down,
        size: AppTokens.chevron,
        color: CupertinoTheme.of(context).primaryColor,
      ),
    ],
  );
}
