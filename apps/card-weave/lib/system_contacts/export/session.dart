import 'dart:convert';

import '../../model.dart';
import 'mapper.dart';
import 'strategy.dart';

class WriteField {
  final String key;
  final Object app, system;
  final bool conflict;
  bool selected;
  WriteField(
    this.key,
    this.app,
    this.system, {
    required this.selected,
    this.conflict = false,
  });
}

class ContactWriteSession {
  final SystemContactsExportStrategy strategy;
  final String key;
  final Map<String, dynamic> contact;
  late final EncodedContact encoded = strategy.mapper.encode(
    object(contact['data']),
  );
  Map<String, dynamic>? association, target;
  String _linkStamp = 'null';
  Map<String, dynamic> account = {'name': null, 'type': null};
  final fields = <WriteField>[];
  final warnings = <String>[];
  static final _busy = <String>{};
  bool get pending => association?['pending'] != null;
  ContactWriteSession(this.strategy, String dataset, this.contact)
    : key = associationKey(dataset, contact['id'] as String);
  Future<void> load() async {
    if (contact['has_conflict'] == true) {
      throw StateError('请先处理 CardWeave 中的联系人冲突');
    }
    association = await strategy.link(key);
    _linkStamp = jsonEncode(association);
    if (pending) return;
    if (association != null) {
      target = await strategy.snapshot(association!['rawId'] as String);
      for (final k in ['lookup', 'accountName', 'accountType']) {
        if (target![k] != association![k]) {
          target = null;
          throw StateError('系统关联已变化，请重新选择目标');
        }
      }
    }
    prepare();
  }

  Future<void> choose(
    Map<String, dynamic>? value, {
    Map<String, dynamic>? newAccount,
  }) async {
    if (pending) throw StateError('请先核对上次写入结果');
    target = value;
    if (newAccount != null) account = newAccount;
    if (value?['rawId'] != association?['rawId']) association = null;
    prepare();
  }

  void prepare() {
    fields.clear();
    warnings.clear();
    warnings.addAll(encoded.warnings);
    if (target?['writable'] == false) throw StateError('该系统记录只读，请选择其他记录或新建');
    final current = strategy.mapper.project(target ?? {'rows': []});
    final baseline = association?['mapper'] == strategy.mapper.version
        ? association
        : null;
    for (final k in writeMimes.keys) {
      if (encoded.blocked.contains(k)) continue;
      final rows = (target?['rows'] as List? ?? []).where(
        (r) => r['mime'] == '$providerPrefix${writeMimes[k]}',
      );
      // Unrecognized date metadata is not safe to reinterpret as a standard event.
      if (rows.any((r) => r['readonly'] == true) ||
          (k == 'dates' &&
              rows.any(
                (r) =>
                    !['0', '1', '2', '3'].contains(r['data2']) ||
                    r.keys.any(
                      (n) =>
                          RegExp(r'^data([4-9]|1[0-4])$')
                              .hasMatch(n.toString()),
                    ),
              ))) {
        warnings.add('${writeFieldLabels[k]}包含只读或未验证扩展数据，本次保留系统值');
        continue;
      }
      final app = encoded.fields[k]!, system = current[k]!;
      if (sameValue(app, system)) continue;
      final appChanged =
          baseline == null || !sameValue(app, (baseline['app'] as Map)[k]);
      final systemChanged =
          baseline == null ||
          !sameValue(system, (baseline['system'] as Map)[k]);
      if (!appChanged && !systemChanged) continue;
      // A baseline is necessary to distinguish system-only edits from two-sided edits.
      fields.add(
        WriteField(
          k,
          app,
          system,
          selected: target == null || (appChanged && !systemChanged),
          conflict: target != null && appChanged && systemChanged,
        ),
      );
    }
  }

  Future<void> checkLink() async {
    if (jsonEncode(await strategy.link(key)) != _linkStamp) {
      throw StateError('本机关联已被其他操作更新，请重新打开预览');
    }
  }

