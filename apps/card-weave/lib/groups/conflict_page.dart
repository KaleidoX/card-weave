import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'pages.dart';

class EntityConflictPage extends StatefulWidget {
  final AppModel model;
  final Map<String, dynamic> conflict;
  const EntityConflictPage(this.model, this.conflict, {super.key});
  @override
  State<EntityConflictPage> createState() => _EntityConflictPageState();
}

class _EntityConflictPageState extends State<EntityConflictPage> {
  bool busy = false;
  String? error;
  String? subject;
  @override
  void initState() {
    super.initState();
    loadSubject();
  }

  Future<void> loadSubject() async {
    if (widget.conflict['table'] != 3) return;
    final ids = (widget.conflict['id'] as String).split(':');
    try {
      final contact = await widget.model.get(ids[1]);
      final groups = await widget.model.groups({'operation': 'list'}) as List;
      final group = groups.where((g) => g['id'] == ids[0]).firstOrNull;
      if (mounted) {
        setState(
          () => subject =
              '${group?['name'] ?? '群组暂不可用'} · ${contact?['data']['display_name'] ?? '联系人暂不可用'}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
  }

  Future<void> resolve(String? value) async {
    final yes = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: const Text('采用此结果？'),
        content: Text(
          value == null
              ? '删除群组，不删除联系人。'
              : value == 'joined'
              ? '将联系人加入群组'
              : value == 'left'
              ? '将联系人移出群组'
              : '群组名称：$value',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('采用'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.model.groups({
        'operation': 'resolve',
        'table': widget.conflict['table'],
        'id': widget.conflict['id'],
        'observed': (widget.conflict['candidates'] as List)
            .map((c) => c['version'])
            .toList(),
        'value': value,
      });
      await widget.model.refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.conflict['table'] == 2;
    return PopScope(
      canPop: !busy,
      child: AppPage(
        navigationBar: AppNavigation(title: Text(group ? '群组冲突' : '成员关系冲突')),
        body: ListView(
          padding: AppTokens.pagePadding,
          children: [
            if (error != null) AppStatus(error!, kind: AppStatusKind.error),
            if (subject != null) Text(subject!),
            const Text('选择明确结果。尚未观察到的新版本仍会保留。'),
            AppGroup(
              children: [
                for (final c in widget.conflict['candidates'] as List)
                  AppRow(
                    title: Text(
                      c['row'] == null
                          ? '删除版本'
                          : group
                          ? c['row'][1]
                          : c['row'][3] == 'joined'
                          ? '加入群组'
                          : '移出群组',
                    ),
                    subtitle: Text('设备：${c['version']['device']}'),
                    onTap: busy
                        ? null
                        : () => resolve(
                            c['row'] == null
                                ? (group ? null : 'left')
                                : group
                                ? c['row'][1]
                                : c['row'][3],
                          ),
                  ),
              ],
            ),
            if (group)
              AppButton(
                onPressed: busy
                    ? null
                    : () async {
                        final name = await groupNameDialog(context, '');
                        if (name != null) await resolve(name);
                      },
                child: const Text('编辑合并名称'),
              ),
          ],
        ),
      ),
    );
  }
}
