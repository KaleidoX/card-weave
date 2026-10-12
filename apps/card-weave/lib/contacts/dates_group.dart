import 'package:flutter/cupertino.dart';

import '../design.dart';
import 'date_format.dart';
import 'calendar_wheels.dart';
export 'calendar_wheels.dart' show CalendarOptionsProvider;

class _DateDraft {
  Map<String, dynamic> value;
  Map<String, dynamic>? saved;
  bool valid;
  int revision = 0;
  _DateDraft(this.value, {this.saved, this.valid = false});
}

class ContactDatesEditor extends StatefulWidget {
  final List<dynamic> dates;
  final CalendarOptionsProvider options;
  final Future<Map<String, dynamic>> Function(String) currentDate;
  final ValueChanged<List<dynamic>> onChanged;
  final ValueChanged<bool>? onEditingChanged;
  const ContactDatesEditor({
    super.key,
    required this.dates,
    required this.options,
    required this.currentDate,
    required this.onChanged,
    this.onEditingChanged,
  });
  @override
  State<ContactDatesEditor> createState() => _ContactDatesEditorState();
}

class _ContactDatesEditorState extends State<ContactDatesEditor> {
  late final entries = [
    for (final d in widget.dates)
      _DateDraft(
        Map<String, dynamic>.from(d),
        saved: Map<String, dynamic>.from(d),
        valid: true,
      ),
  ];
  _DateDraft? active;
  bool adding = false;
  String? addError;
  static const types = {
    'gregorian': '公历生日',
    'chinese_lunar': '农历生日',
    'anniversary': '纪念日',
    'other': '其他',
    'custom': '自定义',
  };
  String type(_DateDraft e) =>
      e.value['kind'] == 'birthday' ? e.value['calendar'] : e.value['kind'];
  bool occupied(String key, [_DateDraft? except]) => entries.any(
    (e) =>
        e != except &&
        e.value['kind'] == 'birthday' &&
        e.value['calendar'] == key,
  );
  void publish() {
    widget.onEditingChanged?.call(adding || entries.any((e) => !e.valid));
    widget.onChanged([
      for (final e in entries)
        if (e.saved != null) Map<String, dynamic>.from(e.saved!),
    ]);
  }

  void open(_DateDraft e) {
    FocusScope.of(context).unfocus();
    setState(() {
      active = active == e ? null : e;
    });
  }

  Future<void> add() async {
    if (adding) return;
    FocusScope.of(context).unfocus();
    final calendar = occupied('gregorian') && !occupied('chinese_lunar')
        ? 'chinese_lunar'
        : 'gregorian';
    final birthday = !occupied(calendar);
    setState(() {
      adding = true;
      addError = null;
    });
    widget.onEditingChanged?.call(true);
    try {
      final today = await widget.currentDate(calendar);
      if (!mounted) return;
      setState(() {
        final value = <String, dynamic>{
          'kind': birthday ? 'birthday' : 'anniversary',
          'label': '',
          'calendar': calendar,
          ...today,
        };
        active = _DateDraft(value, saved: Map.of(value), valid: true);
        entries.add(active!);
      });
    } catch (_) {
      if (mounted) setState(() => addError = '无法获取当前日期，请重试。');
    } finally {
      if (mounted) {
        setState(() => adding = false);
        publish();
      }
    }
  }

  Future<void> changeType(_DateDraft e, String v) async {
    String? label;
    if (v == 'custom') {
      label = await showCupertinoDialog<String>(
        context: context,
        builder: (_) => AppLabelDialog(initial: e.value['label']),
      );
      if (!mounted || label == null || !entries.contains(e)) return;
    }
    final birthday = v == 'gregorian' || v == 'chinese_lunar';
    setState(() {
      if (birthday && e.value['calendar'] != v) {
        e.value['calendar'] = v;
        e.value['month'] = null;
        e.value['day'] = null;
        e.value['is_leap_month'] = false;
        e.valid = false;
      }
      e.value['kind'] = birthday ? 'birthday' : v;
      e.value['label'] = v == 'custom' ? label : '';
      if (e.valid) e.saved = Map.of(e.value);
      active = e;
      e.revision++;
    });
    publish();
  }

  @override
  Widget build(BuildContext context) => FormField<bool>(
    validator: (_) {
      if (adding) return '正在获取当前日期';
      final invalid = entries.where((e) => !e.valid).firstOrNull;
      if (invalid != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => active = invalid);
        });
        return '请完善日期，或删除未完成的日期';
      }
      return null;
    },
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppGroup(
          alignment: AppAlignment.icon,
          children: [
            for (var i = 0; i < entries.length; i++)
              dateRow(entries[i], i == 0),
            if (entries.length < 32)
              AppFieldRow(
                icon: entries.isEmpty ? CupertinoIcons.calendar : null,
                child: AppButton(
                  onPressed: adding ? null : add,
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('添加日期'),
                  ),
                ),
              ),
          ],
        ),
        if (adding) const AppStatus('正在获取当前日期'),
        if (addError != null)
          AppStatus(addError!, kind: AppStatusKind.error, onRetry: add),
        if (field.hasError)
          AppStatus(field.errorText!, kind: AppStatusKind.error),
      ],
    ),
  );
  Widget dateRow(_DateDraft e, bool first) => Column(
    key: ObjectKey(e),
    children: [
      AppFieldRow(
        icon: first ? CupertinoIcons.calendar : null,
        label: AppChoice<String>(
          title: '日期类型',
          selected: type(e),
          options: types,
          label: dateType(e.value),
          enabled: (v) => !occupied(v, e),
          onChanged: (v) => changeType(e, v),
        ),
        trailing: AppRemoveButton(
          label: '删除日期',
          onPressed: () {
            setState(() {
              entries.remove(e);
              if (active == e) active = null;
            });
            publish();
          },
        ),
        child: AppButton(
          onPressed: () => open(e),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              e.value['day'] == null || e.value['month'] == null
                  ? '日期'
                  : '${e.value['kind'] != 'birthday' && e.value['calendar'] == 'chinese_lunar' ? '农历 ' : ''}${dateText(e.value)}',
              style: AppTheme.of(context).text.bodyLarge,
            ),
          ),
        ),
      ),
      if (active == e)
        Padding(
          padding: AppTokens.pagePadding,
          child: CalendarWheels(
            key: ValueKey('${identityHashCode(e)}-${e.revision}'),
            initial: e.value,
            options: widget.options,
            onChanged: (value, valid) {
              if (!mounted || !entries.contains(e)) return;
              setState(() {
                e.value = value;
                e.valid = valid;
                if (valid) e.saved = Map.of(value);
              });
              publish();
            },
          ),
        ),
      if (active != e && !e.valid)
        const AppStatus('日期尚未填写完整', kind: AppStatusKind.warning),
    ],
  );
}
