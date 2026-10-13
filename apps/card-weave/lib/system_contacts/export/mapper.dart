import 'package:collection/collection.dart';

import '../../contacts/fields.dart';

const providerPrefix = 'vnd.android.cursor.item/';
const writeFieldLabels = {
  'name': '姓名与拼音',
  'nickname': '昵称',
  'phones': '电话',
  'emails': '邮箱',
  'organization': '公司与职位',
  'addresses': '地址',
  'instant_messages': '即时消息',
  'website': '网站',
  'notes': '备注',
  'relations': '关联人',
  'dates': '重要日期',
};
const writeMimes = {
  'name': 'name',
  'nickname': 'nickname',
  'phones': 'phone_v2',
  'emails': 'email_v2',
  'organization': 'organization',
  'addresses': 'postal-address_v2',
  'instant_messages': 'im',
  'website': 'website',
  'notes': 'note',
  'relations': 'relation',
  'dates': 'contact_event',
};
const ownedColumns = {
  'name': [1, 2, 3, 4, 5, 6, 7, 8, 9],
  'nickname': [1],
  'phones': [1, 2, 3],
  'emails': [1, 2, 3],
  'organization': [1, 4],
  'addresses': [1, 2, 3],
  'instant_messages': [1, 2, 3, 5, 6],
  'website': [1],
  'notes': [1],
  'relations': [1, 2, 3],
  'dates': [1, 2, 3],
};
typedef ProviderFields = Map<String, List<Map<String, dynamic>>>;
bool sameValue(Object? a, Object? b) =>
    const DeepCollectionEquality().equals(a, b);

class EncodedContact {
  final ProviderFields fields;
  final List<String> warnings;
  final Set<String> blocked;
  const EncodedContact(this.fields, this.warnings, this.blocked);
}

/// A platform/vendor mapper owns the whole export, including cross-field rules.
abstract interface class SystemContactWriteMapper {
  String get version;
  EncodedContact encode(Map<String, dynamic> contact);
  ProviderFields project(Map<String, dynamic> snapshot);
  bool matchesReadback(String field, Object? expected, Object? actual);
  List<Map<String, dynamic>> patches(
    Map<String, dynamic> snapshot,
    ProviderFields desired,
    Set<String> fields,
  );
}

class AndroidContactWriteMapper implements SystemContactWriteMapper {
  const AndroidContactWriteMapper();
  @override
  String get version => 'android-standard/1';
  @override
  EncodedContact encode(Map<String, dynamic> c) {
    final error = contactValidationError(c);
    if (error != null) throw StateError(error);
    final fields = <String, List<Map<String, dynamic>>>{};
    final warnings = <String>[];
    final blocked = <String>{};
    Map<String, dynamic> row(Map<int, dynamic> values) => {
      for (final e in values.entries)
        if (e.value != null && e.value.toString().isNotEmpty)
          'data${e.key}': e.value.toString(),
    };
    fields['name'] = [
      row({
        1: c['display_name'],
        2: c['given_name'],
        3: c['family_name'],
        4: c['name_prefix'],
        5: c['middle_name'],
        6: c['name_suffix'],
        7: c['phonetic_given_name'],
        8: c['phonetic_middle_name'],
        9: c['phonetic_family_name'],
      }),
    ];
    for (final f in ['nickname', 'website', 'notes']) {
      fields[f] = (c[f] as String? ?? '').isEmpty
          ? []
          : [
              row({1: c[f]}),
            ];
    }
    fields['organization'] = [
      if ((c['organization'] as String? ?? '').isNotEmpty ||
          (c['job_title'] as String? ?? '').isNotEmpty)
        row({1: c['organization'], 4: c['job_title']}),
    ];
    for (final f in [
      'phones',
      'emails',
      'addresses',
      'relations',
      'instant_messages',
    ]) {
      fields[f] = [
        for (final v in c[f] as List? ?? [])
          row(
            f == 'instant_messages'
                ? {1: v['value'], 2: 0, 3: v['label'], 5: -1, 6: v['label']}
                : {1: v['value'], 2: 0, 3: v['label']},
          ),
      ];
    }
    fields['dates'] = [];
    for (final d in c['dates'] as List? ?? []) {
      if (d['calendar'] != 'gregorian') {
        blocked.add('dates');
        warnings.add('目标尚未验证农历写入；本次保留系统日期，跳过重要日期字段');
        continue;
      }
      final year = d['year'] == null
          ? '-'
          : d['year'].toString().padLeft(4, '0');
      final value =
          '$year-${d['month'].toString().padLeft(2, '0')}-${d['day'].toString().padLeft(2, '0')}';
      fields['dates']!.add(
        row({
          1: value,
          2: switch (d['kind']) {
            'birthday' => 3,
            'anniversary' => 1,
            'custom' => 0,
            _ => 2,
          },
          3: d['kind'] == 'custom' ? d['label'] : null,
        }),
      );
    }
    return EncodedContact(fields, warnings, blocked);
  }

