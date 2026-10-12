import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';

class ContactGroups extends StatefulWidget {
  final AppModel model;
  final String contactId;
  const ContactGroups(this.model, this.contactId, {super.key});
  @override
  State<ContactGroups> createState() => _ContactGroupsState();
}

class _ContactGroupsState extends State<ContactGroups> {
  List<Map<String, dynamic>> rows = [];
  Set<String> selected = {};
  String? error;
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = (await widget.model.groups({
        'operation': 'contact_groups',
        'id': widget.contactId,
      }) as List).map(object).toList();
      if (mounted) {
        setState(() {
          rows = result;
          selected = {
            for (final r in rows)
              if (r['state'] == 'joined') r['id'] as String,
          };
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.model.groups({
        'operation': 'set_contact_groups',
        'id': widget.contactId,
        'changes': [
          for (final r in rows)
            if ((r['state'] == 'joined') != selected.contains(r['id']))
              {
                'group_id': r['id'],
                'expected': r['state'],
                'joined': selected.contains(r['id']),
              },
        ],
      });
      await widget.model.refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AppSelectionPageShell(
    title: '所属群组',
    busy: busy,
    onDone: loading ? null : save,
    body: ListView(
      padding: AppTokens.pagePadding,
      children: [
        if (error != null) AppStatus(error!, kind: AppStatusKind.error),
        if (error != null)
          AppButton(onPressed: load, child: const Text('重新加载')),
        if (loading) const AppLoadingState(),
        if (!loading && rows.isEmpty)
          const AppEmptyState('尚未创建群组，请从联系人首页的“列表”创建'),
        AppGroup(
          children: [
            for (final r in rows)
              AppSelectionRow(
                title: r['name'] as String,
                selected: selected.contains(r['id']),
                subtitle:
                    r['member_conflict'] == true || r['has_conflict'] == true
                    ? '请先处理冲突'
                    : null,
                onTap:
                    busy ||
                        r['member_conflict'] == true ||
                        r['has_conflict'] == true
                    ? null
                    : () => setState(() {
                        if (!selected.add(r['id'] as String)) {
                          selected.remove(r['id']);
                        }
                      }),
              ),
          ],
        ),
      ],
    ),
  );
}
