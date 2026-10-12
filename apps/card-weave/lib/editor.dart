import 'dart:convert';

import 'package:flutter/material.dart';

import 'model.dart';

String dateText(Map<String, dynamic> d) =>
    '${d['calendar'] == 'chinese_lunar' ? '农历' : '公历'} ${d['year'] ?? '未知年'}年 ${d['is_leap_month'] == true ? '闰' : ''}${d['month']}月${d['day']}日';

class ContactContent extends StatelessWidget {
  final Map<String, dynamic> data;
  final Set<String> differences;
  const ContactContent(this.data, {super.key, this.differences = const {}});
  @override
  Widget build(BuildContext context) {
    Widget item(String field, String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Container(
            decoration: BoxDecoration(
              color: differences.contains(field)
                  ? Theme.of(context).colorScheme.tertiaryContainer
                  : null,
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(value),
              ],
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item('display_name', '姓名', data['display_name'] as String),
        item('given_name', '名', data['given_name'] as String? ?? ''),
        item('family_name', '姓', data['family_name'] as String? ?? ''),
        item('organization', '组织', data['organization'] as String? ?? ''),
        for (final pair in [('phones', '电话'), ('emails', '邮箱')])
          item(
            pair.$1,
            pair.$2,
            (data[pair.$1] as List)
                .map((e) => '${e['label']}  ${e['value']}')
                .join('\n'),
          ),
        item(
          'dates',
          '重要日期',
          (data['dates'] as List)
              .map((e) => '${e['label']} · ${dateText(object(e))}')
              .join('\n'),
        ),
        item('notes', '备注', data['notes'] as String? ?? ''),
      ],
    );
  }
}

class ContactEditor extends StatefulWidget {
  final AppModel model;
  final Map<String, dynamic>? original, seed, conflict;
  const ContactEditor(
    this.model, {
    super.key,
    this.original,
    this.seed,
    this.conflict,
  });
  @override
  State<ContactEditor> createState() => _ContactEditorState();
}