  @override
  bool matchesReadback(String field, Object? expected, Object? actual) {
    if (field != 'name') return sameValue(expected, actual);
    final wanted = (expected as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    final returned = (actual as List)
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
    if (wanted.length != returned.length) return false;
    for (var i = 0; i < wanted.length; i++) {
      if ([2, 3, 4, 5, 6].every((n) => !wanted[i].containsKey('data$n'))) {
        // AOSP derives structured parts when the caller supplies only a display name.
        for (final n in [2, 3, 4, 5, 6]) {
          returned[i].remove('data$n');
        }
      }
    }
    return sameValue(wanted, returned);
  }

  @override
  ProviderFields project(Map<String, dynamic> snapshot) {
    final result = <String, List<Map<String, dynamic>>>{};
    for (final f in writeMimes.keys) {
      result[f] = [];
      for (final raw in snapshot['rows'] as List? ?? []) {
        if (raw['mime'] != '$providerPrefix${writeMimes[f]}') continue;
        final values = {
          for (final n in ownedColumns[f]!)
            if (raw['data$n'] != null && raw['data$n'].toString().isNotEmpty)
              'data$n': raw['data$n'].toString(),
        };
        if (values.isNotEmpty) result[f]!.add(values);
      }
    }
    return result;
  }

  @override
  List<Map<String, dynamic>> patches(
    Map<String, dynamic> snapshot,
    ProviderFields desired,
    Set<String> fields,
  ) {
    final patches = <Map<String, dynamic>>[];
    for (final field in fields) {
      final mime = '$providerPrefix${writeMimes[field]}';
      final old = (snapshot['rows'] as List? ?? [])
          .where((v) => v['mime'] == mime)
          .toList();
      final next = desired[field]!;
      for (var i = 0; i < old.length || i < next.length; i++) {
        final values = {
          for (final n in ownedColumns[field]!)
            'data$n': i < next.length ? next[i]['data$n'] : null,
        };
        if (field == 'addresses') {
          for (var n = 4; n <= 10; n++) {
            values['data$n'] = null;
          }
        }
        final previous = i < old.length
            ? Map<String, dynamic>.from(old[i] as Map)
            : null;
        final extra =
            previous?['opaque'] == true ||
            (previous?.keys.any(
                  (k) =>
                      k.startsWith('data') &&
                      !values.containsKey(k) &&
                      !(field == 'phones' && k == 'data4') &&
                      !(field == 'addresses' &&
                          RegExp(r'^data([4-9]|10)$').hasMatch(k)),
                ) ??
                false);
        if (i >= next.length && !extra) {
          patches.add({'id': previous!['id'], 'mime': mime, 'delete': true});
        } else {
          patches.add({'id': previous?['id'], 'mime': mime, 'values': values});
        }
      }
    }
    return patches;
  }
}
