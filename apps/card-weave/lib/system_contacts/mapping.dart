import '../contacts/fields.dart';
import '../model.dart';
import 'event_dates.dart';

class ImportCandidate {
  final String sourceId;
  final Map<String, dynamic> contact;
  final List<String> warnings;
  final Set<String> duplicates = {};
  String? error;
  String? createdId;
  bool selected = false;
  bool importFailed = false;
  bool uncertain = false;
  ImportCandidate(this.sourceId, this.contact, this.warnings, {this.error});
  String get name => contact['display_name'] as String;
}

Future<ImportCandidate> mapSystemContact(
  Map<String, dynamic> summary,
  Map<String, dynamic> detail, {
  SystemEventDateDecoder decodeEventDate = decodeAndroidEventDate,
}) async {
  final contact = emptyContact();
  final warnings = <String>[];
  final notes = <String>[];
  void warn(String value) {
    if (!warnings.contains(value)) warnings.add(value);
  }

  void scalar(String field, String value) {
    if (value.isEmpty) return;
    if ((contact[field] as String? ?? '').isEmpty) {
      contact[field] = value;
    } else if (contact[field] != value) {
      notes.add('${contactFieldLabels[field]}：$value');
      warn('多个${contactFieldLabels[field]}值，额外内容已保留在备注');
    }
  }

  void list(String field, String label, String value) {
    if (value.isEmpty) return;
    final items = contact.putIfAbsent(field, () => <dynamic>[]) as List;
    if (!items.any((v) => v['label'] == label && v['value'] == value)) {
      items.add({'label': label, 'value': value});
    }
  }

  for (final raw in detail['rows'] as List? ?? []) {
    final r = Map<String, dynamic>.from(raw as Map);
    String d(int n) => (r['data$n'] as String? ?? '').trim();
    final label = (r['label'] as String? ?? '').trim();
    switch (r['mime']) {
      case 'vnd.android.cursor.item/name':
        for (final entry in {
          2: 'given_name',
          3: 'family_name',
          4: 'name_prefix',
          5: 'middle_name',
          6: 'name_suffix',
          7: 'phonetic_given_name',
          8: 'phonetic_middle_name',
          9: 'phonetic_family_name',
        }.entries) {
          scalar(entry.value, d(entry.key));
        }
        scalar('display_name', d(1));
      case 'vnd.android.cursor.item/nickname':
        scalar('nickname', d(1));
      case 'vnd.android.cursor.item/phone_v2':
        list('phones', label, d(1));
      case 'vnd.android.cursor.item/email_v2':
        list('emails', label, d(1));
      case 'vnd.android.cursor.item/postal-address_v2':
        final address = d(1).isNotEmpty
            ? d(1)
            : [
                d(10),
                d(8),
                d(7),
                d(6),
                d(4),
                d(5),
                d(9),
              ].where((v) => v.isNotEmpty).join(' ');
        list('addresses', label.isEmpty ? '地址' : label, address);
      case 'vnd.android.cursor.item/organization':
        scalar('organization', d(1));
        scalar('job_title', d(4));
        for (final n in [5, 6, 7, 8, 9]) {
          if (d(n).isNotEmpty) {
            notes.add('工作信息：${d(n)}');
            warn('额外工作信息已保留在备注');
          }
        }
      case 'vnd.android.cursor.item/im':
        const protocols = {
          '0': 'AIM',
          '1': 'MSN',
          '2': 'Yahoo',
          '3': 'Skype',
          '4': 'QQ',
          '5': 'Google Talk',
          '6': 'ICQ',
          '7': 'Jabber',
          '8': 'NetMeeting',
        };
        list(
          'instant_messages',
          d(5) == '-1' && d(6).isNotEmpty
              ? d(6)
              : protocols[d(5)] ?? (label.isEmpty ? '即时消息' : label),
          d(1),
        );
      case 'vnd.android.cursor.item/website':
        scalar('website', d(1));
      case 'vnd.android.cursor.item/note':
        if (d(1).isNotEmpty) notes.add(d(1));
      case 'vnd.android.cursor.item/relation':
        list('relations', label.isEmpty ? '关联人' : label, d(1));
      case 'vnd.android.cursor.item/contact_event':
        final value = d(1);
        if (value.isEmpty) continue;
        final date = await decodeEventDate(r);
        final dates = contact['dates'] as List;
        final duplicate =
            date != null &&
            date['kind'] == 'birthday' &&
            dates.any(
              (v) =>
                  v['kind'] == 'birthday' && v['calendar'] == date['calendar'],
            );
        if (date == null || duplicate) {
          final metadata = [
            for (var i = 2; i <= 14; i++)
              if (d(i).isNotEmpty) 'data$i=${d(i)}',
          ].join(', ');
          notes.add(
            '${label.isEmpty ? '系统日期' : label}：$value'
            '${date == null && metadata.isNotEmpty ? '（$metadata）' : ''}',
          );
          warn(
            date == null
                ? '无法识别的日期已保留在备注，请核对历法'
                : '多个${date['calendar'] == 'gregorian' ? '公历' : '农历'}生日，额外日期已保留在备注',
          );
        } else {
          dates.add(date);
        }
      case 'vnd.io.cardweave.write-token':
        break;
      case 'vnd.android.cursor.item/photo':
        warn('头像暂不导入');
      case 'vnd.android.cursor.item/group_membership':
        warn('系统群组暂不导入');
      default:
        warn('含厂商或账号扩展字段，未自动转换；请核对农历生日等资料');
    }
  }
  // The provider's aggregate display name is authoritative; keep structured parts separately.
  if ((summary['name'] as String? ?? '').trim().isNotEmpty) {
    contact['display_name'] = (summary['name'] as String).trim();
  }
  if ((contact['display_name'] as String).isEmpty) {
    final identifiers = [
      ...contact['phones'] as List,
      ...contact['emails'] as List,
    ];
    contact['display_name'] = identifiers.isEmpty
        ? '未命名联系人'
        : identifiers.first['value'];
    warn('系统联系人没有姓名，已使用号码、邮箱或占位名称');
  }
  contact['notes'] = notes.join('\n');
  final data = contactDocument(contact);
  return ImportCandidate(
    summary['id'] as String,
    data,
    warnings,
    error: detail['missing'] == true || (detail['rows'] as List? ?? []).isEmpty
        ? '源联系人已删除或没有可导入字段，请重新读取'
        : detail['oversized'] == true
        ? '系统资料过大，请先在系统通讯录整理后重试'
        : contactValidationError(data),
  );
}