class _ContactEditorState extends State<ContactEditor> {
  final form = GlobalKey<FormState>();
  late Map<String, dynamic> data = copy(
    widget.seed ?? widget.original?['data'] ?? emptyContact(),
  );
  late final String initial = jsonEncode(data);
  bool saving = false, leaving = false;
  String? error;
  bool get dirty => jsonEncode(data) != initial;
  Future<bool> discard() async =>
      !dirty ||
      await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('放弃未保存的修改？'),
              content: const Text('联系人原有内容会保留。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('继续编辑'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('放弃修改'),
                ),
              ],
            ),
          ) ==
          true;
  Future<void> back() async {
    if (saving) return;
    if (await discard() && mounted) {
      setState(() => leaving = true);
      Navigator.pop(context);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.conflict != null) {
        await widget.model.resolve(widget.conflict!, data);
      } else {
        await widget.model.save(data, original: widget.original);
      }
      if (mounted) {
        setState(() => leaving = true);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget field(
    String key,
    String title, {
    bool required = false,
    int lines = 1,
  }) => TextFormField(
    initialValue: data[key] as String? ?? '',
    decoration: InputDecoration(
      labelText: title,
      alignLabelWithHint: lines > 1,
    ),
    maxLines: lines,
    textCapitalization: TextCapitalization.sentences,
    onChanged: (value) => setState(() => data[key] = value),
    validator: (v) => required && (v ?? '').trim().isEmpty ? '请填写$title' : null,
  );
  Widget values(String key, String title, TextInputType type) {
    final values = data[key] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(title),
        for (var i = 0; i < values.length; i++)
          Padding(
            key: ObjectKey(values[i]),
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: TextFormField(
                    initialValue: values[i]['label'],
                    decoration: const InputDecoration(labelText: '标签'),
                    onChanged: (v) => setState(() => values[i]['label'] = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: values[i]['value'],
                    keyboardType: type,
                    decoration: InputDecoration(labelText: title),
                    validator: (v) => (v ?? '').trim().isEmpty ? '请填写内容' : null,
                    onChanged: (v) => setState(() => values[i]['value'] = v),
                  ),
                ),
                IconButton(
                  tooltip: '删除$title',
                  onPressed: () => setState(() => values.removeAt(i)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ),
        TextButton.icon(
          onPressed: values.length >= 32
              ? null
              : () => setState(() => values.add({'label': '', 'value': ''})),
          icon: const Icon(Icons.add),
          label: Text('添加$title'),
        ),
      ],
    );
  }

  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
  Widget dates() {
    final dates = data['dates'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('重要日期'),
        for (var i = 0; i < dates.length; i++)
          Card(
            key: ObjectKey(dates[i]),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: dates[i]['label'],
                          decoration: const InputDecoration(labelText: '日期名称'),
                          validator: (v) =>
                              (v ?? '').trim().isEmpty ? '请填写名称' : null,
                          onChanged: (v) =>
                              setState(() => dates[i]['label'] = v),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除日期',
                        onPressed: () => setState(() => dates.removeAt(i)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: dates[i]['calendar'],
                    decoration: const InputDecoration(labelText: '历法'),
                    items: const [
                      DropdownMenuItem(value: 'gregorian', child: Text('公历')),
                      DropdownMenuItem(
                        value: 'chinese_lunar',
                        child: Text('农历'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      dates[i]['calendar'] = v;
                      if (v == 'gregorian') dates[i]['is_leap_month'] = false;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final p in [
                        ('year', '年（可留空）'),
                        ('month', '月'),
                        ('day', '日'),
                      ])
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TextFormField(
                              initialValue: dates[i][p.$1]?.toString() ?? '',
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(labelText: p.$2),
                              onChanged: (v) => setState(
                                () =>
                                    dates[i][p.$1] = v.isEmpty && p.$1 == 'year'
                                    ? null
                                    : int.tryParse(v) ?? 0,
                              ),
                              validator: (v) {
                                final n = int.tryParse(v ?? '');
                                if (p.$1 == 'year' && (v ?? '').isEmpty) {
                                  return null;
                                }
                                if (p.$1 == 'day' && n != null) {
                                  final d = dates[i];
                                  final y = d['year'] as int?;
                                  final leap =
                                      y == null ||
                                      (y % 4 == 0 &&
                                          (y % 100 != 0 || y % 400 == 0));
                                  final maxDay =
                                      d['calendar'] == 'chinese_lunar'
                                      ? 30
                                      : d['month'] == 2
                                      ? (leap ? 29 : 28)
                                      : [4, 6, 9, 11].contains(d['month'])
                                      ? 30
                                      : 31;
                                  if (n > maxDay) return '该月最多 $maxDay 天';
                                }
                                return n == null ||
                                        n < 1 ||
                                        n >
                                            (p.$1 == 'year'
                                                ? 9999
                                                : p.$1 == 'month'
                                                ? 12
                                                : 31)
                                    ? '超出范围'
                                    : null;
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (dates[i]['calendar'] == 'chinese_lunar')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('闰月'),
                      value: dates[i]['is_leap_month'] == true,
                      onChanged: (v) =>
                          setState(() => dates[i]['is_leap_month'] = v),
                    ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          onPressed: dates.length >= 32
              ? null
              : () => setState(
                  () => dates.add({
                    'label': '生日',
                    'calendar': 'gregorian',
                    'year': null,
                    'month': 1,
                    'day': 1,
                    'is_leap_month': false,
                  }),
                ),
          icon: const Icon(Icons.add),
          label: const Text('添加日期'),
        ),
        const Text('未知年份可留空；农历按原始日期保存，不自动换算。'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!dirty && !saving),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          onPressed: back,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          widget.conflict != null
              ? '编辑合并结果'
              : widget.original == null
              ? '新建联系人'
              : '编辑联系人',
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '正在保存…' : '保存'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (error != null)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(error!),
                          if (widget.original != null)
                            TextButton(
                              onPressed: () async {
                                try {
                                  final fresh = await widget.model.get(
                                    widget.original!['id'],
                                  );
                                  if (!context.mounted) return;
                                  final reload = await showDialog<bool>(
                                    context: context,
                                    builder: (c) => AlertDialog(
                                      title: const Text('当前已保存内容'),
                                      content: SingleChildScrollView(
                                        child: fresh == null
                                            ? const Text('联系人已删除')
                                            : ContactContent(
                                                object(fresh['data']),
                                              ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(c),
                                          child: const Text('返回草稿'),
                                        ),
                                        if (fresh != null &&
                                            fresh['has_conflict'] != true)
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(c, true),
                                            child: const Text('放弃草稿，以最新内容编辑'),
                                          ),
                                      ],
                                    ),
                                  );
                                  if (reload == true && context.mounted) {
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ContactEditor(
                                          widget.model,
                                          original: fresh,
                                        ),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => error = message(e));
                                  }
                                }
                              },
                              child: const Text('查看最新内容'),
                            ),
                        ],
                      ),
                    ),
                  ),
                field('display_name', '姓名', required: true),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: field('family_name', '姓')),
                    const SizedBox(width: 12),
                    Expanded(child: field('given_name', '名')),
                  ],
                ),
                const SizedBox(height: 16),
                field('organization', '组织'),
                values('phones', '电话', TextInputType.phone),
                values('emails', '邮箱', TextInputType.emailAddress),
                dates(),
                section('备注'),
                field('notes', '备注', lines: 5),
                const SizedBox(height: 32),
                Text(saving ? '正在保存到本机，请稍候。' : '保存到本机后，可在同步页面手动上传。'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
