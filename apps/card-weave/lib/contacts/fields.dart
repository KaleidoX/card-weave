import 'dart:convert';

const contactFieldLabels = {
  'display_name': '姓名',
  'name_prefix': '姓名前缀',
  'family_name': '姓氏',
  'middle_name': '中间名',
  'given_name': '名字',
  'name_suffix': '姓名后缀',
  'phonetic_family_name': '姓氏拼音',
  'phonetic_middle_name': '中间名拼音',
  'phonetic_given_name': '名字拼音',
  'nickname': '昵称',
  'organization': '公司',
  'job_title': '职位',
  'phones': '电话',
  'emails': '邮箱',
  'addresses': '地址',
  'instant_messages': '即时消息',
  'website': '网站',
  'relations': '关联人',
  'dates': '重要日期',
  'notes': '备注',
};
const optionalContactFields = {
  'middle_name',
  'name_prefix',
  'name_suffix',
  'phonetic_family_name',
  'phonetic_middle_name',
  'phonetic_given_name',
  'nickname',
  'job_title',
  'website',
  'addresses',
  'instant_messages',
  'relations',
};
const phoneticFields = [
  'phonetic_family_name',
  'phonetic_middle_name',
  'phonetic_given_name',
];
const extraSections = {
  'nickname': '昵称',
  'phonetic': '姓名拼音',
  'addresses': '地址',
  'instant_messages': '即时消息',
  'website': '网站',
  'relations': '关联人',
};

String? contactTextError(
  String? input, {
  int maxBytes = 1024,
  bool required = false,
}) {
  final value = input ?? '';
  if (required && value.trim().isEmpty) return '请填写内容';
  if (value.contains('\u0000')) return '不能包含空字符';
  if (utf8.encode(value).length > maxBytes) return '内容过长，最多 $maxBytes 字节';
  return null;
}

Map<String, dynamic> contactDocument(Map<String, dynamic> data) => {
  for (final e in data.entries)
    if (!optionalContactFields.contains(e.key) ||
        (e.value is String && (e.value as String).isNotEmpty) ||
        (e.value is List && (e.value as List).isNotEmpty))
      e.key: e.value,
};

String? contactValidationError(Map<String, dynamic> data) {
  for (final e in contactFieldLabels.entries) {
    final value = data[e.key];
    if (value is String) {
      final error = contactTextError(
        value,
        maxBytes: e.key == 'notes'
            ? 32768
            : e.key == 'website'
            ? 4096
            : 1024,
        required: e.key == 'display_name',
      );
      if (error != null) return '${e.value}：$error';
    }
    if (value is List && e.key != 'dates') {
      if (value.length > 32) return '${e.value}最多 32 项';
      for (var i = 0; i < value.length; i++) {
        final item = value[i] as Map;
        final error =
            contactTextError(
              item['value'] as String?,
              required: true,
              maxBytes: e.key == 'addresses' ? 4096 : 1024,
            ) ??
            contactTextError(
              item['label'] as String?,
              maxBytes: 128,
              required: !['phones', 'emails'].contains(e.key),
            );
        if (error != null) return '${e.value}第 ${i + 1} 项：$error';
      }
    }
  }
  if (utf8.encode(jsonEncode(contactDocument(data))).length > 64 * 1024) {
    return '联系人总内容超过 64 KiB，请缩短备注或其他资料';
  }
  return null;
}