String normalizedPhone(String value) =>
    value.replaceAll(RegExp(r'[\s()（）.\-]'), '');
Set<String> contactKeys(Map<String, dynamic> contact) {
  final keys = <String>{};
  final name = (contact['display_name'] as String? ?? '').trim().toLowerCase();
  if (name.isNotEmpty && name != '未命名联系人') keys.add('姓名:$name');
  for (final p in contact['phones'] as List? ?? []) {
    final value = normalizedPhone(p['value'] as String);
    if (value.isNotEmpty) keys.add('电话:$value');
  }
  for (final e in contact['emails'] as List? ?? []) {
    final value = (e['value'] as String).trim().toLowerCase();
    if (value.isNotEmpty) keys.add('邮箱:$value');
  }
  return keys;
}

class ImportDuplicateIndex {
  final Map<String, Set<String>> _existing = {};
  final Map<String, Set<ImportCandidate>> _incoming = {};
  void addExisting(Map<String, dynamic> contact) {
    for (final key in contactKeys(contact)) {
      (_existing[key] ??= {}).add(contact['display_name'] as String);
    }
  }

  void add(ImportCandidate candidate) {
    for (final key in contactKeys(candidate.contact)) {
      final reason = key.split(':').first;
      for (final name in _existing[key] ?? <String>{}) {
        candidate.duplicates.add('$reason与已有联系人「$name」相同');
      }
      final peers = _incoming[key] ??= {};
      for (final peer in peers) {
        candidate.duplicates.add('$reason与本次「${peer.name}」相同');
        peer.duplicates.add('$reason与本次「${candidate.name}」相同');
        peer.selected = false;
      }
      peers.add(candidate);
    }
    candidate.selected =
        candidate.error == null && candidate.duplicates.isEmpty;
  }
}
