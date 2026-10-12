import 'package:flutter/cupertino.dart';

/// Shares near-end loading and viewport-fill checks across lazy lists.
class AppPagination extends StatefulWidget {
  final bool enabled;
  final Future<void> Function() onLoad;
  final Widget Function(BuildContext, ScrollController) builder;
  const AppPagination({
    super.key,
    required this.enabled,
    required this.onLoad,
    required this.builder,
  });

  @override
  State<AppPagination> createState() => _AppPaginationState();
}

class _AppPaginationState extends State<AppPagination> {
  final controller = ScrollController();
  bool pending = false, scheduled = false;

  @override
  void initState() {
    super.initState();
    controller.addListener(scheduleCheck);
  }

  void scheduleCheck() {
    if (scheduled) return;
    scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduled = false;
      if (mounted) check();
    });
  }

  Future<void> check() async {
    if (!widget.enabled || pending || !controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions || position.extentAfter > 400) return;
    pending = true;
    try {
      await widget.onLoad();
    } finally {
      pending = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    scheduleCheck();
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        scheduleCheck();
        return false;
      },
      child: widget.builder(context, controller),
    );
  }
}
