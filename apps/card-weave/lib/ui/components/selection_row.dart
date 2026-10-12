import 'package:flutter/cupertino.dart';

import 'rows.dart';

class AppSelectionRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback? onTap;
  const AppSelectionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    child: AppRow(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Icon(
        selected
            ? CupertinoIcons.check_mark_circled_solid
            : CupertinoIcons.circle,
      ),
      onTap: onTap,
    ),
  );
}
