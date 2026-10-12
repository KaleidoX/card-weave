import '../../../model.dart';
import '../../event_dates.dart';

typedef SolarToLunar = Future<Map<String, dynamic>> Function(
  int year,
  int month,
  int day,
);

/// realme Contacts 16.80.15: dated lunar events store a solar anchor;
/// year 1900 stores lunar month/day directly, with months 13..24 for leap months.
class RealmeEventDates {
  final SolarToLunar convertSolarToLunar;
  const RealmeEventDates(this.convertSolarToLunar);

  Future<Map<String, dynamic>?> decode(Map<String, dynamic> row) async {
    for (var i = 4; i <= 14; i++) {
      if (i != 10 && eventField(row, i).isNotEmpty) return null;
    }
    final type = eventField(row, 2);
    final marker = eventField(row, 10);
    if (!{'', '0', '1000'}.contains(marker)) return null;
    if (type == '1000' && marker == '0') return null;
    final lunar = type == '1000' || marker == '1000';
    final value = eventField(row, 1);
    final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    final separated = RegExp(r'^(?:(\d{4})-|--)(\d{1,2})-(\d{1,2})$')
        .firstMatch(value);
    final match = compact ?? separated;
    if (match == null) return null;
    final sourceYear = int.tryParse(match.group(1) ?? '');
    final birthday = type == '3' || type == '1000';
    final year = sourceYear == 1900 || (birthday && sourceYear == 1604)
        ? null
        : sourceYear;
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final kind = birthday
        ? 'birthday'
        : type == '1'
        ? 'anniversary'
        : type == '0'
        ? 'custom'
        : 'other';
    final label = (row['label'] as String? ?? '').trim();
    Map<String, dynamic> date;
    if (lunar && year == null) {
      if (month < 1 || month > 24 || day < 1 || day > 30) return null;
      date = {
        'year': null,
        'month': (month - 1) % 12 + 1,
        'day': day,
        'is_leap_month': month > 12,
      };
    } else {
      final actual = DateTime(year ?? 2000, month, day);
      if ((year != null && year < 1) ||
          actual.month != month ||
          actual.day != day) {
        return null;
      }
      if (lunar) {
        try {
          date = await convertSolarToLunar(year!, month, day);
        } on AppFailure catch (e) {
          if (e.code != 'invalid_input') rethrow;
          return null;
        }
      } else {
        date = {
          'year': year,
          'month': month,
          'day': day,
          'is_leap_month': false,
        };
      }
    }
    return {
      ...date,
      'kind': kind,
      'label': kind == 'custom' ? (label.isEmpty ? '系统日期' : label) : '',
      'calendar': lunar ? 'chinese_lunar' : 'gregorian',
    };
  }
}
