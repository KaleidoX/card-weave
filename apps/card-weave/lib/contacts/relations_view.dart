import 'package:flutter/cupertino.dart';

import '../design.dart';
import '../model.dart';

class ContactRelationsView extends StatefulWidget {
  final AppModel model;
  final Map<String, dynamic> data;
  final Future<void> Function(String)? onOpen;
  final bool comparison;
  const ContactRelationsView(
    this.model,
    this.data, {
    super.key,
    this.onOpen,
    this.comparison = false,
  });
  @override
  State<ContactRelationsView> createState() => _ContactRelationsViewState();
}

class _ContactRelationsViewState extends State<ContactRelationsView> {
  late Future<dynamic> views;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    views = widget.model.command('relation_views', {'contact': widget.data});
  }

  @override
  void didUpdateWidget(covariant ContactRelationsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) reload();
  }

  @override
  Widget build(BuildContext context) {
    if ((widget.data['relations'] as List? ?? []).isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(widget.comparison ? '关联人当前状态' : '关联人'),
        FutureBuilder<dynamic>(
          future: views,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return AppGroup(
                children: [
                  AppStatus(
                    message(snapshot.error!),
                    kind: AppStatusKind.error,
                  ),
                  AppButton(
                    onPressed: () => setState(reload),
                    child: const Text('重试'),
                  ),
                ],
              );
            }
            if (!snapshot.hasData) return const CupertinoActivityIndicator();
            return AppGroup(
              children: [
                for (final v in snapshot.data as List)
                  AppRow(
                    title: AppSelectableText(v['name'] as String),
                    subtitle: Text(
                      '${v['label']}${v['state'] == 'unavailable'
                          ? ' · 联系人不可用（可能未同步或已删除）'
                          : v['state'] == 'conflict'
                          ? ' · 联系人有冲突'
                          : ''}',
                    ),
                    trailing: v['state'] == 'available' && widget.onOpen != null
                        ? AppIconButton(
                            tooltip: '打开关联联系人',
                            icon: const Icon(CupertinoIcons.chevron_forward),
                            onPressed: () => widget.onOpen!(
                              v['target_contact_id'] as String,
                            ),
                          )
                        : null,
                    onTap: v['state'] == 'available' && widget.onOpen != null
                        ? () => widget.onOpen!(v['target_contact_id'] as String)
                        : null,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
