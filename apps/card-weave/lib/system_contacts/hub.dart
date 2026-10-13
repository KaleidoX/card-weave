import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'page.dart';
import 'export/page.dart';

class SystemContactsHub extends StatelessWidget {
  final AppModel model;
  const SystemContactsHub(this.model, {super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: const AppNavigation(title: Text('系统通讯录')),
    body: AppSectionScrollView(
      children: [
        AppGroup(
          children: [
            AppRow(
              title: const Text('导入系统通讯录'),
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => SystemContactsImportPage(model),
                ),
              ),
            ),
            AppRow(
              title: const Text('写入系统通讯录与管理关联'),
              subtitle: const Text('可多选联系人，逐位预览和确认。不会自动同步或联动删除。'),
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => SystemContactsWriteList(model),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class SystemContactsWriteList extends StatefulWidget {
  final AppModel model;
  const SystemContactsWriteList(this.model, {super.key});
  @override
  State<SystemContactsWriteList> createState() =>
      _SystemContactsWriteListState();
}

class _SystemContactsWriteListState extends State<SystemContactsWriteList> {
  final items = <Map<String, dynamic>>[], selected = <String>{};
  String? error, result;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      for (var offset = 0; mounted; offset += 50) {
        final page = await widget.model.command('list', {
          'search': '',
          'offset': offset,
        }) as List;
        items.addAll(page.map(object));
        if (page.length < 50) break;
      }
    } catch (e) {
      error = message(e);
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> review() async {
    var completed = 0;
    final ids = selected.toList();
    for (final id in ids) {
      final done = await Navigator.push<bool>(
        context,
        CupertinoPageRoute(
          builder: (_) => SystemContactWritePage(widget.model, id),
        ),
      );
      if (!mounted) return;
      if (done != true) break;
      completed++;
      selected.remove(id);
    }
    setState(
      () => result = '已完成 $completed 位，其余 ${ids.length - completed} 位未继续处理',
    );
  }

  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: const AppNavigation(title: Text('写入与关联')),
    body: Column(
      children: [
        if (error != null) AppStatus(error!, kind: AppStatusKind.error),
        if (result != null) AppStatus(result!),
        if (loading) const CupertinoActivityIndicator(),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (c, i) {
              final item = items[i], id = items[i]['id'] as String;
              return AppRow(
                title: Text(item['data']['display_name'] as String),
                subtitle: item['has_conflict'] == true
                    ? const Text('请先解决冲突')
                    : null,
                trailing: Icon(
                  selected.contains(id)
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                ),
                onTap: item['has_conflict'] == true
                    ? null
                    : () => setState(() {
                        if (!selected.add(id)) selected.remove(id);
                      }),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: AppButton(
            onPressed: selected.isEmpty ? null : review,
            child: Text('逐位预览 ${selected.length} 位'),
          ),
        ),
      ],
    ),
  );
}
