import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'directory_data.dart';
import 'list_row.dart';
import 'search_page.dart';

class ContactDirectoryPage extends StatefulWidget {
  final AppModel model;
  final Widget? leading;
  final List<Widget> notices;
  final VoidCallback onCreate;
  final Future<void> Function(String) onOpen;
  const ContactDirectoryPage({
    super.key,
    required this.model,
    this.leading,
    this.notices = const [],
    required this.onCreate,
    required this.onOpen,
  });
  @override
  State<ContactDirectoryPage> createState() => _ContactDirectoryPageState();
}

class _ContactDirectoryPageState extends State<ContactDirectoryPage> {
  final scroll = ScrollController();
  double listStart = 0;
  String? selected;
  AppModel get m => widget.model;
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  (ContactSection, int) itemAt(int index) {
    for (final section in m.contactSections) {
      if (index <= section.count) return (section, index - 1);
      index -= section.count + 1;
    }
    throw RangeError.index(index, m.contactSections);
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    final rowHeight = math.max(
      68.0,
      scale.scale(17) * 1.3 + scale.scale(13) * 1.4 + 20,
    );
    final headerHeight = math.max(36.0, scale.scale(13) * 1.4 + 16);
    final pinnedHeight = MediaQuery.paddingOf(context).top + 44;
    void jump(String initial) {
      if (!scroll.hasClients) return;
      var offset = listStart - pinnedHeight;
      for (final section in m.contactSections) {
        if (section.initial == initial) {
          setState(() => selected = initial);
          final end = math.max(
            0.0,
            listStart +
                m.contactTotal * rowHeight +
                m.contactSections.length * headerHeight +
                20 -
                scroll.position.viewportDimension,
          );
          scroll.jumpTo(offset.clamp(0, end));
          m.loadContactPage(section.offset);
          return;
        }
        offset += headerHeight + section.count * rowHeight;
      }
    }

    return Stack(
      children: [
        LargeTitlePage(
          controller: scroll,
          title: m.groupTitle,
          leading: widget.leading,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIconButton(
                tooltip: '搜索联系人',
                icon: const Icon(CupertinoIcons.search),
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => ContactSearchPage(
                      model: m,
                      group: m.group,
                      groupTitle: m.groupTitle,
                      onOpen: widget.onOpen,
                    ),
                  ),
                ),
              ),
              AppIconButton(
                tooltip: '新建联系人',
                onPressed: widget.onCreate,
                icon: const Icon(CupertinoIcons.add),
              ),
            ],
          ),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: m.refresh),
            if (widget.notices.isNotEmpty || m.listError != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: AppTokens.pagePadding,
                  child: AppSectionList(
                    children: [
                      ...widget.notices,
                      if (m.listError != null)
                        AppStatus(
                          m.listError!,
                          kind: AppStatusKind.error,
                          onRetry: () => m.load(),
                        ),
                    ],
                  ),
                ),
              ),
            if (m.loading) const SliverToBoxAdapter(child: AppLoadingState()),
            if (!m.loading && m.listError == null && m.contactTotal == 0)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState('还没有联系人', message: '轻点右上角 ＋ 添加第一位联系人。'),
              ),
            SliverLayoutBuilder(
              builder: (context, constraints) {
                listStart = constraints.precedingScrollExtent;
                return SliverPadding(
                  padding: const EdgeInsets.only(
                    left: 16,
                    right: 36,
                    bottom: 20,
                  ),
                  sliver: SliverVariedExtentList.builder(
                    itemCount: m.contactTotal + m.contactSections.length,
                    itemExtentBuilder: (i, _) =>
                        itemAt(i).$2 < 0 ? headerHeight : rowHeight,
                    itemBuilder: (context, i) {
                      final (section, local) = itemAt(i);
                      if (local < 0) {
                        return Semantics(
                          header: true,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: Text(
                                section.initial,
                                style: AppTheme.of(context).text.bodySmall,
                              ),
                            ),
                          ),
                        );
                      }
                      final index = section.offset + local;
                      final contact = m.contactAt(index);
                      final error = m.contactPageErrors[index ~/ 50 * 50];
                      if (contact == null && error == null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) m.loadContactPage(index);
                        });
                      }
                      return AppListItem(
                        first: local == 0,
                        last: local == section.count - 1,
                        alignment: AppAlignment.avatar,
                        child: SizedBox(
                          height: rowHeight - 1,
                          child: Center(
                            child: contact != null
                                ? ContactListRow(
                                    contact: contact,
                                    onTap: () =>
                                        widget.onOpen(contact['id'] as String),
                                  )
                                : error != null
                                ? AppButton(
                                    onPressed: () =>
                                        m.loadContactPage(index, retry: true),
                                    child: const Text('加载失败，轻点重试'),
                                  )
                                : const CupertinoActivityIndicator(),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
        if (m.contactSections.isNotEmpty)
          Positioned(
            right: 0,
            top: pinnedHeight + 16,
            bottom: 16,
            width: 32,
            child: AppAlphabetIndex(
              letters: m.contactSections.map((s) => s.initial).toList(),
              selected: selected,
              onSelected: jump,
            ),
          ),
      ],
    );
  }
}
