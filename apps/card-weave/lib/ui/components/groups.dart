import 'package:flutter/cupertino.dart';

import '../theme.dart';
import '../tokens.dart';

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: AppTokens.caption,
        color: AppTheme.of(context).colors.onSurfaceVariant,
      ),
    ),
  );
}

class SurfaceBox extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry margin;
  const SurfaceBox({
    super.key,
    required this.child,
    this.color,
    this.margin = EdgeInsets.zero,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: color ?? AppTheme.of(context).colors.surface,
      borderRadius: BorderRadius.circular(AppTokens.radius),
    ),
    child: child,
  );
}

enum AppAlignment { plain, icon, avatar }

class AppGroup extends StatelessWidget {
  final List<Widget> children;
  final AppAlignment alignment;
  const AppGroup({
    super.key,
    required this.children,
    this.alignment = AppAlignment.plain,
  });
  @override
  Widget build(BuildContext context) => SurfaceBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) GroupDivider(alignment: alignment),
          children[i],
        ],
      ],
    ),
  );
}

class GroupDivider extends StatelessWidget {
  final AppAlignment alignment;
  const GroupDivider({super.key, this.alignment = AppAlignment.plain});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: switch (alignment) {
        AppAlignment.plain => AppTokens.page,
        AppAlignment.icon => AppTokens.contentInset,
        AppAlignment.avatar =>
          AppTokens.page + AppTokens.avatar + AppTokens.gap,
      },
      right: AppTokens.page,
    ),
    child: Container(
      height: 1 / MediaQuery.devicePixelRatioOf(context),
      color: AppTheme.of(context).colors.outlineVariant,
    ),
  );
}

class AppListItem extends StatelessWidget {
  final Widget child;
  final bool first, last;
  final AppAlignment alignment;
  const AppListItem({
    super.key,
    required this.child,
    required this.first,
    required this.last,
    this.alignment = AppAlignment.plain,
  });
  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppTheme.of(context).colors.surface,
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(first ? AppTokens.radius : 0),
        bottom: Radius.circular(last ? AppTokens.radius : 0),
      ),
    ),
    child: Column(
      children: [
        child,
        if (!last) GroupDivider(alignment: alignment),
      ],
    ),
  );
}
