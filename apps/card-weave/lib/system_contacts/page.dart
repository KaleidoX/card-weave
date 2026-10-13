import 'export/session.dart';

import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'mapping.dart';
import 'preview.dart';
import 'session.dart';
import 'strategy.dart';

class SystemContactsImportPage extends StatefulWidget {
  final AppModel model;
  const SystemContactsImportPage(this.model, {super.key});
  @override
  State<SystemContactsImportPage> createState() =>
      _SystemContactsImportPageState();
}

class _SystemContactsImportPageState extends State<SystemContactsImportPage> {
  final search = TextEditingController();
  ContactsImportSession? session;
  String? unavailable;
  bool preparing = true;
  @override
  void initState() {
    super.initState();
    prepare();
  }

  Future<void> prepare() async {
    try {
      final strategy = await systemContactsStrategy(
        convertSolarToLunar: (year, month, day) async => object(
          await widget.model.command('calendar_date', {
            'calendar': 'chinese_lunar',
            'year': year,
            'month': month,
            'day': day,
          }),
        ),
      );
      if (!mounted) return;
      if (strategy.importer == null) {
        unavailable = strategy.name;
      } else {
        session = ContactsImportSession(
          strategy: strategy.importer!,
          command: widget.model.command,
          refresh: widget.model.refresh,
          onImported: strategy.exporter == null
              ? null
              : (candidate) => associateImported(
                  strategy.exporter!,
                  widget.model.identity['dataset'] as String,
                  candidate.sourceId,
                  candidate.createdId!,
                  candidate.contact,
                ),
        );
        session!.addListener(update);
      }
    } catch (_) {
      unavailable = '无法连接系统通讯录，请重新打开此页面';
    }
    if (mounted) setState(() => preparing = false);
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    session?.removeListener(update);
    session?.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> import({bool retry = false}) async {
    final s = session!;
    if (widget.model.syncing) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (c) => AppDialog(
          title: const Text('同步正在进行'),
          content: const Text('请等待同步结束后再导入。'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(c),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final count = retry ? s.failedCount : s.selectedCount;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => AppDialog(
        title: Text(retry ? '重试 $count 位联系人？' : '导入 $count 位联系人？'),
        content: const Text(
          '所选资料将作为新联系人保存到 CardWeave，不覆盖已有联系人。包含提示的资料请先查看预览。导入后可手动同步。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await s.run(retry: retry);
  }

  Widget candidateRow(ImportCandidate c, ContactsImportSession s) {
    final subtitle = [
      if (c.createdId != null) '已导入',
      if (c.error != null) c.error!,
      ...c.duplicates,
      if (c.warnings.isNotEmpty) '有 ${c.warnings.length} 项转换提示，请查看预览',
      if (c.duplicates.isEmpty && c.error == null && c.createdId == null)
        ...[
          ...c.contact['phones'] as List? ?? [],
          ...c.contact['emails'] as List? ?? [],
        ].take(1).map((v) => v['value'] as String),
    ].join('\n');
    final canSelect =
        s.ready && !s.importing && c.createdId == null && c.error == null;
    return AppGroup(
      children: [
        AppRow(
          title: Text(c.name),
          subtitle: subtitle.isEmpty ? null : Text(subtitle),
          leading: Icon(
            c.selected
                ? CupertinoIcons.check_mark_circled_solid
                : c.createdId != null
                ? CupertinoIcons.check_mark
                : CupertinoIcons.circle,
          ),
          onTap: canSelect ? () => s.toggle(c) : null,
          trailing: AppIconButton(
            tooltip: '预览${c.name}',
            icon: const Icon(CupertinoIcons.info_circle),
            onPressed: s.importing
                ? null
                : () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => ImportContactPreview(c)),
                  ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final busy = s?.loading == true || s?.importing == true;
    final query = search.text.trim().toLowerCase();
    final rows =
        s?.candidates
            .where(
              (c) =>
                  query.isEmpty ||
                  c.name.toLowerCase().contains(query) ||
                  [
                    ...c.contact['phones'] as List? ?? [],
                    ...c.contact['emails'] as List? ?? [],
                  ].any(
                    (v) => (v['value'] as String).toLowerCase().contains(query),
                  ),
            )
            .toList() ??
        <ImportCandidate>[];
    return PopScope(
      canPop: !busy,
      child: AppPage(
        navigationBar: AppNavigation(
          title: const Text('导入系统通讯录'),
          leading: AppButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(s?.finished == true ? '完成' : '返回'),
          ),
        ),
        bottomBar: s?.ready == true
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: AppTokens.pagePadding,
                  child: AppButton.filled(
                    onPressed: busy || s!.selectedCount == 0
                        ? null
                        : () => import(),
                    child: Text(
                      s!.importing
                          ? '正在导入 ${s.processed}/${s.requested}'
                          : '导入已选 ${s.selectedCount} 位',
                    ),
                  ),
                ),
              )
            : null,
        body: AppSectionScrollView(
          children: [
            const Text('从手机系统通讯录选择资料，复制到 CardWeave。仅申请读取权限；不会修改系统联系人，也不会自动上传。'),
            if (preparing) const AppLoadingState(),
            if (unavailable != null) AppStatus(unavailable!),
            if (s != null) ...[
              if (!s.ready && !busy)
                AppGroup(
                  children: [
                    AppRow(
                      title: Text(
                        s.permission == 'blocked' ? '通讯录读取权限已关闭' : '读取系统通讯录',
                      ),
                      subtitle: const Text('授权后显示可导入的联系人，疑似重复项默认不选。'),
                      onTap: () => s.load(requestPermission: true),
                    ),
                    if (s.permission == 'blocked')
                      AppRow(
                        title: const Text('前往系统设置授权'),
                        onTap: s.strategy.openSettings,
                      ),
                  ],
                ),
              if (s.error != null)
                AppStatus(s.error!, kind: AppStatusKind.error),
              if (busy) ...[
                AppStatus(
                  s.loading
                      ? '正在读取与检查，已处理 ${s.candidates.length} 位'
                      : '正在导入 ${s.processed}/${s.requested}',
                ),
                AppButton(onPressed: s.cancel, child: const Text('停止')),
              ],
              if (s.finished)
                AppStatus(
                  '已导入 ${s.createdCount} 位，失败 ${s.failedCount} 位，待核对 ${s.uncertainCount} 位，其余 ${s.candidates.length - s.createdCount - s.failedCount - s.uncertainCount} 位未导入。已保存的资料可在同步页手动上传。',
                ),
              if (s.finished && s.failedCount > 0 && !busy)
                AppButton(
                  onPressed: () => import(retry: true),
                  child: const Text('仅重试失败项'),
                ),
              if (s.ready) ...[
                AppSearchField(
                  controller: search,
                  onChanged: (_) => setState(() {}),
                  onClear: () {
                    search.clear();
                    setState(() {});
                  },
                ),
                AppGroup(
                  children: [
                    AppRow(
                      title: const Text('全选无重复、可导入项'),
                      onTap: busy ? null : s.selectAllSafe,
                    ),
                    AppRow(
                      title: const Text('取消全选'),
                      onTap: busy ? null : s.deselectAll,
                    ),
                  ],
                ),
                if (rows.isEmpty)
                  AppEmptyState(s.candidates.isEmpty ? '系统通讯录为空' : '没有匹配的联系人'),
                ...rows.map((c) => candidateRow(c, s)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
