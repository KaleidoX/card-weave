import 'package:flutter/cupertino.dart';

import '../design.dart';

Map<String, dynamic> contactSummary(Map<String, dynamic> contact) {
  final data = contact['data'] as Map<String, dynamic>;
  final phones = data['phones'] as List;
  final emails = data['emails'] as List;
  return {
    'id': contact['id'],
    'display_name': data['display_name'],
    'has_conflict': contact['has_conflict'],
    'subtitle': phones.isNotEmpty
        ? phones.first['value']
        : emails.isNotEmpty
        ? emails.first['value']
        : data['organization'],
  };
}

class ContactListRow extends StatelessWidget {
  final Map<String, dynamic> contact;
  final VoidCallback onTap;
  const ContactListRow({super.key, required this.contact, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final name = contact['display_name'] as String;
    final subtitle = contact['subtitle'] as String;
    return AppRow(
      leading: ContactAvatar(name),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.of(context).text.titleMedium,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: contact['has_conflict'] == true
          ? Semantics(
              label: '有待处理冲突',
              child: const Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 20,
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
