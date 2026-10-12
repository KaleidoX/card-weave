import 'dart:convert';

import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import '../contacts/selector.dart';

Future<String?> groupNameDialog(BuildContext context, String initial) async {
  return showCupertinoDialog<String>(
    context: context,
    builder: (_) => _GroupName(initial),
  );
}

class _GroupName extends StatefulWidget {
  final String initial;
  const _GroupName(this.initial);
  @override
  State<_GroupName> createState() => _GroupNameState();
}

class _GroupNameState extends State<_GroupName> {
  late final text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('群组名称'),
    content: CupertinoTextField(
      controller: text,
      autofocus: true,
      onChanged: (_) => setState(() {}),
    ),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      CupertinoDialogAction(
        onPressed:
            text.text.trim().isEmpty ||
                utf8.encode(text.text.trim()).length > 128 ||
                text.text.contains('\u0000')
            ? null
            : () => Navigator.pop(context, text.text.trim()),
        child: const Text('完成'),
      ),
    ],
  );
}

class GroupLists extends StatefulWidget {
  final AppModel model;
  final bool selectFilter;
  const GroupLists(this.model, {super.key, this.selectFilter = true});
  @override
  State<GroupLists> createState() => _GroupListsState();
}

class _GroupListsState extends State<GroupLists> {
  List<Map<String, dynamic>> rows = [];
  String draftName = '';
  String? error;
  bool busy = false, loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = (await widget.model.groups({'operation': 'list'}) as List)
          .map(object)
          .toList();
      if (mounted) {
        setState(() {
          rows = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> select(String? id, String title) async {
    widget.model.group = id;
    widget.model.groupTitle = title;
    await widget.model.load(reset: true);
    if (mounted) Navigator.pop(context);
  }

  Future<void> create() async {
    final name = await groupNameDialog(context, draftName);
    if (name == null || !mounted) return;
    draftName = name;
    setState(() => busy = true);
    try {
      await widget.model.groups({'operation': 'create', 'name': name});
      draftName = '';
      await widget.model.refresh();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: AppNavigation(
      title: const Text('列表'),
      actions: [
        AppButton(onPressed: busy ? null : create, child: const Text('新建群组')),
      ],
    ),
    body: ListView(
      padding: AppTokens.pagePadding,
      children: [
        if (error != null) AppStatus(error!, kind: AppStatusKind.error),
        if (error != null) AppButton(onPressed: load, child: const Text('重试')),
        if (loading) const AppLoadingState(),
        if (widget.selectFilter)
          AppGroup(
            children: [
              AppRow(
                title: const Text('全部联系人'),
                onTap: () => select(null, '联系人'),
              ),
              AppRow(title: const Text('未分组'), onTap: () => select('', '未分组')),
            ],
          ),
        const SectionLabel('群组'),
        if (!loading && rows.isEmpty) const AppEmptyState('尚未创建群组'),
        AppGroup(
          children: [
            for (final g in rows)
              AppRow(
                title: Text(g['name'] as String),
                subtitle: Text(
                  '${g['count']} 位联系人${g['pending'] == 0 ? '' : ' · ${g['pending']} 项待确认'}${g['duplicate'] == true ? ' · 名称重复' : ''}${g['has_conflict'] == true ? ' · 群组冲突' : ''}',
                ),
                onTap: g['has_conflict'] == true
                    ? null
                    : () => widget.selectFilter
                          ? select(g['id'] as String, g['name'] as String)
                          : manage(g),
                trailing: AppIconButton(
                  tooltip: '管理群组',
                  icon: const Icon(CupertinoIcons.ellipsis_circle),
                  onPressed: g['has_conflict'] == true ? null : () => manage(g),
                ),
              ),
          ],
        ),
      ],
    ),
  );
  Future<void> manage(Map<String, dynamic> g) async {
    await Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => GroupDetail(widget.model, g)),
    );
    await load();
  }
}

class GroupDetail extends StatefulWidget {
  final AppModel model;
  final Map<String, dynamic> group;
  const GroupDetail(this.model, this.group, {super.key});
  @override
  State<GroupDetail> createState() => _GroupDetailState();
}

class _GroupDetailState extends State<GroupDetail> {
  late String name = widget.group['name'] as String;
  String? renameDraft;
  List<Map<String, dynamic>> members = [];
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final rows = (await widget.model.groups({
        'operation': 'members',
        'id': widget.group['id'],
      }) as List).map(object).toList();
      for (final r in rows) {
        final c = await widget.model.get(r['contact_id'] as String);
        r['name'] = c?['data']['display_name'] ?? '联系人不可用';
      }
      if (mounted) setState(() => members = rows);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
  }

  Future<void> act(Map<String, dynamic> request) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.model.groups({
        ...request,
        'id': widget.group['id'],
        'expected': name,
      });
      await widget.model.refresh();
    } catch (e) {
      if (mounted) setState(() => error = message(e));
      rethrow;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> rename() async {
    final next = await groupNameDialog(context, renameDraft ?? name);
    if (next == null || !mounted) return;
    renameDraft = next;
    try {
      await act({'operation': 'rename', 'name': next});
      renameDraft = null;
      if (mounted) setState(() => name = next);
      if (widget.model.group == widget.group['id']) {
        widget.model.groupTitle = next;
      }
    } catch (_) {}
  }

  Future<void> selectMembers() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ContactSelector(
          widget.model,
          disabled: {
            for (final r in members)
              if (r['has_conflict'] == true) r['contact_id'] as String,
          },
          selected: {
            for (final r in members)
              if (r['state'] == 'joined') r['contact_id'] as String,
          },
          onSave: (selected) async {
            final previous = {
              for (final r in members) r['contact_id'] as String: r,
            };
            final changes = <Map<String, dynamic>>[];
            for (final id in {...previous.keys, ...selected}) {
              if ((previous[id]?['state'] == 'joined') !=
                  selected.contains(id)) {
                changes.add({
                  'contact_id': id,
                  'expected': previous[id]?['state'],
                  'joined': selected.contains(id),
                });
              }
            }
            await widget.model.groups({
              'operation': 'set_members',
              'id': widget.group['id'],
              'changes': changes,
            });
            await widget.model.refresh();
          },
        ),
      ),
    );
    await load();
  }

  Future<void> remove() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => AppDialog(
        title: const Text('删除群组？'),
        content: const Text('不会删除联系人。其他设备的并发修改可能需要处理冲突。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (widget.model.group == widget.group['id']) {
        widget.model.group = null;
        widget.model.groupTitle = '联系人';
      }
      await act({'operation': 'delete'});
      if (mounted) Navigator.pop(context);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: AppNavigation(title: Text(name)),
    body: ListView(
      padding: AppTokens.pagePadding,
      children: [
        if (error != null) AppStatus(error!, kind: AppStatusKind.error),
        AppGroup(
          children: [
            AppRow(title: const Text('重命名'), onTap: busy ? null : rename),
            AppRow(
              title: const Text('管理成员'),
              onTap: busy ? null : selectMembers,
            ),
          ],
        ),
        const SectionLabel('成员'),
        AppGroup(
          children: [
            for (final r in members)
              if (r['state'] == 'joined' || r['has_conflict'] == true)
                AppRow(
                  title: Text(r['name'] as String),
                  subtitle: r['has_conflict'] == true
                      ? const Text('成员关系待确认')
                      : null,
                ),
          ],
        ),
        AppButton(onPressed: busy ? null : remove, child: const Text('删除群组')),
      ],
    ),
  );
}
