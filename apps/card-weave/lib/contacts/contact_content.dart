import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'date_format.dart';

class ContactContent extends StatelessWidget {
  final Map<String, dynamic> data;
  final Set<String> differences;
  final bool showHero, grouped;
  const ContactContent(
    this.data, {
    super.key,
    this.differences = const {},
    this.showHero = false,
    this.grouped = true,
  });
  @override
  Widget build(BuildContext context) {
    Widget item(
      String field,
      String label,
      String value, {
      bool stacked = false,
    }) => AppInfoRow(
      label: label,
      value: value,
      changed: differences.contains(field),
    );
    Widget section(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title),
        if (grouped)
          SurfaceBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const GroupDivider(),
                  rows[i],
                ],
              ],
            ),
          )
        else
          ...rows,
      ],
    );
    final name = data['display_name'] as String;
    final organization = data['organization'] as String? ?? '';
    final phones = data['phones'] as List;
    final emails = data['emails'] as List;
    final dates = data['dates'] as List;
    final notes = data['notes'] as String? ?? '';
    final basic = <Widget>[
      if (!showHero) item('display_name', '姓名', name),
      for (final entry in {
        'family_name': '姓氏',
        'given_name': '名字',
        'middle_name': '中间名',
      }.entries)
        if ((data[entry.key] as String? ?? '').isNotEmpty ||
            differences.contains(entry.key))
          item(entry.key, entry.value, data[entry.key] as String? ?? ''),
      if (!showHero &&
          (organization.isNotEmpty || differences.contains('organization')))
        item('organization', '公司', organization),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHero) ...[
          const SizedBox(height: 8),
          Center(child: ContactAvatar(name, large: true)),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: AppTheme.of(context).text.headlineSmall,
          ),
          if (organization.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                organization,
                textAlign: TextAlign.center,
                style: AppTheme.of(context).text.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
        ],
        if (basic.isNotEmpty) section('基本信息', basic),
        if (phones.isNotEmpty ||
            emails.isNotEmpty ||
            differences.contains('phones') ||
            differences.contains('emails'))
          section('联系方式', [
            for (final phone in phones)
              item(
                'phones',
                (phone['label'] as String).isEmpty ? '电话' : phone['label'],
                phone['value'],
                stacked: true,
              ),
            if (phones.isEmpty && differences.contains('phones'))
              item('phones', '电话', '', stacked: true),
            for (final email in emails)
              item(
                'emails',
                (email['label'] as String).isEmpty ? '邮箱' : email['label'],
                email['value'],
                stacked: true,
              ),
            if (emails.isEmpty && differences.contains('emails'))
              item('emails', '邮箱', '', stacked: true),
          ]),
        if (dates.isNotEmpty || differences.contains('dates'))
          section('重要日期', [
            for (final d in dates)
              item('dates', dateType(object(d)), dateText(object(d))),
            if (dates.isEmpty) item('dates', '日期', ''),
          ]),
        if (notes.isNotEmpty || differences.contains('notes'))
          section('备注', [item('notes', '备注', notes, stacked: true)]),
      ],
    );
  }
}
