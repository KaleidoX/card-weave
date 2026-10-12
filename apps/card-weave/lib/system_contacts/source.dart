import 'package:flutter/services.dart';

abstract interface class SystemContactsSource {
  Future<String> permission({bool request = false});
  Future<void> openSettings();
  Future<List<Map<String, dynamic>>> page(String after);
  Future<Map<String, dynamic>> detail(
    String id, {
    Set<String> additionalMimeTypes = const {},
  });
}

class AndroidContactsSource implements SystemContactsSource {
  static const channel = MethodChannel('io.cardweave/system_contacts');
  @override
  Future<String> permission({bool request = false}) async => (await channel
      .invokeMethod<String>(request ? 'requestPermission' : 'permission'))!;
  @override
  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');
  @override
  Future<List<Map<String, dynamic>>> page(String after) async =>
      (await channel.invokeListMethod<dynamic>('page', {
        'after': after,
      }))!.map((v) => Map<String, dynamic>.from(v as Map)).toList();
  @override
  Future<Map<String, dynamic>> detail(
    String id, {
    Set<String> additionalMimeTypes = const {},
  }) async => Map<String, dynamic>.from(
    (await channel.invokeMapMethod<String, dynamic>('detail', {
      'id': id,
      'additionalMimeTypes': additionalMimeTypes.toList(),
    }))!,
  );
}
