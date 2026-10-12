import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';

class ContactSelector extends StatefulWidget {
  final AppModel model;
  final String? exclude;
  final Set<String> disabled;
  final Set<String>? selected;
  final Future<void> Function(Set<String>)? onSave;
  const ContactSelector(
    this.model, {
    super.key,
    this.exclude,
    this.disabled = const {},
    this.selected,
    this.onSave,
  });
  @override
  State<ContactSelector> createState() => _ContactSelectorState();
}

class _ContactSelectorState extends State<ContactSelector> {
  final search = TextEditingController();
  late final selected = {...?widget.selected};
  List<Map<String, dynamic>> rows = [];
  bool loading = true, busy = false, more = false;
  String? error;
  int generation = 0;
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

  Future<void> load({bool reset = true}) async {
    if (!reset && loading) return;
    final ticket = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (reset) rows = [];
    });
    try {
      final page = (await widget.model.command('list', {
        'search': search.text,
        'offset': rows.length,
      }) as List).map(object).toList();
      if (!mounted || ticket != generation) return;
      setState(() {
        rows.addAll(page);
        more = page.length == 50;
      });
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = message(e));
    }
    if (mounted && ticket == generation) setState(() => loading = false);
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.onSave!(selected);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => AppSelectionPageShell(
    title: widget.selected == null ? '选择联系人' : '已选 ${selected.length} 位',
    busy: busy,
    onDone: widget.onSave == null ? null : save,
    body: AppPagination(
      enabled: more && !loading && !busy && error == null,
      onLoad: () => load(reset: false),
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverPadding(
            padding: AppTokens.pagePadding,
            sliver: SliverToBoxAdapter(
              child: AppSectionList(
                children: [
                  AppSearchField(
                    controller: search,
                    onChanged: (_) => load(),
                    onClear: () {
                      search.clear();
                      load();
                    },
                  ),
                  if (error != null)
                    AppStatus(error!, kind: AppStatusKind.error),
                  if (error != null)
                    AppButton(
                      onPressed: () => load(reset: false),
                      child: const Text('重试'),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.page),
            sliver: SliverList.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final c = rows[index];
                if (c['id'] == widget.exclude) return const SizedBox.shrink();
                return AppListItem(
                  key: ValueKey(c['id']),
                  first:
                      index == 0 ||
                      (index == 1 && rows.first['id'] == widget.exclude),
                  last:
                      index == rows.length - 1 ||
                      (index == rows.length - 2 &&
                          rows.last['id'] == widget.exclude),
                  child: AppSelectionRow(
                    title: c['data']['display_name'] as String,
                    selected: selected.contains(c['id']),
                    subtitle:
                        (c['has_conflict'] == true ||
                            widget.disabled.contains(c['id']))
                        ? '请先处理联系人冲突'
                        : null,
                    onTap:
                        busy ||
                            (c['has_conflict'] == true ||
                                widget.disabled.contains(c['id']))
                        ? null
                        : () {
                            if (widget.selected == null) {
                              Navigator.pop(context, c);
                            } else {
                              setState(() {
                                if (!selected.add(c['id'] as String)) {
                                  selected.remove(c['id']);
                                }
                              });
                            }
                          },
                  ),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: AppSectionList(
              children: [
                if (loading) const AppLoadingState(),
                if (!loading && rows.isEmpty) const AppEmptyState('没有可选联系人'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
