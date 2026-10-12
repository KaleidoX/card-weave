import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

typedef CalendarOptionsProvider = Future<Map<String, dynamic>> Function(
  String calendar,
  int? year,
);

const lunarMonths = [
  '正月',
  '二月',
  '三月',
  '四月',
  '五月',
  '六月',
  '七月',
  '八月',
  '九月',
  '十月',
  '冬月',
  '腊月',
];
String lunarDay(int day) {
  const digits = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  if (day <= 10) return '初${digits[day - 1]}';
  if (day < 20) return '十${digits[day - 11]}';
  if (day == 20) return '二十';
  if (day < 30) return '廿${digits[day - 21]}';
  return '三十';
}

String dateType(Map<String, dynamic> d) => switch (d['kind']) {
  'birthday' => d['calendar'] == 'chinese_lunar' ? '农历生日' : '公历生日',
  'anniversary' => '纪念日',
  'other' => '其他',
  _ => d['label'] as String,
};
String dateText(Map<String, dynamic> d) {
  final lunar = d['calendar'] == 'chinese_lunar';
  final year = d['year'] == null ? '' : '${d['year']}年';
  return lunar
      ? '$year${d['is_leap_month'] == true ? '闰' : ''}${lunarMonths[(d['month'] as int) - 1]}${lunarDay(d['day'] as int)}'
      : '$year${d['month']}月${d['day']}日';
}

class ContactDatesEditor extends StatefulWidget {
  const ContactDatesEditor({
    super.key,
    required this.dates,
    required this.options,
    required this.onChanged,
    this.onEditingChanged,
  });
  final List<dynamic> dates;
  final CalendarOptionsProvider options;
  final ValueChanged<List<dynamic>> onChanged;
  final ValueChanged<bool>? onEditingChanged;
  @override
  State<ContactDatesEditor> createState() => _ContactDatesEditorState();
}

