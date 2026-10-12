import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';

import 'src/rust/frb_generated.dart';
import 'model.dart';
import 'groups/pages.dart';
import 'contacts/relations_view.dart';
import 'groups/contact_groups.dart';
import 'groups/conflict_page.dart';
import 'editor.dart';
import 'contacts/contact_content.dart';
import 'contacts/fields.dart';
import 'settings.dart';
import 'design.dart';
import 'contacts/date_format.dart' show dateType, dateText;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(CardWeaveApp(model: AppModel()));
}

class CardWeaveApp extends StatelessWidget {
  final AppModel model;
  const CardWeaveApp({super.key, required this.model});
  @override
  Widget build(BuildContext context) => CupertinoApp(
    debugShowCheckedModeBanner: false,
    title: 'CardWeave',
    builder: (context, child) {
      final theme = AppTheme(MediaQuery.platformBrightnessOf(context));
      return CupertinoTheme(
        data: theme.cupertino,
        child: DefaultTextStyle(style: theme.text.bodyLarge, child: child!),
      );
    },
    home: Home(model),
  );
}

class Home extends StatefulWidget {
  final AppModel model;
  const Home(this.model, {super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int tab = 0;
  String? savedMessage, syncError;
  Timer? debounce;
  final search = TextEditingController();
  AppModel get m => widget.model;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(m.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      m.host.cancel();
      unawaited(m.command('close'));
    }
  }

  Future<void> openEditor() async {
    final saved = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => ContactEditor(m),
      ),
    );
    if (saved == true && mounted) setState(() => savedMessage = '已保存到本机');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: m,
    builder: (context, _) {
      if (!m.ready) {
        return const AppPage(body: AppLoadingState());
      }
      if (m.startupError != null) {
        return AppPage(
          body: Center(
            child: AppStatus(
              m.startupError!,
              kind: AppStatusKind.error,
              onRetry: m.start,
            ),
          ),
        );
      }
      if (!m.initialized) return Welcome(m);
      const destinations = [
        AppTabItem(CupertinoIcons.person_2, '联系人'),
        AppTabItem(CupertinoIcons.arrow_2_circlepath, '同步'),
        AppTabItem(CupertinoIcons.gear, '设置'),
      ];
      return AppPage(
        safeTop: false,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTokens.width),
            child: IndexedStack(
              index: tab,
              children: [contacts(), syncPage(), SettingsPage(m)],
            ),
          ),
        ),
        bottomBar: AppTabs(
          index: tab,
          onChanged: (v) => setState(() => tab = v),
          items: destinations,
        ),
      );
    },
  );
  Widget conflictBanner() => SurfaceBox(
    child: AppRow(
      leading: const Icon(CupertinoIcons.square_stack),
      title: Text('${m.conflicts.length} 项资料需要处理冲突'),
      subtitle: const Text('多个版本会保留，直到你作出选择'),
      trailing: const Icon(CupertinoIcons.chevron_forward),
      onTap: () => Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => ConflictList(m)),
      ),
    ),
  );
  Widget contacts() => AppPagination(
    enabled: tab == 0 && m.more && !m.loading && m.listError == null,
    onLoad: () => m.load(),
    builder: (context, controller) => LargeTitlePage(
      controller: controller,
      title: m.groupTitle,
      leading: m.supportsGroups
          ? AppButton(
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => GroupLists(m)),
              ),
              child: const Text('列表'),
            )
          : null,
      trailing: AppIconButton(
        tooltip: '新建联系人',
        onPressed: openEditor,
        icon: const Icon(CupertinoIcons.add),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: m.refresh),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSearchField(
                  controller: search,
                  onClear: () {
                    debounce?.cancel();
                    search.clear();
                    m.search = '';
                    m.load(reset: true);
                  },
                  onChanged: (v) {
                    debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 250), () {
                      m.search = v;
                      m.load(reset: true);
                    });
                  },
                ),
                if (m.conflicts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: conflictBanner(),
                  ),
                if (savedMessage != null)
                  AppStatus(savedMessage!, kind: AppStatusKind.success),
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
        if (m.contacts.isEmpty && !m.loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AppEmptyState(
              m.search.isEmpty ? '还没有联系人' : '没有找到匹配的联系人',
              message: m.search.isEmpty ? '轻点右上角 ＋ 添加第一位联系人。' : '试试其他姓名或联系方式。',
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: m.contacts.length,
            itemBuilder: (context, i) {
              final contact = m.contacts[i], data = object(contact['data']);
              final phones = data['phones'] as List,
                  emails = data['emails'] as List;
              final name = data['display_name'] as String;
              final subtitle = phones.isNotEmpty
                  ? phones.first['value'] as String
                  : emails.isNotEmpty
                  ? emails.first['value'] as String
                  : data['organization'] as String;
              return AppListItem(
                first: i == 0,
                last: i == m.contacts.length - 1,
                alignment: AppAlignment.avatar,
                child: AppRow(
                  leading: ContactAvatar(name),
                  title: Text(
                    name,
                    style: AppTheme.of(context).text.titleMedium,
                  ),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  trailing: contact['has_conflict'] == true
                      ? Semantics(
                          label: '有待处理冲突',
                          child: Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            size: 20,
                          ),
                        )
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => ContactDetail(m, contact['id']),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: AppTokens.pagePadding,
            child: Center(
              child: m.loading
                  ? const CupertinoActivityIndicator()
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    ),
  );
  Widget syncPage() => GroupedPageList(
    title: '同步',
    children: [
      AppSection(
        title: '当前状态',
        child: AppGroup(
          children: [
            AppRow(
              title: const Text('待上传更改'),
              trailing: Text('${m.status['pending_outbox'] ?? 0} 项'),
            ),
            AppRow(
              title: const Text('待处理冲突'),
              trailing: Text('${m.status['conflict_count'] ?? 0} 位联系人 ›'),
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => ConflictList(m)),
              ),
            ),
            if (m.lastSync != null) ...[
              AppRow(
                title: const Text('最近完成扫描'),
                subtitle: Text(
                  m.lastSync!.replaceFirst('T', ' ').split('.').first,
                ),
              ),
            ],
          ],
        ),
      ),
      if (m.status['protocol_healthy'] == false) ...[
        const AppStatus(
          '部分远端数据尚未处理完成。请重试同步；若持续失败，请检查远端数据与服务。',
          kind: AppStatusKind.warning,
        ),
      ],
      if (m.conflicts.isNotEmpty) ...[
        AppSection(title: '需要你的选择', child: conflictBanner()),
      ],
      if (m.syncMessage != null) ...[
        AppSection(
          title: '本轮同步结果',
          child: AppStatus(m.syncMessage!, kind: AppStatusKind.success),
        ),
      ],
      SurfaceBox(
        child: AppRow(
          leading: m.syncing ? const CupertinoActivityIndicator() : null,
          title: Text(
            m.syncing
                ? (m.cancelling ? '正在取消同步' : '取消同步')
                : m.config.isEmpty
                ? '配置同步位置'
                : '立即同步',
            style: TextStyle(color: AppTheme.of(context).colors.primary),
          ),
          onTap: m.cancelling
              ? null
              : () async {
                  if (m.syncing) {
                    m.cancel();
                    return;
                  }
                  if (m.config.isEmpty) {
                    setState(() => tab = 2);
                    return;
                  }
                  setState(() => syncError = null);
                  try {
                    await m.synchronize();
                  } catch (e) {
                    if (mounted) setState(() => syncError = message(e));
                  }
                },
        ),
      ),
      if (syncError != null) AppStatus(syncError!, kind: AppStatusKind.error),
      AppSection(
        title: '同步位置',
        child: AppGroup(
          children: [
            AppRow(
              leading: const Icon(CupertinoIcons.cloud),
              title: Text(
                m.config.isEmpty
                    ? '尚未配置'
                    : m.config['type'] == 's3'
                    ? 'S3 兼容存储'
                    : 'WebDAV',
              ),
              subtitle: const Text('连接设置与账号'),
              trailing: const Icon(CupertinoIcons.chevron_forward),
              onTap: () => setState(() => tab = 2),
            ),
          ],
        ),
      ),
      Text(
        '本轮结果只描述当前同步；并发修改会作为冲突保留。',
        style: AppTheme.of(context).text.bodySmall,
      ),
    ],
  );
}

