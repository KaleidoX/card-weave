import 'package:flutter/cupertino.dart';

import '../../design.dart';
import '../../model.dart';
import '../strategy.dart';

class SystemContactTargetPage extends StatefulWidget {
  final SystemContactsStrategy strategies;
  const SystemContactTargetPage(this.strategies, {super.key});
  @override
  State<SystemContactTargetPage> createState() =>
      _SystemContactTargetPageState();
}

class _SystemContactTargetPageState extends State<SystemContactTargetPage> {
  final search = TextEditingController();
  final items = <Map<String, dynamic>>[];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      var after = '0';
      while (mounted) {
        final page = await widget.strategies.importer!.page(after);
        items.addAll(page);
        if (page.length < 50) break;
        final next = page.last['id'] as String;
        if (next == after) throw StateError('系统分页未前进');
        after = next;
      }
    } catch (e) {
      error = message(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> select(Map<String, dynamic> item) async {
    try {
      final targets = await widget.strategies.exporter!.targets(
        item['id'] as String,
      );
      if (!mounted) return;
      if (!targets.any((t) => t['writable'] == true)) {
        throw StateError('此联系人没有可写记录，请选择其他联系人或新建');
      }
      final result = await showCupertinoModalPopup<Map<String, dynamic>>(
        context: context,
        builder: (c) => CupertinoActionSheet(
          title: Text(item['name'] as String),
          message: const Text('选择要关联的账户记录'),
          actions: [
            for (final t in targets.where((t) => t['writable'] == true))
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(c, t),
                child: Text(
                  '${t['accountName'] ?? '设备本地'}${t['writable'] == true ? '' : '（只读）'}',
                ),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
        ),
      );
      if (result != null && mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: const AppNavigation(title: Text('选择系统联系人')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: AppSearchField(
            controller: search,
            onClear: () => setState(search.clear),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (error != null) AppStatus(error!, kind: AppStatusKind.error),
        if (loading) const CupertinoActivityIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (c, i) {
              final item = items[i];
              if (!(item['name'] as String).toLowerCase().contains(
                search.text.toLowerCase(),
              )) {
                return const SizedBox.shrink();
              }
              return AppRow(
                title: Text(item['name'] as String),
                onTap: () => select(item),
              );
            },
          ),
        ),
      ],
    ),
  );
}
