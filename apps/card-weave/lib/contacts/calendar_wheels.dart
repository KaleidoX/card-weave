import 'dart:async';

import 'package:flutter/cupertino.dart';

import '../design.dart';
import 'date_format.dart';

typedef CalendarOptionsProvider = Future<Map<String, dynamic>> Function(
  String calendar,
  int? year,
);

class CalendarWheels extends StatefulWidget {
  const CalendarWheels({
    super.key,
    required this.initial,
    required this.options,
    required this.onChanged,
  });
  final Map<String, dynamic> initial;
  final CalendarOptionsProvider options;
  final void Function(Map<String, dynamic>, bool) onChanged;
  @override
  State<CalendarWheels> createState() => _CalendarWheelsState();
}

class _CalendarWheelsState extends State<CalendarWheels> {
  late final Map<String, dynamic> d = widget.initial;
  Map<String, dynamic>? limits;
  List<Map<String, dynamic>> months = [];
  bool loading = true;
  bool failed = false;
  int request = 0;
  Timer? yearUpdate;

  int get monthIndex => months.indexWhere(
    (m) => m['month'] == d['month'] && m['is_leap_month'] == d['is_leap_month'],
  );
  int get maxDay => monthIndex < 0 ? 0 : months[monthIndex]['days'] as int;
  bool get validDay => !loading && !failed && hasValidDay;
  bool get hasValidDay =>
      d['day'] != null && d['day'] >= 1 && d['day'] <= maxDay;
  bool get validYear =>
      d['year'] == null ||
      (limits != null &&
          d['year'] >= limits!['min_year'] &&
          d['year'] <= limits!['max_year']);

  void report() {
    final value = Map<String, dynamic>.from(d);
    final valid = validDay && validYear;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(value, valid);
    });
  }

  Future<void> load() async {
    final ticket = ++request;
    final calendar = d['calendar'] as String;
    final year = d['year'] as int?;
    setState(() {
      loading = true;
      failed = false;
    });
    report();
    try {
      final base = limits ?? await widget.options(calendar, null);
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
    report();
  }

  void changeYear(int? value) {
    if (d['year'] == value) return;
    ++request;
    setState(() {
      d['year'] = value;
      loading = true;
      failed = false;
    });
    report();
    yearUpdate ??= Timer(const Duration(milliseconds: 150), () {
      yearUpdate = null;
      unawaited(load());
    });
  }

  @override
  void dispose() {
    yearUpdate?.cancel();
    super.dispose();
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
    bool enabled = true,
  }) => Expanded(
    child: IgnorePointer(
      ignoring: !enabled,
      child: AppWheel(
        key: ValueKey('$label-$identity'),
        label: label,
        count: count,
        selected: selected,
        text: text,
        onChanged: changed,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final lunar = d['calendar'] == 'chinese_lunar';
    return Column(
      children: [
        if (d['kind'] != 'birthday')
          CupertinoSlidingSegmentedControl<String>(
            children: const {
              'gregorian': Text('公历'),
              'chinese_lunar': Text('农历'),
            },
            groupValue: d['calendar'],
            onValueChanged: (v) {
              if (v == null) return;
              yearUpdate?.cancel();
              yearUpdate = null;
              setState(() {
                months = [];
                d['calendar'] = v;
                d['month'] = null;
                d['is_leap_month'] = false;
                d['day'] = null;
                limits = null;
              });
              unawaited(load());
            },
          ),
        Row(
          children: [
            if (limits != null)
              wheel(
                '年份',
                limits!['max_year'] - limits!['min_year'] + 2,
                d['year'] == null || !validYear
                    ? 0
                    : d['year'] - limits!['min_year'] + 1,
                (i) =>
                    i == 0 ? '——' : '${i + (limits!['min_year'] as int) - 1}',
                (i) => changeYear(
                  i == 0 ? null : i + (limits!['min_year'] as int) - 1,
                ),
                identity: d['calendar'],
              ),
            if (months.isNotEmpty) ...[
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
                (i) {
                  if (loading || failed) return;
                  setState(() {
                    d['month'] = i == 0 ? null : months[i - 1]['month'];
                    d['is_leap_month'] = i == 0
                        ? false
                        : months[i - 1]['is_leap_month'];
                    if (!validDay) d['day'] = null;
                  });
                  report();
                },
                identity: d['calendar'],
                enabled: !loading && !failed,
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
                (i) {
                  if (loading || failed) return;
                  setState(() => d['day'] = i == 0 ? null : i);
                  report();
                },
                identity:
                    '${d['calendar']}-${d['month']}-${d['is_leap_month']}',
                enabled: !loading && !failed,
              ),
            ],
          ],
        ),
        if (loading && months.isEmpty)
          const Padding(
            padding: AppTokens.pagePadding,
            child: CupertinoActivityIndicator(),
          ),
        if (failed) ...[
          Text(
            limits != null && !validYear
                ? '该年份不在支持范围内，请重新选择或不指定年份。'
                : '无法获取日历，请重试。',
          ),
          AppButton(onPressed: load, child: const Text('重试')),
        ],
        Visibility(
          visible: !failed && !hasValidDay,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: const AppStatus('请选择有效月份和日期'),
        ),
        if (lunar) const Text('月份和日数按农历计算；不指定年份时保留月日及闰月信息，不校验具体年份。'),
      ],
    );
  }
}
