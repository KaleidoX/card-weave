import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'date_format.dart';
import 'fields.dart';
import 'value_kind.dart';

class ContactContent extends StatelessWidget {
  final Map<String, dynamic> data;
  final Set<String> differences;
  final bool showHero, grouped;
  final bool includeRelations;
  const ContactContent(
    this.data, {
    super.key,
    this.differences = const {},
    this.showHero = false,
    this.grouped = true,
    this.includeRelations = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget item(String key, String label, String value) => AppInfoRow(
      label: label,
      value: value,
      changed: differences.contains(key),
    );
    Widget section(String title, List<Widget> rows) => AppSection(
      title: title,
      child: grouped ? AppGroup(children: rows) : Column(children: rows),
    );
    List<Widget> scalarRows(List<String> keys) => [
      for (final key in keys)
        if ((data[key] as String? ?? '').isNotEmpty ||
            differences.contains(key))
          item(key, contactFieldLabels[key]!, data[key] as String? ?? ''),
    ];
    final name = data['display_name'] as String;
    final basic = scalarRows([
      if (!showHero) 'display_name',
      'name_prefix',
      'family_name',
      'middle_name',
      'given_name',
      'name_suffix',
      'nickname',
    ]);
    final phonetic = scalarRows(phoneticFields);
    final employment = scalarRows(['organization', 'job_title']);
    final website = scalarRows(['website']);
    final notes = scalarRows(['notes']);
    final dates = data['dates'] as List;
    return AppSectionList(
      children: [
        if (showHero)
          Column(
            children: [
              const SizedBox(height: AppTokens.small),
              Center(child: ContactAvatar(name, large: true)),
              const SizedBox(height: AppTokens.gap),
              Text(
                name,
                textAlign: TextAlign.center,
                style: AppTheme.of(context).text.headlineSmall,
              ),
            ],
          ),
        if (basic.isNotEmpty) section('基本信息', basic),
        if (phonetic.isNotEmpty) section('姓名拼音', phonetic),
        if (employment.isNotEmpty) section('工作信息', employment),
        for (final kind in ContactValueKind.values)
          if ((includeRelations || kind != ContactValueKind.relation) &&
              ((data[kind.field] as List? ?? []).isNotEmpty ||
                  differences.contains(kind.field)))
            section(kind.title, [
              for (final value in data[kind.field] as List? ?? [])
                item(
                  kind.field,
                  (value['label'] as String).isEmpty
                      ? kind.title
                      : value['label'],
                  '${value['value']}${value['target_contact_id'] == null ? '' : ' · 关联 ID：${value['target_contact_id']}'}',
                ),
              if ((data[kind.field] as List? ?? []).isEmpty)
                item(kind.field, kind.title, ''),
            ]),
        if (website.isNotEmpty) section('网站', website),
        if (dates.isNotEmpty || differences.contains('dates'))
          section('重要日期', [
            for (final d in dates)
              item('dates', dateType(object(d)), dateText(object(d))),
            if (dates.isEmpty) item('dates', '日期', ''),
          ]),
        if (notes.isNotEmpty) section('备注', notes),
      ],
    );
  }
}
