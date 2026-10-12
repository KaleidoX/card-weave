import 'package:flutter/cupertino.dart';

import '../design.dart';

class _ValueEntry {
  String label, value;
  _ValueEntry(this.label, this.value);
}

class ContactValuesGroup extends StatefulWidget {
  final List<dynamic> initial;
  final bool email;
  final ValueChanged<List<Map<String, String>>> onChanged;
  const ContactValuesGroup({
    super.key,
    required this.initial,
    required this.email,
    required this.onChanged,
  });
  @override
  State<ContactValuesGroup> createState() => _ContactValuesGroupState();
}

class _ContactValuesGroupState extends State<ContactValuesGroup> {
  late final List<_ValueEntry> entries = [
    for (final e in widget.initial) _ValueEntry(e['label'], e['value']),
    if (widget.initial.length < 32) _ValueEntry(defaultLabel, ''),
  ];
  String get defaultLabel => widget.email ? '个人' : '手机';
  String get title => widget.email ? '邮箱' : '电话';
  void publish() => widget.onChanged([
    for (final e in entries)
      if (e.value.trim().isNotEmpty) {'label': e.label, 'value': e.value},
  ]);
  void cleanup(_ValueEntry entry) {
    if (!mounted || entry.value.isNotEmpty || entries.last == entry) return;
    setState(() => entries.remove(entry));
  }

  @override
  Widget build(BuildContext context) => AppGroup(
    alignment: AppAlignment.icon,
    children: [
      for (var i = 0; i < entries.length; i++) row(entries[i], i == 0),
    ],
  );
  Widget row(_ValueEntry entry, bool first) {
    final labels = widget.email
        ? ['个人', '工作', '其他']
        : ['手机', '住宅', '工作', '总机', '单位传真', '住宅传真', '寻呼机', '其他'];
    const custom = '__custom__';
    return Focus(
      key: ObjectKey(entry),
      onFocusChange: (focused) {
        if (!focused) cleanup(entry);
      },
      child: AppFieldRow(
        icon: first
            ? (widget.email ? CupertinoIcons.mail : CupertinoIcons.phone)
            : null,
        label: AppChoice<String>(
          title: '$title标签',
          selected: entry.label,
          label: entry.label.isEmpty ? title : entry.label,
          options: {
            '': '未指定',
            for (final l in labels) l: l,
            if (!labels.contains(entry.label) && entry.label.isNotEmpty)
              entry.label: entry.label,
            custom: '自定义',
          },
          onChanged: (v) async {
            final value = v == custom
                ? await showCupertinoDialog<String>(
                    context: context,
                    builder: (_) => AppLabelDialog(initial: entry.label),
                  )
                : v;
            if (value == null || !mounted || !entries.contains(entry)) return;
            setState(() => entry.label = value);
            publish();
          },
        ),
        trailing: entry.value.isEmpty
            ? null
            : AppRemoveButton(
                label: '删除$title',
                onPressed: () {
                  setState(() {
                    entries.remove(entry);
                    if (entries.isEmpty || entries.last.value.isNotEmpty) {
                      entries.add(_ValueEntry(defaultLabel, ''));
                    }
                  });
                  publish();
                },
              ),
        child: AppInput(
          label: title,
          labelVisible: false,
          inline: true,
          initialValue: entry.value,
          keyboardType: widget.email
              ? TextInputType.emailAddress
              : TextInputType.phone,
          onChanged: (v) {
            setState(() {
              entry.value = v;
              if (v.trim().isNotEmpty &&
                  entries.last == entry &&
                  entries.length < 32) {
                entries.add(_ValueEntry(defaultLabel, ''));
              }
            });
            publish();
          },
        ),
      ),
    );
  }
}
