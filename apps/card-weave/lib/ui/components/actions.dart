import 'package:flutter/cupertino.dart';

import '../theme.dart';
import '../tokens.dart';

class AppButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool filled;
  final Widget? icon;
  const AppButton({super.key, required this.onPressed, required this.child})
    : filled = false,
      icon = null;
  const AppButton.filled({
    super.key,
    required this.onPressed,
    required this.child,
  }) : filled = true,
       icon = null;
  const AppButton.icon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
  }) : child = label,
       filled = false;
  const AppButton.filledIcon({
    super.key,
    required this.onPressed,
    required Widget label,
    required this.icon,
  }) : child = label,
       filled = true;
  @override
  Widget build(BuildContext context) {
    final content = icon == null
        ? child
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon!,
              const SizedBox(width: 8),
              Flexible(child: child),
            ],
          );
    final padding = EdgeInsets.symmetric(
      horizontal: filled ? 16 : 8,
      vertical: 10,
    );
    return filled
        ? CupertinoButton.filled(
            onPressed: onPressed,
            padding: padding,
            minimumSize: const Size(AppTokens.touch, AppTokens.touch),
            borderRadius: BorderRadius.circular(AppTokens.radius),
            child: content,
          )
        : CupertinoButton(
            onPressed: onPressed,
            padding: padding,
            minimumSize: const Size(AppTokens.touch, AppTokens.touch),
            child: content,
          );
  }
}

class AppIconButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final String tooltip;
  const AppIconButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: tooltip,
    container: true,
    button: true,
    child: CupertinoButton(
      onPressed: onPressed,
      padding: const EdgeInsets.all(AppTokens.small),
      minimumSize: const Size(AppTokens.touch, AppTokens.touch),
      child: icon,
    ),
  );
}

class AppRemoveButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  const AppRemoveButton({
    super.key,
    required this.onPressed,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => AppIconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(
      CupertinoIcons.minus_circle_fill,
      size: AppTokens.actionIcon,
      color: AppTheme.of(context).colors.error,
    ),
  );
}
