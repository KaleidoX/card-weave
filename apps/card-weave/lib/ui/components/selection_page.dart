import 'package:flutter/cupertino.dart';

import 'navigation.dart';
import 'actions.dart';

class AppSelectionPageShell extends StatelessWidget {
  final String title;
  final Widget body;
  final VoidCallback? onDone;
  final bool busy;
  const AppSelectionPageShell({
    super.key,
    required this.title,
    required this.body,
    this.onDone,
    this.busy = false,
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AppPage(
      navigationBar: AppNavigation(
        title: Text(title),
        leading: AppButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        actions: [
          if (onDone != null)
            AppButton(onPressed: busy ? null : onDone, child: const Text('完成')),
        ],
      ),
      body: body,
    ),
  );
}
