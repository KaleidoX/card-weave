import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../model.dart';
import 'mapping.dart';
import 'strategy.dart';

typedef ImportCommand = Future<dynamic> Function(
  String action,
  Map<String, dynamic> arguments,
);

/// Owns a single preview/import session; platform access is supplied by a strategy.
class ContactsImportSession extends ChangeNotifier {
  final SystemContactsImportStrategy strategy;
  final ImportCommand command;
  final Future<void> Function() refresh;
  final List<ImportCandidate> candidates = [];
  bool loading = false, importing = false, ready = false, finished = false;
  bool _cancelled = false, _disposed = false;
  String permission = 'unknown';
  String? error;
  int processed = 0, requested = 0;
  ContactsImportSession({
    required this.strategy,
    required this.command,
    required this.refresh,
  });
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void cancel() {
    _cancelled = true;
    changed();
  }

  @override
  void dispose() {
    _cancelled = true;
    _disposed = true;
    super.dispose();
  }

  Future<void> load({bool requestPermission = false}) async {
    if (loading || importing) return;
    loading = true;
    ready = false;
    finished = false;
    error = null;
    _cancelled = false;
    candidates.clear();
    changed();
    try {
      permission = await strategy.permission(request: requestPermission);
      if (permission != 'granted' || _cancelled) return;
      final duplicates = ImportDuplicateIndex();
      for (var offset = 0; !_cancelled; offset += 50) {
        final existing =
            await command('list', {'search': '', 'offset': offset}) as List;
        for (final c in existing) {
          duplicates.addExisting(object(c['data']));
        }
        if (existing.length < 50) break;
      }
      if (_cancelled) return;
      for (final conflict in await command('conflicts', {}) as List) {
        for (final candidate in conflict['candidates'] as List? ?? []) {
          final contact = candidate['contact'];
          if (contact != null) duplicates.addExisting(object(contact['data']));
        }
      }
      var after = '0';
      while (!_cancelled) {
        final page = await strategy.page(after);
        for (final summary in page) {
          if (_cancelled) break;
          final detail = await strategy.detail(summary['id'] as String);
          final candidate = await strategy.mapContact(summary, detail);
          if (candidate.error == null) {
            try {
              await command('validate_contact', {'contact': candidate.contact});
            } on AppFailure {
              candidate.error = '资料不符合联系人格式，请在系统通讯录整理后重试';
            }
          }
          if (_cancelled) break;
          duplicates.add(candidate);
          candidates.add(candidate);
          changed();
        }
        if (page.length < 50) break;
        final next = page.last['id'] as String;
        if (next == after) throw StateError('Non advancing contact page');
        after = next;
      }
      ready = !_cancelled;
      if (_cancelled && !_disposed) error = '已停止读取，请重新读取后选择导入';
    } on PlatformException catch (e) {
      if (e.code == 'permission') permission = 'denied';
      error = e.code == 'permission' ? '通讯录权限已撤销，请重新授权' : '无法读取系统通讯录，请重试';
    } catch (_) {
      error = '无法准备导入列表，请重试';
    } finally {
      loading = false;
      changed();
    }
  }

  void toggle(ImportCandidate c) {
    if (!ready ||
        importing ||
        c.createdId != null ||
        (c.error != null && !c.importFailed)) {
      return;
    }
    c.selected = !c.selected;
    changed();
  }

  void selectAllSafe() {
    for (final c in candidates) {
      c.selected =
          c.createdId == null && c.error == null && c.duplicates.isEmpty;
    }
    changed();
  }

  void deselectAll() {
    for (final c in candidates) {
      c.selected = false;
    }
    changed();
  }

  int get selectedCount => candidates
      .where((c) => c.selected && c.createdId == null && c.error == null)
      .length;
  int get createdCount => candidates.where((c) => c.createdId != null).length;
  int get uncertainCount => candidates.where((c) => c.uncertain).length;
  int get failedCount => candidates.where((c) => c.importFailed).length;

  Future<void> run({bool retry = false}) async {
    if (!ready || importing || loading) return;
    final chosen = candidates
        .where(
          (c) =>
              c.createdId == null &&
              (retry ? c.importFailed : c.selected && c.error == null),
        )
        .toList();
    if (chosen.isEmpty) return;
    importing = true;
    finished = false;
    _cancelled = false;
    error = null;
    processed = 0;
    requested = chosen.length;
    changed();
    try {
      for (final c in chosen) {
        if (_cancelled) break;
        try {
          final result = await command('create', {'contact': c.contact});
          c.createdId = result['id'] as String;
          c.selected = false;
          c.importFailed = false;
          c.error = null;
        } catch (e) {
          c.importFailed =
              e is AppFailure &&
              const {
                'invalid_input',
                'busy',
                'cancelled',
                'conflict_requires_resolution',
              }.contains(e.code);
          c.uncertain = !c.importFailed;
          c.selected = false;
          c.error = c.uncertain ? '未收到保存结果，请返回后重新读取并核对重复提示，避免重复导入' : message(e);
        }
        processed++;
        changed();
      }
    } finally {
      try {
        await refresh();
      } catch (_) {
        error = '导入结果已保留，联系人列表刷新失败，请返回后刷新';
      }
      importing = false;
      finished = true;
      changed();
    }
  }
}