class Welcome extends StatefulWidget {
  final AppModel model;
  const Welcome(this.model, {super.key});
  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  bool busy = false;
  String? error;
  final join = TextEditingController();
  @override
  void dispose() {
    join.dispose();
    super.dispose();
  }

  Future<void> create(bool joining) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Map<String, dynamic>? info;
      if (joining) {
        info = object(jsonDecode(join.text));
        final ok = await showCupertinoDialog<bool>(
          context: context,
          builder: (c) => AppDialog(
            title: const Text('加入这个通讯录？'),
            content: Text(
              '通讯录：${info!['dataset']}\n同步位置：${info['backend']?['endpoint'] ?? '稍后设置'}\n\n加入信息不包含访问凭据。此设备会创建自己的身份。',
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('返回'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(c, true),
                child: const Text('确认加入'),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
      await widget.model.create(info);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTokens.width),
          child: ListView(
            shrinkWrap: true,
            padding: AppTokens.pagePadding,
            children: [
              Icon(
                CupertinoIcons.person_2,
                size: 76,
                color: AppTheme.of(context).colors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'CardWeave',
                textAlign: TextAlign.center,
                style: AppTheme.of(context).text.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                '联系人留在你的设备上\n需要时，再与你的其他设备同步',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              if (error != null) AppStatus(error!, kind: AppStatusKind.error),
              AppButton.filled(
                onPressed: busy ? null : () => create(false),
                child: Text(busy ? '正在准备…' : '创建本地通讯录'),
              ),
              const SizedBox(height: 28),
              AppDisclosure(
                title: const Text('已有通讯录？加入现有通讯录'),
                children: [
                  AppInput(
                    controller: join,
                    label: '粘贴另一台设备的加入信息',
                    minLines: 3,
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    onPressed: busy ? null : () => create(true),
                    child: const Text('检查并加入'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ContactDetail extends StatefulWidget {
  final AppModel model;
  final String id;
  const ContactDetail(this.model, this.id, {super.key});
  @override
  State<ContactDetail> createState() => _ContactDetailState();
}

class _ContactDetailState extends State<ContactDetail> {
  Map<String, dynamic>? contact;
  String? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final value = await widget.model.get(widget.id);
      if (mounted) setState(() => contact = value);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: AppNavigation(
      title: const Text(''),
      actions: [
        if (contact != null)
          AppButton(
            onPressed: contact!['has_conflict'] == true
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      CupertinoPageRoute(
                        fullscreenDialog: true,
                        builder: (_) =>
                            ContactEditor(widget.model, original: contact),
                      ),
                    );
                    await load();
                  },
            child: const Text('编辑'),
          ),
      ],
    ),
    body: loading
        ? const AppLoadingState()
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: AppTokens.width),
              child: AppSectionScrollView(
                children: [
                  if (error != null)
                    AppStatus(error!, kind: AppStatusKind.error),
                  if (contact == null)
                    const AppEmptyState('联系人已不存在。')
                  else ...[
                    if (contact!['has_conflict'] == true)
                      SurfaceBox(
                        child: AppRow(
                          title: const Text('此联系人有多个版本'),
                          subtitle: const Text('请先处理冲突，再编辑或删除。'),
                          trailing: const Icon(CupertinoIcons.chevron_forward),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => ConflictList(widget.model),
                            ),
                          ).then((_) => load()),
                        ),
                      ),
                    ContactContent(
                      object(contact!['data']),
                      showHero: true,
                      includeRelations: false,
                    ),
                    if (widget.model.supportsGroups)
                      AppGroup(
                        children: [
                          AppRow(
                            title: const Text('群组'),
                            onTap: () => Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) =>
                                    ContactGroups(widget.model, widget.id),
                              ),
                            ),
                          ),
                        ],
                      ),
                    if ((contact!['data']['relations'] as List? ?? [])
                        .isNotEmpty)
                      ContactRelationsView(
                        widget.model,
                        object(contact!['data']),
                        onOpen: (id) async {
                          await Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => ContactDetail(widget.model, id),
                            ),
                          );
                          await load();
                        },
                      ),
                    AppButton.icon(
                      onPressed: contact!['has_conflict'] == true
                          ? null
                          : () async {
                              final ok = await showCupertinoDialog<bool>(
                                context: context,
                                builder: (c) => AppDialog(
                                  title: const Text('删除联系人？'),
                                  content: const Text(
                                    '删除先保存在本机，下次同步后传递到其他设备。并发编辑仍可能形成冲突。',
                                  ),
                                  actions: [
                                    CupertinoDialogAction(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('取消'),
                                    ),
                                    CupertinoDialogAction(
                                      isDefaultAction: true,
                                      onPressed: () => Navigator.pop(c, true),
                                      isDestructiveAction: true,
                                      child: const Text('确认删除'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                try {
                                  await widget.model.delete(contact!);
                                  if (context.mounted) Navigator.pop(context);
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => error = message(e));
                                  }
                                }
                              }
                            },
                      icon: const Icon(CupertinoIcons.trash),
                      label: Text(
                        '删除联系人',
                        style: TextStyle(
                          color: AppTheme.of(context).colors.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
  );
}

class ConflictList extends StatelessWidget {
  final AppModel model;
  const ConflictList(this.model, {super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => AppPage(
      navigationBar: AppNavigation(title: const Text('处理冲突')),
      body: model.conflicts.isEmpty
          ? const AppEmptyState('没有待处理的冲突')
          : AppSectionScrollView(
              children: [
                const Text('资料在不同设备上被修改。请选择保留的版本或编辑合并结果。'),
                ...model.conflicts.map((conflict) {
                  if (conflict['entity_type'] != null) {
                    return AppRow(
                      title: Text(
                        conflict['entity_type'] == 'group' ? '群组冲突' : '成员关系冲突',
                      ),
                      subtitle: Text(conflict['title'] as String? ?? ''),
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) =>
                              EntityConflictPage(model, copy(conflict)),
                        ),
                      ),
                    );
                  }
                  final candidates = conflict['candidates'] as List;
                  final named = candidates.where((c) => c['contact'] != null);
                  return SurfaceBox(
                    child: AppRow(
                      leading: const Icon(CupertinoIcons.square_stack),
                      title: Text(
                        named.isEmpty
                            ? '已删除联系人'
                            : named.first['contact']['data']['display_name'],
                      ),
                      subtitle: Text(
                        '${candidates.length} 个候选版本${candidates.any((c) => c['contact'] == null) ? ' · 含删除版本' : ''}',
                      ),
                      trailing: const Icon(CupertinoIcons.chevron_forward),
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => ConflictPage(model, copy(conflict)),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    ),
  );
}

class ConflictPage extends StatefulWidget {
  final AppModel model;
  final Map<String, dynamic> conflict;
  const ConflictPage(this.model, this.conflict, {super.key});
  @override
  State<ConflictPage> createState() => _ConflictPageState();
}

class _ConflictPageState extends State<ConflictPage> {
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final candidates = widget.conflict['candidates'] as List;
    final keys = contactFieldLabels.keys;
    final differences = {
      for (final k in keys)
        if (candidates.any((c) {
              final value = c['contact']?['data']?[k];
              return value != null &&
                  value != '' &&
                  (value is! List || value.isNotEmpty);
            }) &&
            candidates
                    .map((c) => jsonEncode(c['contact']?['data']?[k]))
                    .toSet()
                    .length >
                1)
          k,
    };
    return AppPage(
      navigationBar: AppNavigation(title: const Text('选择最终版本')),
      body: AppSectionScrollView(
        children: [
          const Text('下面列出不同的字段。请选择保留的完整版本，也可以查看完整资料或编辑合并。之后到达的新版本仍会保留。'),
          if (error != null) AppStatus(error!, kind: AppStatusKind.error),
          for (var i = 0; i < candidates.length; i++)
            SurfaceBox(
              child: Padding(
                padding: AppTokens.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '版本 ${i + 1}',
                      style: AppTheme.of(context).text.titleLarge,
                    ),
                    Text(
                      '设备 ${candidates[i]['version']['device'].toString().substring(0, 8)}',
                      style: AppTheme.of(context).text.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    if (candidates[i]['contact'] == null)
                      const AppRow(
                        leading: Icon(CupertinoIcons.trash),
                        title: Text('删除版本'),
                        subtitle: Text('保留此版本将删除联系人。'),
                      )
                    else ...[
                      for (final field in differences)
                        AppInfoRow(
                          changed: true,
                          label: contactFieldLabels[field] ?? field,
                          value: (conflictValue(
                            object(candidates[i]['contact']['data']),
                            field,
                          )),
                        ),
                      AppDisclosure(
                        title: const Text('查看完整版本'),
                        children: [
                          ContactContent(
                            object(candidates[i]['contact']['data']),
                            differences: differences,
                            grouped: false,
                          ),
                          ContactRelationsView(
                            widget.model,
                            object(candidates[i]['contact']['data']),
                            comparison: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 12,
                      children: [
                        AppButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final chosen = candidates[i]['contact'];
                                  final ok = await showCupertinoDialog<bool>(
                                    context: context,
                                    builder: (c) => AppDialog(
                                      title: Text(
                                        chosen == null
                                            ? '确认采用删除版本？'
                                            : '确认采用此版本？',
                                      ),
                                      content: const Text(
                                        '结果先保存在本机，需要再次同步到其他设备。',
                                      ),
                                      actions: [
                                        CupertinoDialogAction(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('取消'),
                                        ),
                                        CupertinoDialogAction(
                                          isDefaultAction: true,
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: const Text('确认采用'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true) return;
                                  setState(() => saving = true);
                                  try {
                                    await widget.model.resolve(
                                      widget.conflict,
                                      chosen == null
                                          ? null
                                          : object(chosen['data']),
                                    );
                                    if (context.mounted) Navigator.pop(context);
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() => error = message(e));
                                    }
                                  } finally {
                                    if (mounted) setState(() => saving = false);
                                  }
                                },
                          child: Text(
                            candidates[i]['contact'] == null
                                ? '采用删除版本'
                                : '采用此版本',
                          ),
                        ),
                        if (candidates[i]['contact'] != null)
                          AppButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    final saved = await Navigator.push<bool>(
                                      context,
                                      CupertinoPageRoute(
                                        fullscreenDialog: true,
                                        builder: (_) => ContactEditor(
                                          widget.model,
                                          seed: object(
                                            candidates[i]['contact']['data'],
                                          ),
                                          conflict: widget.conflict,
                                        ),
                                      ),
                                    );
                                    if (saved == true && context.mounted) {
                                      Navigator.pop(context);
                                    }
                                  },
                            child: const Text('以此为基础合并'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String conflictValue(Map<String, dynamic> data, String field) {
  final value = data[field];
  if (field == 'dates') {
    return (value as List).isEmpty
        ? '未填写'
        : value
              .map((d) => '${dateType(object(d))}  ${dateText(object(d))}')
              .join('\n');
  }
  if (value is List) {
    return value.isEmpty
        ? '未填写'
        : value
              .map(
                (v) =>
                    '${v['label']}  ${v['value']}${v['target_contact_id'] == null ? '' : ' · 关联 ID：${v['target_contact_id']}'}'
                        .trim(),
              )
              .join('\n');
  }
  return value == null || value == '' ? '未填写' : value.toString();
}
