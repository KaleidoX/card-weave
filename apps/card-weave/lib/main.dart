import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'src/rust/frb_generated.dart';
import 'model.dart';
import 'editor.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(CardWeaveApp(model: AppModel()));
}

class CardWeaveApp extends StatelessWidget {
  final AppModel model;
  const CardWeaveApp({super.key, required this.model});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'CardWeave',
    theme: theme(Brightness.light),
    darkTheme: theme(Brightness.dark),
    home: Home(model),
  );
  ThemeData theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff2855a8),
      brightness: brightness,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

void notice(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class Home extends StatefulWidget {
  final AppModel model;
  const Home(this.model, {super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int tab = 0;
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
      MaterialPageRoute(builder: (_) => ContactEditor(m)),
    );
    if (saved == true && mounted) notice(context, '已保存到本机');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: m,
    builder: (context, _) {
      if (!m.ready) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (m.startupError != null) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.startupError!),
                FilledButton(onPressed: m.start, child: const Text('重试')),
              ],
            ),
          ),
        );
      }
      if (!m.initialized) return Welcome(m);
      final content = switch (tab) {
        0 => contacts(),
        1 => syncPage(),
        _ => SettingsPage(m),
      };
      final destinations = const [
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: '通讯录',
        ),
        NavigationDestination(icon: Icon(Icons.sync), label: '同步'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
      ];
      return LayoutBuilder(
        builder: (context, size) => Scaffold(
          appBar: AppBar(
            title: Text(['通讯录', '同步', '设置'][tab]),
            actions: [
              if (tab == 0)
                IconButton(
                  tooltip: '刷新',
                  onPressed: m.syncing ? null : () => m.refresh(),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          body: Row(
            children: [
              if (size.maxWidth >= 700)
                NavigationRail(
                  selectedIndex: tab,
                  onDestinationSelected: (v) => setState(() => tab = v),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      label: Text('通讯录'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.sync),
                      label: Text('同步'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: Text('设置'),
                    ),
                  ],
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: size.maxWidth < 700
              ? NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (v) => setState(() => tab = v),
                  destinations: destinations,
                )
              : null,
          floatingActionButton: tab == 0
              ? FloatingActionButton.extended(
                  onPressed: openEditor,
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('新建联系人'),
                )
              : null,
        ),
      );
    },
  );
  Widget conflictBanner() => Card(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: ListTile(
      leading: const Icon(Icons.difference_outlined),
      title: Text('${m.conflicts.length} 位联系人需要处理冲突'),
      subtitle: const Text('多个版本会保留，直到你作出选择'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ConflictList(m)),
      ),
    ),
  );
  Widget contacts() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: TextField(
          controller: search,
          decoration: InputDecoration(
            hintText: '搜索姓名、电话、邮箱或备注',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    onPressed: () {
                      search.clear();
                      m.search = '';
                      m.load(reset: true);
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: (v) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 250), () {
              m.search = v;
              m.load(reset: true);
            });
          },
        ),
      ),
      if (m.conflicts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: conflictBanner(),
        ),
      if (m.listError != null && m.contacts.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(child: Text(m.listError!)),
              TextButton(onPressed: () => m.load(), child: const Text('重新加载')),
            ],
          ),
        ),
      if (m.syncing) const LinearProgressIndicator(),
      Expanded(
        child: m.contacts.isEmpty && !m.loading
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        m.listError != null
                            ? Icons.error_outline
                            : Icons.people_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        m.listError ??
                            (m.search.isEmpty ? '你的联系人，从这里开始' : '没有找到匹配的联系人'),
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        m.search.isEmpty ? '离线也能记录，准备好后再同步。' : '试试其他姓名或联系方式。',
                      ),
                      if (m.listError != null)
                        TextButton(
                          onPressed: () => m.load(reset: true),
                          child: const Text('重新加载'),
                        ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: m.contacts.length + 1,
                itemBuilder: (c, i) {
                  if (i == m.contacts.length) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: m.loading
                            ? const CircularProgressIndicator()
                            : m.more
                            ? TextButton(
                                onPressed: () => m.load(),
                                child: const Text('加载更多'),
                              )
                            : Text(m.contacts.isEmpty ? '' : '已显示全部匹配联系人'),
                      ),
                    );
                  }
                  final contact = m.contacts[i], data = object(contact['data']);
                  final phones = data['phones'] as List;
                  final emails = data['emails'] as List;
                  final name = data['display_name'] as String;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(child: Text(name.characters.first)),
                    title: Text(name),
                    subtitle: Text(
                      phones.isNotEmpty
                          ? phones.first['value']
                          : emails.isNotEmpty
                          ? emails.first['value']
                          : data['organization'] as String,
                    ),
                    trailing: contact['has_conflict'] == true
                        ? const Tooltip(
                            message: '有待处理冲突',
                            child: Icon(Icons.warning_amber),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ContactDetail(m, contact['id']),
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
  Widget syncPage() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Icon(
        m.syncing ? Icons.sync : Icons.cloud_outlined,
        size: 64,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 20),
      Text(
        m.syncing ? (m.cancelling ? '正在取消同步' : '正在同步') : '由你决定何时同步',
        style: Theme.of(context).textTheme.headlineSmall,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      const Text('更改先保存在本机。同步会上传本机更改并获取其他设备的版本。', textAlign: TextAlign.center),
      const SizedBox(height: 24),
      Card(
        child: Column(
          children: [
            ListTile(
              title: const Text('待上传更改'),
              trailing: Text('${m.status['pending_outbox'] ?? 0}'),
            ),
            ListTile(
              title: const Text('待处理冲突'),
              trailing: Text('${m.status['conflict_count'] ?? 0}'),
            ),
            ListTile(
              title: const Text('同步位置'),
              subtitle: Text(m.config['endpoint'] as String? ?? '尚未配置'),
            ),
          ],
        ),
      ),
      if (m.lastSync != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '最近完成扫描：${m.lastSync!.replaceFirst("T", " ").split(".").first}',
          ),
        ),
      if (m.status['protocol_healthy'] == false)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('部分远端数据尚未处理完成。请重试同步；若持续失败，请检查远端数据与服务。'),
        ),
      if (m.conflicts.isNotEmpty) conflictBanner(),
      if (m.syncMessage != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(m.syncMessage!),
        ),
      const SizedBox(height: 16),
      if (m.syncing) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: m.cancelling ? null : m.cancel,
          child: const Text('取消同步'),
        ),
      ] else
        FilledButton.icon(
          onPressed: () async {
            if (m.config.isEmpty) {
              setState(() => tab = 2);
              return;
            }
            try {
              await m.synchronize();
            } catch (e) {
              if (mounted) notice(context, message(e));
            }
          },
          icon: const Icon(Icons.sync),
          label: Text(m.config.isEmpty ? '配置同步位置' : '立即同步'),
        ),
      const SizedBox(height: 16),
      const Text('本轮结果只描述当前同步；并发修改会作为冲突保留。'),
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
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('加入这个通讯录？'),
            content: Text(
              '通讯录：${info!['dataset']}\n同步位置：${info['backend']?['endpoint'] ?? '稍后设置'}\n\n加入信息不包含访问凭据。此设备会创建自己的身份。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('返回'),
              ),
              FilledButton(
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
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(28),
            children: [
              Icon(
                Icons.contacts_outlined,
                size: 76,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'CardWeave',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              const Text(
                '联系人留在你的设备上\n需要时，再与你的其他设备同步',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: busy ? null : () => create(false),
                child: Text(busy ? '正在准备…' : '创建本地通讯录'),
              ),
              const SizedBox(height: 28),
              ExpansionTile(
                title: const Text('已有通讯录？加入现有通讯录'),
                children: [
                  TextField(
                    controller: join,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '粘贴另一台设备的加入信息',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('联系人详情'),
      actions: [
        if (contact != null)
          IconButton(
            tooltip: '编辑联系人',
            icon: const Icon(Icons.edit_outlined),
            onPressed: contact!['has_conflict'] == true
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ContactEditor(widget.model, original: contact),
                      ),
                    );
                    await load();
                  },
          ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (error != null) Text(error!),
                  if (contact == null)
                    const Text('联系人已不存在。')
                  else ...[
                    if (contact!['has_conflict'] == true)
                      Card(
                        child: ListTile(
                          title: const Text('此联系人有多个版本'),
                          subtitle: const Text('请先处理冲突，再编辑或删除。'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ConflictList(widget.model),
                            ),
                          ).then((_) => load()),
                        ),
                      ),
                    ContactContent(object(contact!['data'])),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: contact!['has_conflict'] == true
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('删除联系人？'),
                                  content: const Text(
                                    '删除先保存在本机，下次同步后传递到其他设备。并发编辑仍可能形成冲突。',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(c, true),
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
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('删除联系人'),
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
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('处理冲突')),
      body: model.conflicts.isEmpty
          ? const Center(child: Text('没有待处理的冲突'))
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('同一联系人在不同设备上被修改。请选择保留的完整版本，或编辑合并结果。'),
                ),
                ...model.conflicts.map((conflict) {
                  final candidates = conflict['candidates'] as List;
                  final named = candidates.where((c) => c['contact'] != null);
                  return ListTile(
                    leading: const Icon(Icons.difference_outlined),
                    title: Text(
                      named.isEmpty
                          ? '已删除联系人'
                          : named.first['contact']['data']['display_name'],
                    ),
                    subtitle: Text(
                      '${candidates.length} 个候选版本${candidates.any((c) => c['contact'] == null) ? ' · 含删除版本' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConflictPage(model, copy(conflict)),
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
    final keys = emptyContact().keys;
    final differences = {
      for (final k in keys)
        if (candidates
                .map((c) => jsonEncode(c['contact']?['data']?[k]))
                .toSet()
                .length >
            1)
          k,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('选择最终版本')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('高亮字段在版本间不同。选择会覆盖你当前看到的这些候选；之后到达的新版本仍会保留。'),
          if (error != null) Text(error!),
          for (var i = 0; i < candidates.length; i++)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '版本 ${i + 1}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '设备 ${candidates[i]['version']['device'].toString().substring(0, 8)}',
                    ),
                    const SizedBox(height: 16),
                    if (candidates[i]['contact'] == null)
                      const ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('删除版本'),
                        subtitle: Text('保留此版本将删除联系人。'),
                      )
                    else
                      ContactContent(
                        object(candidates[i]['contact']['data']),
                        differences: differences,
                      ),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final chosen = candidates[i]['contact'];
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: Text(
                                        chosen == null
                                            ? '确认采用删除版本？'
                                            : '确认采用此版本？',
                                      ),
                                      content: const Text(
                                        '结果先保存在本机，需要再次同步到其他设备。',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
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
                          OutlinedButton(
                            onPressed: saving
                                ? null
                                : () async {
                                    final saved = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
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
