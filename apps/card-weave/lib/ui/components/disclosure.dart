import 'package:flutter/cupertino.dart';

import 'rows.dart';

class AppDisclosure extends StatefulWidget {
  final Widget title;
  final List<Widget> children;
  const AppDisclosure({super.key, required this.title, required this.children});
  @override
  State<AppDisclosure> createState() => _AppDisclosureState();
}

class _AppDisclosureState extends State<AppDisclosure> {
  bool open = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      AppRow(
        title: widget.title,
        trailing: Icon(
          open ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
          size: 16,
        ),
        onTap: () => setState(() => open = !open),
      ),
      if (open) ...widget.children,
    ],
  );
}
