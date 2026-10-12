import 'package:flutter/cupertino.dart';

import '../design.dart';
import 'fields.dart';

String composeContactName(Map<String, String> parts) {
  final present = [
    'family_name',
    'middle_name',
    'given_name',
  ].map((k) => parts[k] ?? '').where((v) => v.trim().isNotEmpty).toList();
  final chinese =
      present.isNotEmpty &&
      present.every((v) => RegExp(r'^[\u3400-\u9fff]+$').hasMatch(v.trim()));
  final body =
      (chinese
              ? ['family_name', 'middle_name', 'given_name']
              : ['given_name', 'middle_name', 'family_name'])
          .map((k) => (parts[k] ?? '').trim())
          .where((v) => v.isNotEmpty)
          .join(chinese ? '' : ' ');
  return [
    parts['name_prefix'] ?? '',
    body,
    parts['name_suffix'] ?? '',
  ].map((v) => v.trim()).where((v) => v.isNotEmpty).join(' ');
}

class ContactNameGroup extends StatefulWidget {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, String>> onChanged;
  final ValueChanged<bool>? onPendingChanged;
  const ContactNameGroup({
    super.key,
    required this.data,
    required this.onChanged,
    this.onPendingChanged,
  });
  @override
  State<ContactNameGroup> createState() => _ContactNameGroupState();
}

class _ContactNameGroupState extends State<ContactNameGroup> {
  late Map<String, String> parts;
  late final Map<String, String> originalParts;
  late String display;
  late String originalDisplay;
  @override
  void initState() {
    super.initState();
    parts = {
      for (final k in [
        'name_prefix',
        'family_name',
        'middle_name',
        'given_name',
        'name_suffix',
      ])
        k: widget.data[k] as String? ?? '',
    };
    originalParts = Map.of(parts);
    display = widget.data['display_name'] as String;
    originalDisplay = display;
  }

  bool expanded = false, pending = false, accepted = false;
  int revision = 0;
  bool get structured => parts.values.any((v) => v.isNotEmpty);
  void changePart(String key, String value) {
    setState(() {
      parts[key] = value;
      final hadParts = originalParts.values.any((v) => v.isNotEmpty);
      pending =
          !accepted &&
          hadParts &&
          originalDisplay != composeContactName(originalParts);
      if (!pending) display = composeContactName(parts);
    });
    widget.onPendingChanged?.call(pending);
    if (!pending) widget.onChanged({...parts, 'display_name': display});
  }

  void expand() => setState(() {
    if (!expanded && !structured) parts['given_name'] = display;
    expanded = !expanded;
  });
  @override
  Widget build(BuildContext context) => FormField<bool>(
    validator: (_) => pending
        ? '请选择是否更新显示姓名'
        : display.trim().isEmpty
        ? '请填写姓名'
        : null,
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGroup(
          alignment: AppAlignment.icon,
          children: [
            if (!expanded)
              AppFieldRow(
                icon: CupertinoIcons.person,
                trailing: AppIconButton(
                  tooltip: '展开姓名细分',
                  onPressed: expand,
                  icon: const Icon(
                    CupertinoIcons.chevron_down,
                    size: AppTokens.chevron,
                  ),
                ),
                child: structured
                    ? AppButton(
                        onPressed: expand,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(display.isEmpty ? '姓名' : display),
                        ),
                      )
                    : AppInput(
                        key: ValueKey('display-$revision'),
                        label: '姓名',
                        labelVisible: false,
                        inline: true,
                        initialValue: display,
                        validator: (v) => contactTextError(v, required: true),
                        onChanged: (v) {
                          setState(() {
                            display = v;
                            originalDisplay = v;
                          });
                          widget.onChanged({'display_name': v});
                        },
                      ),
              )
            else
              for (final entry in {
                'name_prefix': '姓名前缀',
                'family_name': '姓氏',
                'middle_name': '中间名',
                'given_name': '名字',
                'name_suffix': '姓名后缀',
              }.entries)
                AppFieldRow(
                  icon: entry.key == 'name_prefix'
                      ? CupertinoIcons.person
                      : null,
                  trailing: entry.key == 'name_prefix'
                      ? AppIconButton(
                          tooltip: '收起姓名细分',
                          onPressed: expand,
                          icon: const Icon(
                            CupertinoIcons.chevron_up,
                            size: AppTokens.chevron,
                          ),
                        )
                      : null,
                  child: AppInput(
                    key: ValueKey('${entry.key}-$revision'),
                    label: entry.value,
                    labelVisible: false,
                    inline: true,
                    initialValue: parts[entry.key],
                    validator: (v) => contactTextError(v),
                    onChanged: (v) => changePart(entry.key, v),
                  ),
                ),
          ],
        ),
        if (pending) ...[
          AppStatus(
            '显示姓名将从“$originalDisplay”更新为“${composeContactName(parts)}”。',
            kind: AppStatusKind.warning,
          ),
          Wrap(
            children: [
              AppButton(
                onPressed: () {
                  setState(() {
                    accepted = true;
                    pending = false;
                    display = composeContactName(parts);
                  });
                  widget.onPendingChanged?.call(false);
                  widget.onChanged({...parts, 'display_name': display});
                },
                child: const Text('使用新姓名'),
              ),
              AppButton(
                onPressed: () => setState(() {
                  parts = Map.of(originalParts);
                  display = originalDisplay;
                  pending = false;
                  revision++;
                  widget.onPendingChanged?.call(false);
                }),
                child: const Text('还原姓名'),
              ),
            ],
          ),
        ],
        if (field.hasError)
          AppStatus(field.errorText!, kind: AppStatusKind.error),
      ],
    ),
  );
}
