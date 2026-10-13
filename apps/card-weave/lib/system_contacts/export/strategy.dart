import 'dart:convert';
import 'dart:math';

import '../source.dart';
import 'mapper.dart';

abstract interface class SystemContactsExportStrategy {
  SystemContactWriteMapper get mapper;
  Future<String> permission({bool request = false});
  Future<void> openSettings();
  Future<List<Map<String, dynamic>>> accounts();
  Future<List<Map<String, dynamic>>> targets(String contactId);
  Future<Map<String, dynamic>> snapshot(String rawId);
  Future<Map<String, dynamic>?> link(String key);
  Future<void> saveLink(String key, Map<String, dynamic>? value);
  Future<Map<String, dynamic>?> recover(String token);
  Future<Map<String, dynamic>> write(Map<String, dynamic> request);
}

class AndroidContactsExportStrategy implements SystemContactsExportStrategy {
  @override
  final SystemContactWriteMapper mapper;
  const AndroidContactsExportStrategy({
    this.mapper = const AndroidContactWriteMapper(),
  });
  static const channel = AndroidContactsSource.channel;
  @override
  Future<String> permission({bool request = false}) async =>
      (await channel.invokeMethod<String>(
        request ? 'requestWritePermission' : 'writePermission',
      ))!;
  @override
  Future<void> openSettings() => AndroidContactsSource().openSettings();
  Future<List<Map<String, dynamic>>> _list(
    String method, [
    Map<String, dynamic>? args,
  ]) async => (await channel.invokeListMethod<dynamic>(
    method,
    args,
  ))!.map((v) => Map<String, dynamic>.from(v as Map)).toList();
  @override
  Future<List<Map<String, dynamic>>> accounts() => _list('writeAccounts');
  @override
  Future<List<Map<String, dynamic>>> targets(String contactId) =>
      _list('writeTargets', {'id': contactId});
  @override
  Future<Map<String, dynamic>> snapshot(String rawId) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMapMethod<String, dynamic>('writeSnapshot', {
          'id': rawId,
        }))!,
      );
  @override
  Future<Map<String, dynamic>?> link(String key) async {
    final value = await channel.invokeMethod<String>('linkGet', {'key': key});
    return value == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(value) as Map);
  }

  @override
  Future<void> saveLink(String key, Map<String, dynamic>? value) =>
      channel.invokeMethod<void>('linkPut', {
        'key': key,
        'value': value == null ? null : jsonEncode(value),
      });
  @override
  Future<Map<String, dynamic>?> recover(String token) async {
    final value = await channel.invokeMapMethod<String, dynamic>(
      'writeRecover',
      {'token': token},
    );
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  @override
  Future<Map<String, dynamic>> write(Map<String, dynamic> request) async =>
      Map<String, dynamic>.from(
        (await channel.invokeMapMethod<String, dynamic>(
          'writeApply',
          request,
        ))!,
      );
}

String writeToken() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String associationKey(String dataset, String contactId) =>
    '$dataset/$contactId';
