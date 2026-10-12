import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'src/rust/api.dart';

Map<String, dynamic> object(dynamic value) =>
    Map<String, dynamic>.from(value as Map);
Map<String, dynamic> copy(Map<String, dynamic> value) =>
    object(jsonDecode(jsonEncode(value)));
String message(Object error) {
  final code = error is AppFailure ? error.code : 'unknown';
  return switch (code) {
    'duplicate_group_name' => '已有同名群组，请使用其他名称。',
    'legacy_join' => '这是旧通讯录的加入信息。请在原设备升级后复制新的加入信息。',
    'migration_not_ready' => '请先完成同步并解决全部冲突，再升级通讯录。',
    'edit_stale' => '资料已发生变化。当前选择或草稿已保留，请查看最新内容后重新编辑。',
    'conflict_requires_resolution' => '资料有多个版本，请到冲突页面处理。当前选择或草稿已保留。',
    'invalid_input' => '内容或配置不符合要求，请检查字段、日期和服务器地址。',
    'authentication' => '认证失败，请检查账号、密码或访问密钥。',
    'cancelled' => '同步已取消；已完成的更改仍然保留。',
    'network_error' => '无法完成同步，请检查网络、证书和服务器设置后重试。',
    'unsupported' => '服务器不支持所需能力或地址不受支持。请使用 HTTPS。',
    'remote_corrupt' => '远端数据校验失败，本次同步已停止。',
    'database_in_use' => '通讯录正在被其他会话使用，请稍后重试。',
    'rate_limit' => '服务器请求过于频繁，请稍后重试。',
    'not_found' => '联系人已不存在，请返回列表刷新。',
    'secure_storage' => '无法保存凭据。可取消“记住凭据”，仅在本次使用。',
    'busy' => '同步正在进行，请等待或取消后重试。',
    _ => '操作未完成，本机数据会保留。请重试。',
  };
}

class AppFailure implements Exception {
  final String code;
  AppFailure(this.code);
}

dynamic unwrap(String text) {
  final value = object(jsonDecode(text));
  if (value['ok'] != true) {
    throw AppFailure(value['error']['code'] as String);
  }
  return value['data'];
}

Map<String, dynamic> emptyContact() => {
  'version': 2,
  'display_name': '',
  'given_name': '',
  'middle_name': '',
  'family_name': '',
  'organization': '',
  'notes': '',
  'phones': <dynamic>[],
  'emails': <dynamic>[],
  'dates': <dynamic>[],
};
const publicBackendKeys = ['type', 'endpoint', 'directory', 'region', 'bucket'];
Map<String, dynamic> publicBackend(Map<String, dynamic> value) {
  final result = <String, dynamic>{
    for (final k in publicBackendKeys)
      if (value.containsKey(k)) k: value[k],
  };
  if (result['type'] == 'webdav' && !result.containsKey('directory')) {
    final uri = Uri.tryParse(result['endpoint'] as String? ?? '');
    if (uri?.host == 'dav.jianguoyun.com' &&
        uri!.pathSegments.firstOrNull == 'dav') {
      result['endpoint'] = uri.replace(path: '/dav/').toString();
      result['directory'] = uri.pathSegments
          .skip(1)
          .where((s) => s.isNotEmpty)
          .join('/');
    } else {
      result['directory'] = '';
    }
  }
  if (result['type'] != 'webdav') result.remove('directory');
  return result;
}

