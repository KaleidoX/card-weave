import 'target_page.dart';

import 'package:flutter/cupertino.dart';

import '../../design.dart';
import '../../model.dart';
import '../strategy.dart';
import 'mapper.dart';
import 'session.dart';
import '../mapping.dart';

Future<SystemContactsStrategy> writeStrategies(AppModel model) =>
    systemContactsStrategy(
      convertSolarToLunar: (year, month, day) async => object(
        await model.command('calendar_date', {
          'calendar': 'chinese_lunar',
          'year': year,
          'month': month,
          'day': day,
        }),
      ),
    );

class SystemContactWritePage extends StatefulWidget {
  final AppModel model;
  final String id;
  const SystemContactWritePage(this.model, this.id, {super.key});
  @override
  State<SystemContactWritePage> createState() => _SystemContactWritePageState();
}

class _SystemContactWritePageState extends State<SystemContactWritePage> {
  SystemContactsStrategy? strategies;
  ContactWriteSession? session;
  String? error;
  final possibleDuplicates = <String>[];
  bool duplicatesChecked = false, newTargetConfirmed = false;
  bool busy = true, authorized = false, finished = false;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      error = e is StateError ? e.message.toString() : message(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> initialize() async {
    try {
      strategies = await writeStrategies(widget.model);
      if (strategies!.exporter == null) throw StateError('当前平台尚未支持写入');
      authorized = await strategies!.exporter!.permission() == 'granted';
      if (authorized) await load();
    } catch (e) {
      error = e is StateError ? e.message.toString() : message(e);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final contact = await widget.model.get(widget.id);
    if (contact == null) throw StateError('联系人已删除');
    session = ContactWriteSession(
      strategies!.exporter!,
      widget.model.identity['dataset'] as String,
      contact,
    );
    await session!.load();
    if (session!.target == null && !session!.pending) await checkDuplicates();
  }

  Future<void> checkDuplicates() async {
    possibleDuplicates.clear();
    final keys = contactKeys(object(session!.contact['data']));
    var after = '0';
    while (mounted) {
      final page = await strategies!.importer!.page(after);
      for (final summary in page) {
        final candidate = await strategies!.importer!.mapContact(
          summary,
          await strategies!.importer!.detail(summary['id'] as String),
        );
        if (contactKeys(candidate.contact).intersection(keys).isNotEmpty) {
          possibleDuplicates.add(summary['name'] as String);
        }
      }
      if (page.length < 50) break;
      final next = page.last['id'] as String;
      if (next == after) throw StateError('系统分页未前进');
      after = next;
    }
    duplicatesChecked = true;
  }

  Future<void> chooseTarget() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      CupertinoPageRoute(builder: (_) => SystemContactTargetPage(strategies!)),
    );
    if (result != null && mounted) {
      await run(() async {
        await session!.choose(result);
        finished = false;
      });
    }
  }