class _ContactDatesEditorState extends State<ContactDatesEditor> {
  int? editing;
  Map<String, dynamic>? draft;
  int generation = 0;
  static const types = {
    'gregorian': '公历生日',
    'chinese_lunar': '农历生日',
    'anniversary': '纪念日',
    'other': '其他',
    'custom': '自定义',
  };
  String type(Map<String, dynamic> d) =>
      d['kind'] == 'birthday' ? d['calendar'] as String : d['kind'] as String;
  bool occupied(String value) => widget.dates.asMap().entries.any(
    (e) =>
        e.key != editing &&
        e.value['kind'] == 'birthday' &&
        e.value['calendar'] == value,
  );
  void begin(int index) => setState(() {
    FocusScope.of(context).unfocus();
    widget.onEditingChanged?.call(true);
    editing = index;
    draft = Map<String, dynamic>.from(widget.dates[index]);
    generation++;
  });
  void cancel() => setState(() {
    widget.onEditingChanged?.call(false);
    editing = null;
    draft = null;
  });
  void add() => setState(() {
    FocusScope.of(context).unfocus();
    widget.onEditingChanged?.call(true);
    editing = widget.dates.length;
    final calendar = occupied('gregorian') && !occupied('chinese_lunar')
        ? 'chinese_lunar'
        : 'gregorian';
    final now = DateTime.now();
    draft = {
      'kind': occupied(calendar) ? 'anniversary' : 'birthday',
      'label': '',
      'calendar': calendar,
      'year': null,
      'month': calendar == 'chinese_lunar' ? 1 : now.month,
      'day': calendar == 'chinese_lunar' ? null : now.day,
      'is_leap_month': false,
    };
    generation++;
  });
  Widget typeMenu(Map<String, dynamic> d) => DropdownButton<String>(
    value: type(d),
    isExpanded: true,
    items: types.entries
        .map(
          (e) => DropdownMenuItem(
            value: e.key,
            enabled: !occupied(e.key),
            child: Text(e.value),
          ),
        )
        .toList(),
    onChanged: (v) => setState(() {
      d['kind'] = ['gregorian', 'chinese_lunar'].contains(v) ? 'birthday' : v;
      if (d['kind'] == 'birthday') {
        if (d['calendar'] != v) d['day'] = null;
        d['calendar'] = v;
        if (v == 'gregorian') d['is_leap_month'] = false;
      }
      generation++;
    }),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              for (
                var i = 0;
                i <
                    widget.dates.length +
                        (editing == widget.dates.length ? 1 : 0);
                i++
              ) ...[
                if (i > 0) const Divider(),
                if (editing == i) ...[
                  Row(
                    children: [
                      const Icon(Icons.calendar_month),
                      const SizedBox(width: 12),
                      Expanded(child: typeMenu(draft!)),
                    ],
                  ),
                  if (draft!['kind'] == 'custom')
                    TextFormField(
                      key: ValueKey('custom-$generation'),
                      initialValue: draft!['label'],
                      decoration: const InputDecoration(labelText: '日期名称'),
                      onChanged: (v) => setState(() => draft!['label'] = v),
                    ),
                  _DateWheels(
                    key: ValueKey(generation),
                    initial: draft!,
                    options: widget.options,
                    onCancel: cancel,
                    onConfirm: (value) {
                      final next = [...widget.dates];
                      if (i == next.length) {
                        next.add(value);
                      } else {
                        next[i] = value;
                      }
                      widget.onChanged(next);
                      cancel();
                    },
                  ),
                ] else
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: InkWell(
                          onTap: draft == null ? () => begin(i) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                Text('${dateType(widget.dates[i])} ▾'),
                                Text(
                                  dateText(widget.dates[i]),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '删除日期',
                        onPressed: draft == null
                            ? () {
                                final next = [...widget.dates]..removeAt(i);
                                widget.onChanged(next);
                              }
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
              ],
              TextButton.icon(
                onPressed: draft == null && widget.dates.length < 32
                    ? add
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('添加日期'),
              ),
            ],
          ),
        ),
      ),
      FormField<bool>(
        validator: (_) => draft != null ? '请先确定或取消正在编辑的日期' : null,
        builder: (state) => state.hasError && draft != null
            ? Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _DateWheels extends StatefulWidget {
  const _DateWheels({
    super.key,
    required this.initial,
    required this.options,
    required this.onConfirm,
    required this.onCancel,
  });
  final Map<String, dynamic> initial;
  final CalendarOptionsProvider options;
  final ValueChanged<Map<String, dynamic>> onConfirm;
  final VoidCallback onCancel;
  @override
  State<_DateWheels> createState() => _DateWheelsState();
}

class _DateWheelsState extends State<_DateWheels> {
  late final Map<String, dynamic> d = widget.initial;
  Map<String, dynamic>? limits;
  List<Map<String, dynamic>> months = [];
  bool loading = true;
  bool failed = false;
  int request = 0;

  int get monthIndex => months.indexWhere(
    (m) => m['month'] == d['month'] && m['is_leap_month'] == d['is_leap_month'],
  );
  int get maxDay => monthIndex < 0 ? 0 : months[monthIndex]['days'] as int;
  bool get validDay =>
      !loading &&
      !failed &&
      d['day'] != null &&
      d['day'] >= 1 &&
      d['day'] <= maxDay;
  bool get validYear =>
      d['year'] == null ||
      (limits != null &&
          d['year'] >= limits!['min_year'] &&
          d['year'] <= limits!['max_year']);

  Future<void> load() async {
    final ticket = ++request;
    final calendar = d['calendar'] as String;
    final year = d['year'] as int?;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      final base = await widget.options(calendar, null);
      if (!mounted || ticket != request) return;
      setState(() => limits = base);
      final result = year == null ? base : await widget.options(calendar, year);
      if (!mounted || ticket != request) return;
      setState(() {
        months = (result['months'] as List)
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        loading = false;
        if (monthIndex < 0) {
          d['month'] = null;
          d['is_leap_month'] = false;
          d['day'] = null;
        }
        if (!validDay) d['day'] = null;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        failed = true;
      });
    }
  }

  void changeYear(int? value) {
    if (d['year'] == value) return;
    setState(() => d['year'] = value);
    unawaited(load());
  }

  void chooseYear() {
    if (limits == null) return;
    changeYear(
      DateTime.now().year.clamp(
        limits!['min_year'] as int,
        limits!['max_year'] as int,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Widget wheel(
    String label,
    int count,
    int selected,
    String Function(int) text,
    ValueChanged<int> changed, {
    Object? identity,
  }) => Expanded(
    child: _Wheel(
      key: ValueKey('$label-$identity'),
      label: label,
      count: count,
      selected: selected,
      text: text,
      onChanged: changed,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final lunar = d['calendar'] == 'chinese_lunar';
    return Column(
      children: [
        if (d['kind'] != 'birthday')
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'gregorian', label: Text('公历')),
              ButtonSegment(value: 'chinese_lunar', label: Text('农历')),
            ],
            selected: {d['calendar']},
            onSelectionChanged: (v) {
              setState(() {
                d['calendar'] = v.single;
                d['day'] = null;
                limits = null;
              });
              unawaited(load());
            },
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('不指定年份'),
          value: d['year'] == null,
          onChanged: (v) {
            if (v!) {
              changeYear(null);
            } else {
              chooseYear();
            }
          },
        ),
        if (lunar && limits != null)
          Text('农历年份支持 ${limits!['min_year']}–${limits!['max_year']}'),
        Row(
          children: [
            if (d['year'] == null || !validYear)
              Expanded(
                child: TextButton(
                  onPressed: limits == null ? null : chooseYear,
                  child: Text(d['year'] == null ? '选择年份' : '重新选择年份'),
                ),
              )
            else if (limits != null)
              wheel(
                '年份',
                limits!['max_year'] - limits!['min_year'] + 1,
                d['year'] - limits!['min_year'],
                (i) => '${i + (limits!['min_year'] as int)} 年',
                (i) => changeYear(i + (limits!['min_year'] as int)),
                identity: d['calendar'],
              ),
            if (!loading && !failed) ...[
              wheel(
                '月份',
                months.length + 1,
                monthIndex + 1,
                (i) {
                  if (i == 0) return '选择月份';
                  final m = months[i - 1];
                  return lunar
                      ? '${m['is_leap_month'] == true ? '闰' : ''}${lunarMonths[(m['month'] as int) - 1]}'
                      : '${m['month']} 月';
                },
                (i) => setState(() {
                  d['month'] = i == 0 ? null : months[i - 1]['month'];
                  d['is_leap_month'] = i == 0
                      ? false
                      : months[i - 1]['is_leap_month'];
                  if (!validDay) d['day'] = null;
                }),
                identity: '${d['calendar']}-${d['year']}',
              ),
              wheel(
                '日期',
                maxDay + 1,
                d['day'] ?? 0,
                (i) => i == 0
                    ? '请选择'
                    : lunar
                    ? lunarDay(i)
                    : '$i 日',
                (i) => setState(() => d['day'] = i == 0 ? null : i),
                identity:
                    '${d['calendar']}-${d['year']}-${d['month']}-${d['is_leap_month']}',
              ),
            ],
          ],
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        if (failed) ...[
          Text(
            limits != null && !validYear
                ? '该年份不在支持范围内，请重新选择或不指定年份。'
                : '无法获取日历，请重试。',
          ),
          TextButton(onPressed: load, child: const Text('重试')),
        ] else if (!loading && !validDay)
          const Text('请选择有效月份和日期'),
        if (lunar)
          Text(
            d['year'] == null
                ? '未指定年份：保留普通月或闰月及月日，尚未校验具体年份。'
                : '月份和日数按所选农历年份计算。',
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('取消')),
            FilledButton(
              onPressed:
                  validDay &&
                      (d['kind'] != 'custom' ||
                          (d['label'] as String).trim().isNotEmpty)
                  ? () => widget.onConfirm(Map<String, dynamic>.from(d))
                  : null,
              child: const Text('确定'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Wheel extends StatefulWidget {
  const _Wheel({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.text,
    required this.onChanged,
  });
  final String label;
  final int count;
  final int selected;
  final String Function(int) text;
  final ValueChanged<int> onChanged;
  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final controller = FixedExtentScrollController(
    initialItem: widget.selected,
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.label,
    child: SizedBox(
      height: 180,
      child: CupertinoPicker.builder(
        scrollController: controller,
        itemExtent: 44,
        childCount: widget.count,
        onSelectedItemChanged: widget.onChanged,
        itemBuilder: (_, i) => Center(
          child: FittedBox(
            child: Text(widget.text(i), style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
    ),
  );
}
