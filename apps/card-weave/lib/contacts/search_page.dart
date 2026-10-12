import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'list_row.dart';

class ContactSearchPage extends StatefulWidget {
  final AppModel model;
  final String? group;
  final String groupTitle;
  final Future<void> Function(String) onOpen;
  const ContactSearchPage({
    super.key,
    required this.model,
    this.group,
    required this.groupTitle,
    required this.onOpen,
  });
  @override
  State<ContactSearchPage> createState() => _ContactSearchPageState();
}

class _ContactSearchPageState extends State<ContactSearchPage> {
  final search = TextEditingController();
  Timer? debounce;
  int generation = 0;
  bool loading = false, more = false;
  String? error;
  List<Map<String, dynamic>> rows = [];
  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  void changed(String _) {
    debounce?.cancel();
    generation++;
    setState(() {
      rows = [];
      more = false;
      error = null;
      loading = search.text.trim().isNotEmpty;
    });
    if (loading) {
      debounce = Timer(
        const Duration(milliseconds: 250),
        () => load(reset: true),
      );
    }
  }

  Future<void> open(String id) async {
    await widget.onOpen(id);
    if (mounted) await load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if ((!reset && loading) || search.text.trim().isEmpty) return;
    final ticket = ++generation;
    final query = search.text.trim();
    setState(() {
      loading = true;
      error = null;
      if (reset) rows = [];
    });
    try {
      final result = widget.model.supportsGroups
          ? await widget.model.groups({
              'operation': 'contacts',
              'group': widget.group,
              'search': query,
              'offset': rows.length,
            })
          : await widget.model.command('list', {
              'search': query,
              'offset': rows.length,
            });
      if (!mounted || ticket != generation) return;
      final page = (result as List).map(object).map(contactSummary).toList();
      setState(() {
        rows.addAll(page);
        more = page.length == 50;
      });
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = message(e));
    }
    if (mounted && ticket == generation) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: const AppNavigation(title: Text('搜索联系人')),
    body: Column(
      children: [
        Padding(
          padding: AppTokens.pagePadding,
          child: AppSearchField(
            autofocus: true,
            controller: search,
            onChanged: changed,
            onClear: () {
              search.clear();
              changed('');
            },
          ),
        ),
        Expanded(
          child: AppPagination(
            enabled: more && !loading && error == null,
            onLoad: () => load(),
            builder: (context, controller) => CustomScrollView(
              controller: controller,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                if (error != null)
                  SliverToBoxAdapter(
                    child: AppStatus(
                      error!,
                      kind: AppStatusKind.error,
                      onRetry: () => load(),
                    ),
                  ),
                if (!loading && error == null && rows.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppEmptyState(
                      search.text.trim().isEmpty
                          ? '搜索${widget.groupTitle}'
                          : '没有找到匹配的联系人',
                      message: '输入姓名、电话、邮箱或其他联系人资料。',
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => AppListItem(
                      first: i == 0,
                      last: i == rows.length - 1,
                      alignment: AppAlignment.avatar,
                      child: ContactListRow(
                        contact: rows[i],
                        onTap: () => open(rows[i]['id'] as String),
                      ),
                    ),
                  ),
                ),
                if (loading) const SliverToBoxAdapter(child: AppLoadingState()),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