  Future<void> chooseAccount() async {
    final accounts = await strategies!.exporter!.accounts();
    if (!mounted) return;
    final choice = await showCupertinoModalPopup<Map<String, dynamic>>(
      context: context,
      builder: (c) => CupertinoActionSheet(
        title: const Text('新建到哪个账户？'),
        actions: [
          for (final a in accounts)
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(c, a),
              child: Text(
                a['name'] == null ? '设备本地通讯录' : '${a['name']} · ${a['type']}',
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(c),
          child: const Text('取消'),
        ),
      ),
    );
    if (choice != null) {
      await session!.choose(null, newAccount: choice);
      if (!duplicatesChecked) await checkDuplicates();
      newTargetConfirmed = true;
    }
  }

  Future<void> apply() async {
    final s = session!;
    if (!s.pending &&
        s.target == null &&
        (!duplicatesChecked || !newTargetConfirmed)) {
      throw StateError('请先核对疑似重复项，并选择新建账户');
    }
    final latest = await widget.model.get(widget.id);
    if (!s.pending &&
        (latest == null ||
            latest['has_conflict'] == true ||
            !sameValue(latest['data'], s.contact['data']))) {
      throw StateError('CardWeave 联系人已变化，请重新打开预览');
    }
    if (widget.model.syncing) throw StateError('请等待同步结束后再写入');
    if (!mounted) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (c) => AppDialog(
        title: Text(s.pending ? '核对并完成上次写入？' : '确认写入系统通讯录？'),
        content: Text(
          s.pending
              ? '先查询系统写入标记，已完成的创建不会重复执行。'
              : '仅写入已勾选字段。空值会清空对应内容；其他系统字段保持原样。',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认写入'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final current = await widget.model.get(widget.id);
    final recovered = s.pending
        ? await strategies!.exporter!.recover(
            s.association!['pending']['request']['token'] as String,
          )
        : null;
    if (recovered == null &&
        (current == null ||
            current['has_conflict'] == true ||
            !sameValue(
              strategies!.exporter!.mapper
                  .encode(object(current['data']))
                  .fields,
              s.pending ? s.association!['pending']['app'] : s.encoded.fields,
            ))) {
      throw StateError('App 资料在确认期间已变化，请重新准备；未执行的旧请求可以取消');
    }
    await s.write();
    finished = true;
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    return AppPage(
      navigationBar: AppNavigation(
        title: const Text('写入系统通讯录'),
        actions: [
          if (finished)
            AppButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('完成'),
            ),
        ],
      ),
      body: AppSectionScrollView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('手动复制或更新系统联系人，不会自动双向同步。系统账户可能由其所属服务继续同步。'),
          ),
          if (error != null) AppStatus(error!, kind: AppStatusKind.error),
          if (busy) const AppLoadingState(),
          if (!busy && !authorized && strategies?.exporter != null)
            AppGroup(
              children: [
                AppRow(
                  title: const Text('允许读取和写入通讯录'),
                  onTap: () => run(() async {
                    authorized =
                        await strategies!.exporter!.permission(request: true) ==
                        'granted';
                    if (authorized) await load();
                  }),
                ),
                AppRow(
                  title: const Text('打开系统权限设置'),
                  onTap: () => strategies!.exporter!.openSettings(),
                ),
              ],
            ),
          if (!busy && authorized && s != null) ...[
            AppGroup(
              children: [
                AppRow(
                  title: Text(s.contact['data']['display_name'] as String),
                  subtitle: Text(
                    s.target == null
                        ? '新建到 ${s.account['name'] ?? '设备本地通讯录'}'
                        : '更新系统记录 · ${s.target!['accountName'] ?? '本地'}',
                  ),
                ),
                if (!s.pending)
                  AppRow(
                    title: const Text('查找并关联现有系统联系人'),
                    subtitle: const Text('请先检查是否已有相同姓名、电话或邮箱，避免重复创建'),
                    onTap: chooseTarget,
                  ),
                if (!s.pending)
                  AppRow(
                    title: const Text('选择账户并新建'),
                    onTap: () => run(chooseAccount),
                  ),
                if (s.target != null && !s.pending)
                  AppRow(
                    title: const Text('仅保存关联，不修改系统资料'),
                    onTap: () => run(() async {
                      await s.associateOnly();
                      finished = true;
                    }),
                  ),
                if (s.association != null && !s.pending)
                  AppRow(
                    title: const Text('解除本机关联'),
                    subtitle: const Text('不会删除系统联系人'),
                    onTap: () => run(() async {
                      await s.unlink();
                      await checkDuplicates();
                      newTargetConfirmed = false;
                    }),
                  ),
              ],
            ),
            if (s.target == null && possibleDuplicates.isNotEmpty)
              AppStatus(
                '发现疑似重复：${possibleDuplicates.join('、')}。请关联现有记录，或明确选择新建。',
              ),
            for (final warning in s.warnings) AppStatus(warning),
            if (s.pending) ...[
              const AppStatus('上次操作需要核对。不会直接重复创建联系人。'),
              AppButton(
                onPressed: () => run(apply),
                child: const Text('核对并完成上次写入'),
              ),
              AppButton(
                onPressed: () => run(s.discardUnapplied),
                child: const Text('确认未写入后重新准备'),
              ),
            ] else ...[
              for (final field in s.fields)
                AppGroup(
                  children: [
                    AppSwitchRow(
                      title: Text(writeFieldLabels[field.key]!),
                      subtitle: Text(
                        field.conflict
                            ? '首次关联或两端均有变化，请选择是否使用 CardWeave'
                            : '勾选使用 CardWeave，未勾选保留系统值',
                      ),
                      value: field.selected,
                      onChanged: (v) => setState(() => field.selected = v),
                    ),
                    AppRow(
                      title: const Text('系统当前'),
                      subtitle: Text(_describe(field.key, field.system)),
                    ),
                    AppRow(
                      title: const Text('CardWeave'),
                      subtitle: Text(_describe(field.key, field.app)),
                    ),
                  ],
                ),
              if (s.fields.isEmpty && error == null)
                const AppStatus('可写字段没有变化'),
              if (s.fields.any((f) => f.selected))
                AppButton(
                  onPressed: () => run(apply),
                  child: const Text('确认所选字段并写入'),
                ),
            ],
            if (finished) const AppStatus('操作完成，系统数据已读回核对'),
          ],
        ],
      ),
    );
  }
}

String _describe(String field, Object value) {
  final rows = value as List;
  if (rows.isEmpty) return '空（选中写入将清空）';
  if (field == 'name') {
    const labels = {
      1: '姓名',
      2: '名字',
      3: '姓氏',
      4: '前缀',
      5: '中间名',
      6: '后缀',
      7: '名字拼音',
      8: '中间名拼音',
      9: '姓氏拼音',
    };
    return rows
        .map(
          (r) => [
            for (final e in labels.entries)
              if (r['data${e.key}'] != null) '${e.value}：${r['data${e.key}']}',
          ].join('\n'),
        )
        .join('\n');
  }
  if (field == 'dates') {
    return rows
        .map((r) {
          final label = switch (r['data2']) {
            '3' => '公历生日',
            '1' => '纪念日',
            '0' => r['data3'] ?? '自定义日期',
            _ => '其他日期',
          };
          final raw = r['data1'] as String? ?? '';
          return '$label：${raw.startsWith('--') ? '${raw.substring(2)}（不指定年份）' : raw}';
        })
        .join('\n');
  }
  if (field == 'organization') {
    return rows
        .map((r) => [r['data1'], r['data4']].whereType<String>().join(' · '))
        .join('\n');
  }
  return rows
      .map(
        (r) => [
          r['data3'],
          r['data1'],
        ].whereType<String>().where((v) => v.isNotEmpty).join('：'),
      )
      .join('\n');
}
