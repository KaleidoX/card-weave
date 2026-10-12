import 'dart:async';

typedef SystemEventDateDecoder = FutureOr<Map<String, dynamic>?> Function(
  Map<String, dynamic> row,
);

String eventField(Map<String, dynamic> row, int n) =>
    (row['data$n'] as String? ?? '').trim();

Map<String, dynamic>? decodeAndroidEventDate(Map<String, dynamic> row) {
  if (List.generate(
    11,
    (i) => eventField(row, i + 4),
  ).any((v) => v.isNotEmpty)) {
    return null;
  }
  final match = RegExp(r'^(?:(\d{4})-|--)(\d{2})-(\d{2})$')
      .firstMatch(eventField(row, 1));
  if (match == null) return null;
  final year = match.group(1) == null ? null : int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final actual = DateTime(year ?? 2000, month, day);
  if ((year != null && year < 1) ||
      actual.month != month ||
      actual.day != day) {
    return null;
  }
  final kind = switch (eventField(row, 2)) {
    '3' => 'birthday',
    '1' => 'anniversary',
    '0' => 'custom',
    _ => 'other',
  };
  final label = (row['label'] as String? ?? '').trim();
  return {
    'kind': kind,
    'label': kind == 'custom' ? (label.isEmpty ? '系统日期' : label) : '',
    'calendar': 'gregorian',
    'year': year,
    'month': month,
    'day': day,
    'is_leap_month': false,
  };
}
