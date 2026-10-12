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
