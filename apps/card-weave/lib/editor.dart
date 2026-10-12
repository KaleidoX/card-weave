import 'dart:convert';

import 'package:flutter/cupertino.dart';

import 'model.dart';
import 'contacts/dates_group.dart';
import 'contacts/contact_content.dart';
import 'design.dart';
import 'contacts/name_group.dart';
import 'contacts/values_group.dart';

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
  bool saving = false,
      leaving = false,
      editingDate = false,
      pendingName = false;
  String? error;
  bool get dirty => pendingName || editingDate || jsonEncode(data) != initial;
  Future<bool> discard() async =>
      !dirty ||
      await showCupertinoDialog<bool>(
            context: context,
            builder: (c) => AppDialog(
              title: const Text('放弃未保存的修改？'),
              content: const Text('联系人原有内容会保留。'),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('继续编辑'),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.pop(c, true),
                  isDestructiveAction: true,
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
    FocusScope.of(context).unfocus();
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
  }) => AppInput(
    label: title,
    initialValue: data[key] as String? ?? '',
    minLines: lines,
    labelVisible: lines == 1,
    onChanged: (value) => setState(() => data[key] = value),
    validator: (v) => required && (v ?? '').trim().isEmpty ? '请填写$title' : null,
  );

  Widget section(String title) => SectionLabel(title);
  Widget dates() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ContactDatesEditor(
        dates: data['dates'] as List,
        options: widget.model.calendarOptions,
        currentDate: widget.model.currentCalendarDate,
        onEditingChanged: (value) => setState(() => editingDate = value),
        onChanged: (value) => setState(() => data['dates'] = value),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving || (!dirty && !saving),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) back();
    },
    child: AppPage(
      navigationBar: AppNavigation(
        leading: AppButton(
          key: const ValueKey('cancel-contact'),
          onPressed: back,
          child: const Text('取消'),
        ),
        title: Text(
          widget.conflict != null
              ? '编辑合并结果'
              : widget.original == null
              ? '新建联系人'
              : '编辑联系人',
        ),
        actions: [
          AppButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '正在保存…' : '完成'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppTokens.width),
            child: AbsorbPointer(
              absorbing: saving,
              child: Form(
                key: form,
                child: ListView(
                  padding: AppTokens.pagePadding,
                  children: [
                    if (error != null)
                      SurfaceBox(
                        color: AppTheme.of(context).colors.errorContainer,
                        child: Padding(
                          padding: AppTokens.pagePadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(error!),
                              if (widget.original != null)
                                AppButton(
                                  onPressed: () async {
                                    try {
                                      final fresh = await widget.model.get(
                                        widget.original!['id'],
                                      );
                                      if (!context.mounted) return;
                                      final reload =
                                          await showCupertinoDialog<bool>(
                                            context: context,
                                            builder: (c) => AppDialog(
                                              title: const Text('当前已保存内容'),
                                              content: SingleChildScrollView(
                                                child: fresh == null
                                                    ? const Text('联系人已删除')
                                                    : ContactContent(
                                                        object(fresh['data']),
                                                      ),
                                              ),
                                              actions: [
                                                CupertinoDialogAction(
                                                  onPressed: () =>
                                                      Navigator.pop(c),
                                                  child: const Text('返回草稿'),
                                                ),
                                                if (fresh != null &&
                                                    fresh['has_conflict'] !=
                                                        true)
                                                  CupertinoDialogAction(
                                                    isDefaultAction: true,
                                                    onPressed: () =>
                                                        Navigator.pop(c, true),
                                                    child: const Text(
                                                      '放弃草稿，以最新内容编辑',
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          );
                                      if (reload == true && context.mounted) {
                                        Navigator.pushReplacement(
                                          context,
                                          CupertinoPageRoute(
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
                    ContactNameGroup(
                      data: data,
                      onPendingChanged: (value) =>
                          setState(() => pendingName = value),
                      onChanged: (values) =>
                          setState(() => data.addAll(values)),
                    ),
                    const SizedBox(height: AppTokens.section),
                    ContactValuesGroup(
                      initial: data['phones'] as List,
                      email: false,
                      onChanged: (values) =>
                          setState(() => data['phones'] = values),
                    ),
                    const SizedBox(height: AppTokens.section),
                    ContactValuesGroup(
                      initial: data['emails'] as List,
                      email: true,
                      onChanged: (values) =>
                          setState(() => data['emails'] = values),
                    ),
                    const SizedBox(height: AppTokens.section),
                    AppGroup(
                      alignment: AppAlignment.icon,
                      children: [
                        AppFieldRow(
                          icon: CupertinoIcons.building_2_fill,
                          child: AppInput(
                            label: '公司',
                            labelVisible: false,
                            inline: true,
                            initialValue: data['organization'],
                            onChanged: (v) =>
                                setState(() => data['organization'] = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTokens.section),
                    dates(),
                    const SizedBox(height: AppTokens.section),
                    AppGroup(
                      alignment: AppAlignment.icon,
                      children: [
                        AppFieldRow(
                          icon: CupertinoIcons.text_alignleft,
                          child: AppInput(
                            label: '备注',
                            labelVisible: false,
                            inline: true,
                            minLines: 3,
                            initialValue: data['notes'],
                            onChanged: (v) => setState(() => data['notes'] = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        saving ? '正在保存到本机，请稍候。' : '保存到本机后，可在同步页面手动上传。',
                        style: AppTheme.of(context).text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