  Future<void> persist(Map<String, dynamic>? next) async {
    await strategy.saveLink(key, next);
    _linkStamp = jsonEncode(next);
    association = next;
  }

  Future<void> associateOnly() async {
    await checkLink();
    if (target == null || pending || target!['writable'] != true) {
      throw StateError('请选择可写的系统联系人');
    }
    final current = await strategy.snapshot(target!['rawId'] as String);
    if (current['version'] != target!['version'] ||
        current['lookup'] != target!['lookup']) {
      throw StateError('系统联系人在关联期间已变化，请重新选择');
    }
    await _saveBaseline(current, encoded.fields);
    prepare();
  }

  Future<void> unlink() async {
    await checkLink();
    if (pending) throw StateError('请先核对上次写入结果');
    await persist(null);
    association = null;
    target = null;
    prepare();
  }

  Future<void> _saveBaseline(Map<String, dynamic> value, Object app) async {
    final next = {
      'rawId': value['rawId'],
      'lookup': value['lookup'],
      'accountName': value['accountName'],
      'accountType': value['accountType'],
      'mapper': strategy.mapper.version,
      'app': app,
      'system': strategy.mapper.project(value),
      'lastSuccess': DateTime.now().toUtc().toIso8601String(),
    };
    await persist(next);
    target = value;
  }

  Future<void> write() async {
    if (!_busy.add(key)) throw StateError('此联系人正在写入');
    try {
      await checkLink();
      Map<String, dynamic> work;
      if (pending) {
        work = object(association!['pending']);
      } else {
        final selected = fields
            .where((f) => f.selected)
            .map((f) => f.key)
            .toSet();
        if (selected.isEmpty) throw StateError('请选择要写入的字段；也可仅保存关联');
        work = {
          'app': encoded.fields,
          'selected': selected.toList(),
          'request': {
            'token': writeToken(),
            'rawId': target?['rawId'],
            'lookup': target?['lookup'],
            'version': target?['version'],
            'accountName': target == null
                ? account['name']
                : target!['accountName'],
            'accountType': target == null
                ? account['type']
                : target!['accountType'],
            'patches': strategy.mapper.patches(
              target ?? {'rows': []},
              encoded.fields,
              selected,
            ),
          },
        };
        association = {...?association, 'pending': work};
        await persist(association);
      }
      final request = object(work['request']);
      await persist(association);
      final recovered = await strategy.recover(request['token'] as String);
      if (recovered == null && !sameValue(work['app'], encoded.fields)) {
        throw StateError('上次请求尚未写入且 App 资料已变化，请取消未执行请求后重新预览');
      }
      final result = recovered ?? await strategy.write(request);
      final actual = strategy.mapper.project(result);
      for (final field in work['selected'] as List) {
        if (!strategy.mapper.matchesReadback(
          field as String,
          (work['app'] as Map)[field],
          actual[field],
        )) {
          throw StateError('系统写入后读回不一致，已保留待核对记录，请勿重复新建');
        }
      }
      await _saveBaseline(result, work['app']);
      prepare();
    } finally {
      _busy.remove(key);
    }
  }

  Future<void> discardUnapplied() async {
    await checkLink();
    if (!pending) return;
    final request = object(association!['pending']['request']);
    if (await strategy.recover(request['token'] as String) != null) {
      throw StateError('系统已有写入结果，请先核对并完成');
    }
    association!.remove('pending');
    if (!association!.containsKey('rawId')) association = null;
    await persist(association);
    await load();
  }
}

/// Imported aggregates are linked automatically only when a single raw record is unambiguous.
Future<bool> associateImported(
  SystemContactsExportStrategy strategy,
  String dataset,
  String sourceId,
  String id,
  Map<String, dynamic> contact,
) async {
  final targets = await strategy.targets(sourceId);
  if (targets.length != 1) return false;
  final session = ContactWriteSession(strategy, dataset, {
    'id': id,
    'data': contact,
  });
  await session.choose(targets.single);
  await session.associateOnly();
  return true;
}
