import 'package:flutter/cupertino.dart';

import 'inputs.dart';
import '../theme.dart';
import '../tokens.dart';

class AppRow extends StatelessWidget {
  final Widget title;
  final Widget? subtitle, leading, trailing;
  final VoidCallback? onTap;
  const AppRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: subtitle == null ? AppTokens.row : AppTokens.twoLineRow,
      ),
      child: Padding(
        padding: AppTokens.rowPadding,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DefaultTextStyle(
                    style: AppTheme.of(context).text.bodyLarge,
                    child: title,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    DefaultTextStyle(
                      style: AppTheme.of(context).text.bodySmall,
                      child: subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.sizeOf(context).width.clamp(0, 680) * .42,
                ),
                child: DefaultTextStyle(
                  style: AppTheme.of(context).text.bodyMedium,
                  child: trailing!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return onTap == null
        ? content
        : CupertinoButton(
            onPressed: onTap,
            padding: EdgeInsets.zero,
            child: content,
          );
  }
}

class AppSwitchRow extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  const AppSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => AppRow(
    title: title,
    subtitle: subtitle,
    trailing: CupertinoSwitch(value: value, onChanged: onChanged),
    onTap: onChanged == null ? null : () => onChanged!(!value),
  );
}

class AppFieldRow extends StatelessWidget {
  final Widget child;
  final IconData? icon;
  final Widget? label, trailing;
  final double labelWidth;
  const AppFieldRow({
    super.key,
    required this.child,
    this.icon,
    this.label,
    this.trailing,
    this.labelWidth = 108,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppTokens.page),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTokens.row),
      child: LayoutBuilder(
        builder: (context, box) {
          final stacked =
              label != null &&
              (box.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(AppTokens.body) > 22);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: AppTokens.icon,
                height: AppTokens.row,
                child: icon == null ? null : Icon(icon, size: AppTokens.icon),
              ),
              const SizedBox(width: AppTokens.gap),
              Expanded(
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(alignment: Alignment.centerLeft, child: label!),
                          child,
                        ],
                      )
                    : ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: AppTokens.row,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (label != null)
                              SizedBox(
                                width: labelWidth,
                                height: AppTokens.row,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: label,
                                ),
                              ),
                            Expanded(
                              child: Stack(
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: AppTokens.row,
                                    ),
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        left: label == null
                                            ? 0
                                            : AppTokens.small,
                                      ),
                                      child: child,
                                    ),
                                  ),
                                  if (label != null)
                                    Positioned(
                                      left: 0,
                                      top:
                                          (AppTokens.row -
                                              AppTokens.actionIcon) /
                                          2,
                                      bottom:
                                          (AppTokens.row -
                                              AppTokens.actionIcon) /
                                          2,
                                      width:
                                          1 /
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ),
                                      child: ColoredBox(
                                        key: const ValueKey(
                                          'field-label-divider',
                                        ),
                                        color: AppTheme.of(context)
                                            .colors
                                            .outlineVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              SizedBox(width: AppTokens.touch, child: trailing),
            ],
          );
        },
      ),
    ),
  );
}

class AppInfoRow extends StatelessWidget {
  final String label, value;
  final bool changed;
  const AppInfoRow({
    super.key,
    required this.label,
    required this.value,
    this.changed = false,
  });
  @override
  Widget build(BuildContext context) => AppRow(
    title: Text(
      changed ? '$label · 有差异' : label,
      style: AppTheme.of(context).text.bodySmall,
    ),
    subtitle: AppSelectableText(
      value.isEmpty ? '未填写' : value,
      style: AppTheme.of(context).text.bodyLarge,
    ),
  );
}
