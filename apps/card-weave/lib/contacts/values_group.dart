import 'package:flutter/cupertino.dart';

import '../design.dart';
import 'value_kind.dart';
import 'fields.dart';

class _ValueEntry {
  String label, value;
  String? target;
  _ValueEntry(this.label, this.value, [this.target]);
}

class ContactValuesGroup extends StatefulWidget {
  final List<dynamic> initial;
  final ContactValueKind kind;
  final Future<Map<String, dynamic>?> Function()? selectContact;
  final Map<String, String> targetNames;
  final Map<String, String> targetStates;
  final ValueChanged<List<Map<String, String>>> onChanged;
  const ContactValuesGroup({
    super.key,
    required this.initial,
    required this.kind,
    this.selectContact,
    this.targetNames = const {},
    this.targetStates = const {},
    required this.onChanged,
  });
  @override
  State<ContactValuesGroup> createState() => _ContactValuesGroupState();
}

class _ContactValuesGroupState extends State<ContactValuesGroup> {
  late final List<_ValueEntry> entries = [
    for (final e in widget.initial)
      _ValueEntry(e['label'], e['value'], e['target_contact_id']),
    if (widget.initial.length < 32) _ValueEntry(defaultLabel, ''),
  ];
  String get defaultLabel => widget.kind.labels.first;
  String get title => widget.kind.title;
  void publish() => widget.onChanged([
    for (final e in entries)
      if (e.value.trim().isNotEmpty)
        {
          'label': e.label,
          'value': e.value,
          if (e.target != null) 'target_contact_id': e.target!,
        },
  ]);
  void cleanup(_ValueEntry entry) {
    if (!mounted ||
        !entries.contains(entry) ||
        entry.value.trim().isNotEmpty ||
        entries.last == entry) {
      return;
    }
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
    final labels = widget.kind.labels;
    final custom = Object();
    return Focus(
      key: ObjectKey(entry),
      onFocusChange: (focused) {
        if (!focused) cleanup(entry);
      },
      child: AppFieldRow(
        icon: first ? widget.kind.icon : null,
        label: AppChoice<Object>(
          title: '$title标签',
          selected: entry.label,
          label: entry.label.isEmpty ? title : entry.label,
          options: {
            if (!widget.kind.requiresLabel) '': '未指定',
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
                : v as String;
            if (value == null || !mounted || !entries.contains(entry)) return;
            if (entry.target != null &&
                entries.any(
                  (e) =>
                      e != entry &&
                      e.target == entry.target &&
                      e.label == value,
                )) {
              await duplicate();
              return;
            }
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (entry.target != null)
              AppButton(
                onPressed: () async {
                  final choice = await chooseOption<String>(
                    context,
                    title: '关联联系人',
                    selected: '',
                    options: {'select': '重新选择', 'manual': '改为手动填写'},
                  );
                  if (!mounted || !entries.contains(entry)) return;
                  if (choice == 'manual') {
                    setState(() {
                      entry.value =
                          widget.targetNames[entry.target] ?? entry.value;
                      entry.target = null;
                    });
                    publish();
                  }
                  if (choice == 'select') await select(entry);
                },
                child: Text(widget.targetNames[entry.target] ?? entry.value),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: AppInput(
                      label: title,
                      labelVisible: false,
                      inline: true,
                      key: ValueKey(entry.target),
                      initialValue: entry.value,
                      keyboardType: widget.kind.keyboard,
                      multiline: widget.kind == ContactValueKind.address,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? null
                          : contactTextError(
                                  v,
                                  maxBytes: widget.kind.maxBytes,
                                ) ??
                                contactTextError(
                                  entry.label,
                                  maxBytes: 128,
                                  required: widget.kind.requiresLabel,
                                ),
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
                  if (widget.selectContact != null)
                    AppIconButton(
                      tooltip: '选择联系人',
                      onPressed: () => select(entry),
                      icon: const Icon(
                        CupertinoIcons.person_crop_circle_badge_plus,
                      ),
                    ),
                ],
              ),
            if (entry.target != null &&
                [
                  'unavailable',
                  'conflict',
                ].contains(widget.targetStates[entry.target]))
              Text(
                widget.targetStates[entry.target] == 'conflict'
                    ? '关联联系人有冲突'
                    : '关联联系人不可用',
                style: AppTheme.of(context).text.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> duplicate() => showCupertinoDialog<void>(
    context: context,
    builder: (_) => AppDialog(
      title: const Text('已添加此关联'),
      content: const Text('同一联系人与关系类型只需添加一次。'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
  Future<void> select(_ValueEntry entry) async {
    final target = await widget.selectContact?.call();
    if (target == null || !mounted || !entries.contains(entry)) return;
    if (entries.any(
      (e) => e != entry && e.target == target['id'] && e.label == entry.label,
    )) {
      await duplicate();
      return;
    }
    setState(() {
      entry.target = target['id'] as String;
      entry.value = target['data']['display_name'] as String;
      if (entries.last == entry && entries.length < 32) {
        entries.add(_ValueEntry(defaultLabel, ''));
      }
    });
    publish();
  }
}
