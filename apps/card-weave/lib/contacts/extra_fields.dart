import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';
import 'selector.dart';
import 'fields.dart';
import 'value_kind.dart';
import 'values_group.dart';

class ContactExtraFields extends StatefulWidget {
  final Map<String, dynamic> data;
  final AppModel? model;
  final String? contactId;
  final void Function(String, dynamic) onChanged;
  const ContactExtraFields({
    super.key,
    required this.data,
    this.model,
    this.contactId,
    required this.onChanged,
  });
  @override
  State<ContactExtraFields> createState() => _ContactExtraFieldsState();
}

class _ContactExtraFieldsState extends State<ContactExtraFields> {
  Map<String, String> names = {};
  Map<String, String> states = {};
  @override
  void initState() {
    super.initState();
    loadNames();
  }

  Future<void> loadNames() async {
    if (widget.model == null) return;
    try {
      final views = await widget.model!.command('relation_views', {
        'contact': widget.data,
      });
      if (mounted) {
        states = {
          for (final v in views as List)
            if (v['target_contact_id'] != null)
              v['target_contact_id'] as String: v['state'] as String,
        };
        setState(
          () => names = {
            for (final v in views)
              if (v['target_contact_id'] != null)
                v['target_contact_id'] as String: v['name'] as String,
          },
        );
      }
    } catch (_) {}
  }

  bool expanded = false;
  late final populated = extraSections.keys.where(hasValue).toSet();
  bool hasValue(String key) => key == 'phonetic'
      ? phoneticFields.any((k) => (widget.data[k] as String? ?? '').isNotEmpty)
      : widget.data[key] is List
      ? (widget.data[key] as List).isNotEmpty
      : (widget.data[key] as String? ?? '').isNotEmpty;

  Widget group(String key) {
    final kind = ContactValueKind.values
        .where((k) => k.field == key)
        .firstOrNull;
    return AppSection(
      key: ValueKey('extra-$key'),
      title: extraSections[key]!,
      child: kind != null
          ? ContactValuesGroup(
              initial: widget.data[key] as List? ?? [],
              kind: kind,
              targetNames: names,
              targetStates: states,
              selectContact:
                  kind == ContactValueKind.relation && widget.model != null
                  ? () => Navigator.push<Map<String, dynamic>>(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => ContactSelector(
                          widget.model!,
                          exclude: widget.contactId,
                        ),
                      ),
                    )
                  : null,
              onChanged: (v) => widget.onChanged(key, v),
            )
          : AppGroup(
              alignment: AppAlignment.icon,
              children: [
                for (final field in key == 'phonetic' ? phoneticFields : [key])
                  AppFieldRow(
                    icon: field != phoneticFields.first && key == 'phonetic'
                        ? null
                        : key == 'website'
                        ? CupertinoIcons.globe
                        : CupertinoIcons.person,
                    child: AppInput(
                      label: contactFieldLabels[field]!,
                      labelVisible: false,
                      inline: true,
                      initialValue: widget.data[field] as String? ?? '',
                      keyboardType: key == 'website'
                          ? TextInputType.url
                          : TextInputType.text,
                      validator: (v) => contactTextError(
                        v,
                        maxBytes: key == 'website' ? 4096 : 1024,
                      ),
                      onChanged: (v) => widget.onChanged(field, v),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) => AppSectionList(
    children: [
      if (!expanded)
        AppGroup(
          children: [
            AppRow(
              title: const Text('更多信息'),
              trailing: const Icon(CupertinoIcons.chevron_down),
              onTap: () {
                FocusScope.of(context).unfocus();
                setState(() => expanded = true);
              },
            ),
          ],
        ),
      for (final key in extraSections.keys)
        if (expanded || populated.contains(key)) group(key),
    ],
  );
}
