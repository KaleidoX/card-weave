import 'package:flutter/cupertino.dart';

import '../tokens.dart';

class AppDialog extends StatelessWidget {
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
  });
  @override
  Widget build(BuildContext context) =>
      CupertinoAlertDialog(title: title, content: content, actions: actions);
}

class AppLabelDialog extends StatefulWidget {
  final String initial;
  const AppLabelDialog({super.key, required this.initial});
  @override
  State<AppLabelDialog> createState() => _AppLabelDialogState();
}

class _AppLabelDialogState extends State<AppLabelDialog> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('自定义标签'),
    content: Padding(
      padding: const EdgeInsets.only(top: AppTokens.gap),
      child: CupertinoTextField(
        controller: text,
        autofocus: true,
        placeholder: '标签名称',
        onChanged: (_) => setState(() {}),
      ),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      CupertinoDialogAction(
        onPressed: text.text.trim().isEmpty || text.text.length > 256
            ? null
            : () => Navigator.pop(context, text.text.trim()),
        child: const Text('完成'),
      ),
    ],
  );
}