void validateBackend(Map<String, dynamic> value) {
  final uri = Uri.tryParse(value['endpoint'] as String? ?? '');
  if (!['webdav', 's3'].contains(value['type']) ||
      uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw AppFailure('invalid_input');
  }
  if (value['type'] == 'webdav') {
    final directory = (value['directory'] as String? ?? '').replaceAll(
      RegExp(r'^/+|/+$'),
      '',
    );
    if (utf8.encode(directory).length > 1024 ||
        directory.contains('\\') ||
        directory.contains('\u0000') ||
        (directory.isNotEmpty &&
            directory
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..'))) {
      throw AppFailure('invalid_input');
    }
  }
  if (value['type'] == 's3' &&
      ((value['region'] as String? ?? '').isEmpty ||
          (value['bucket'] as String? ?? '').isEmpty)) {
    throw AppFailure('invalid_input');
  }
}

class AppModel extends ChangeNotifier {
  final AppHost host = AppHost();
  final FlutterSecureStorage secure = const FlutterSecureStorage();
  late Directory directory;
  bool ready = false,
      initialized = false,
      syncing = false,
      cancelling = false,
      loading = false;
  String? startupError, listError, syncMessage, lastSync;
  String search = '';
  String? group;
  String groupTitle = '联系人';
  String bookName = 'book';
  String? _stampDataset;
  bool get supportsGroups => identity['version'] == 2;
  Future<dynamic> groups(Map<String, dynamic> request) =>
      command('groups', {'request': request});
  int generation = 0;
  List<Map<String, dynamic>> contacts = [], conflicts = [];
  Map<String, dynamic> identity = {},
      status = {},
      config = {},
      credentials = {};
  bool more = false;
  Future<dynamic> command(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async => unwrap(
    await host.execute(request: jsonEncode({'action': action, ...args})),
  );
  Future<void> start() async {
    startupError = null;
    try {
      directory = Directory(
        await (await getApplicationSupportDirectory()).resolveSymbolicLinks(),
      );
      final active = File('${directory.path}/active-book.txt');
      if (await active.exists()) {
        bookName = (await active.readAsString()).trim();
        if (!RegExp(r'^book(?:-[0-9]+)?$').hasMatch(bookName)) {
          throw AppFailure('invalid_input');
        }
      }
      final stamp = File('${directory.path}/last-sync.txt');
      if (await stamp.exists()) {
        final saved = await stamp.readAsString();
        final parts = saved.split('\n');
        if (parts.length == 2) {
          lastSync = parts[1];
          _stampDataset = parts[0];
        }
      }
      final file = File('${directory.path}/sync.json');
      if (await file.exists()) {
        final saved = object(jsonDecode(await file.readAsString()));
        config = {...saved, ...publicBackend(saved)};
      }
      final ref = config['credential_ref'];
      if (ref is String) {
        try {
          final saved = await secure.read(key: ref);
          if (saved != null) {
            credentials = object(jsonDecode(saved));
          }
        } catch (_) {
          syncMessage = '无法读取已保存凭据，请在设置中重新输入。';
        }
      }
      if (!initialized &&
          await Directory('${directory.path}/$bookName').exists()) {
        identity = object(
          unwrap(
            await host.initialize(
              path: '${directory.path}/$bookName',
              create: false,
            ),
          ),
        );
        initialized = true;
      }
      if (initialized) {
        if (_stampDataset != identity['dataset']) lastSync = null;
        await refresh();
      }
    } catch (e) {
      startupError = message(e);
    }
    ready = true;
    notifyListeners();
  }

  Future<void> migrate() async {
    final oldName = bookName;
    final next = 'book-${DateTime.now().microsecondsSinceEpoch}';
    await command('migrate', {'destination': '${directory.path}/$next'});
    await command('close');
    try {
      final nextIdentity = object(
        unwrap(
          await host.initialize(path: '${directory.path}/$next', create: false),
        ),
      );
      final temp = File('${directory.path}/active-book.txt.tmp');
      await temp.writeAsString(next, flush: true);
      await temp.rename('${directory.path}/active-book.txt');
      bookName = next;
      identity = nextIdentity;
    } catch (_) {
      try {
        await command('close');
      } catch (_) {}
      identity = object(
        unwrap(
          await host.initialize(
            path: '${directory.path}/$oldName',
            create: false,
          ),
        ),
      );
      rethrow;
    }
    lastSync = null;
    syncMessage = '升级完成。请手动同步，并将新的加入信息提供给其他设备。';
    try {
      final stamp = File('${directory.path}/last-sync.txt');
      if (await stamp.exists()) await stamp.delete();
    } catch (_) {}
    group = null;
    groupTitle = '联系人';
    await refresh();
  }

  Future<void> create([Map<String, dynamic>? join]) async {
    if (join?['format'] == 'card-weave-join/1') throw AppFailure('legacy_join');
    if (join != null &&
        (join['format'] != 'card-weave-join/2' || join['dataset'] is! String)) {
      throw AppFailure('invalid_input');
    }
    Map<String, dynamic>? backend;
    if (join?['backend'] != null) {
      backend = publicBackend(object(join!['backend']));
      validateBackend(backend);
    }
    identity = object(
      unwrap(
        await host.initialize(
          path: '${directory.path}/$bookName',
          create: true,
          dataset: join?['dataset'] as String?,
        ),
      ),
    );
    initialized = true;
    if (backend != null) {
      try {
        await saveConfig(backend, {}, false);
      } catch (_) {
        syncMessage = '通讯录已创建，但同步位置未保存。请在设置中重新配置。';
      }
    }
    await refresh();
    notifyListeners();
  }

  Future<void> refresh() async {
    status = object(await command('status'));
    conflicts = (await command('conflicts') as List).map(object).toList();
    if (supportsGroups) {
      conflicts.addAll(
        (await groups({'operation': 'conflicts'}) as List).map(object),
      );
    }
    await load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    final ticket = ++generation;
    if (reset) {
      contacts = [];
      more = false;
    }
    loading = true;
    listError = null;
    notifyListeners();
    try {
      final result = supportsGroups
          ? await groups({
              'operation': 'contacts',
              'group': group,
              'search': search,
              'offset': contacts.length,
            })
          : await command('list', {
              'search': search,
              'offset': contacts.length,
            });
      final page = (result as List).map(object).toList();
      if (ticket != generation) {
        return;
      }
      final seen = contacts.map((c) => c['id']).toSet();
      contacts.addAll(page.where((c) => seen.add(c['id'])));
      more = page.length == 50;
    } catch (e) {
      if (ticket == generation) {
        listError = message(e);
      }
    }
    if (ticket == generation) {
      loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> get(String id) async {
    final result = await command('get', {'id': id});
    return result == null ? null : object(result);
  }

  Future<Map<String, dynamic>> calendarOptions(
    String calendar,
    int? year,
  ) async => object(
    await command('calendar_options', {'calendar': calendar, 'year': year}),
  );

  Future<Map<String, dynamic>> currentCalendarDate(String calendar) async {
    final now = DateTime.now();
    return object(
      await command('calendar_date', {
        'calendar': calendar,
        'year': now.year,
        'month': now.month,
        'day': now.day,
      }),
    );
  }

  Future<void> save(
    Map<String, dynamic> data, {
    Map<String, dynamic>? original,
  }) async {
    await command(original == null ? 'create' : 'save', {
      'contact': data,
      if (original != null) 'id': original['id'],
      if (original != null) 'expected': original['data'],
    });
    await refresh();
  }

  Future<void> delete(Map<String, dynamic> original) async {
    await command('delete', {
      'id': original['id'],
      'expected': original['data'],
    });
    await refresh();
  }

  Future<void> resolve(
    Map<String, dynamic> conflict,
    Map<String, dynamic>? data,
  ) async {
    await command('resolve', {
      'id': conflict['id'],
      'resolution': {
        'observed': (conflict['candidates'] as List)
            .map((c) => c['version'])
            .toList(),
        'contact': data,
      },
    });
    await refresh();
  }

  Future<void> saveConfig(
    Map<String, dynamic> backend,
    Map<String, dynamic> secrets,
    bool remember,
  ) async {
    validateBackend(backend);
    final old = config['credential_ref'];
    final ref = 'sync-${DateTime.now().microsecondsSinceEpoch}';
    if (remember) {
      try {
        await secure.write(key: ref, value: jsonEncode(secrets));
      } catch (_) {
        throw AppFailure('secure_storage');
      }
    }
    final next = {
      ...publicBackend(backend),
      if (remember) 'credential_ref': ref,
    };
    try {
      final temp = File('${directory.path}/sync.json.tmp');
      await temp.writeAsString(jsonEncode(next), flush: true);
      await temp.rename('${directory.path}/sync.json');
    } catch (_) {
      if (remember) {
        await secure.delete(key: ref);
      }
      rethrow;
    }
    config = next;
    credentials = copy(secrets);
    if (old is String && old != ref) {
      try {
        await secure.delete(key: old);
      } catch (_) {
        syncMessage = '配置已保存，旧凭据清理未完成。';
      }
    }
    notifyListeners();
  }

  Future<void> synchronize() async {
    if (syncing) {
      return;
    }
    validateBackend(config);
    if (!host.beginSync()) {
      throw AppFailure('busy');
    }
    syncing = true;
    cancelling = false;
    syncMessage = null;
    notifyListeners();
    try {
      final result = object(
        unwrap(
          await host.synchronize(
            configuration: jsonEncode({
              ...publicBackend(config),
              ...credentials,
            }),
          ),
        ),
      );
      final complete = result['complete_scan'] == true;
      if (complete) {
        lastSync = DateTime.now().toIso8601String();
        try {
          await File('${directory.path}/last-sync.txt')
              .writeAsString('${identity['dataset']}\n$lastSync', flush: true);
        } catch (_) {
          /* Sync already committed; an optional timestamp must not report data failure. */
        }
      }
      syncMessage =
          '${complete ? '本轮同步完成' : '本轮同步未扫描完，请再次同步'} · 上传 ${result['uploaded']}，下载 ${result['downloaded']}';
    } catch (e) {
      syncMessage = message(e);
    } finally {
      syncing = false;
      cancelling = false;
      try {
        await refresh();
      } catch (e) {
        syncMessage = message(e);
      }
      notifyListeners();
    }
  }

  void cancel() {
    host.cancel();
    cancelling = true;
    notifyListeners();
  }

  String joinText() => jsonEncode({
    'format': supportsGroups ? 'card-weave-join/2' : 'card-weave-join/1',
    'dataset': identity['dataset'],
    if (config.isNotEmpty) 'backend': publicBackend(config),
  });
}
