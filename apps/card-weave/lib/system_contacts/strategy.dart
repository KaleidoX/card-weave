import 'dart:io';

import 'mapping.dart';
import 'contact_mapper.dart';
import 'vendors/realme/mapper.dart';
import '../contacts/fields.dart';
import 'vendors/realme/dates.dart';
import 'source.dart';

/// Import/export are independent capabilities: unsupported directions are absent.
abstract interface class SystemContactsImportStrategy {
  Future<String> permission({bool request = false});
  Future<void> openSettings();
  Future<List<Map<String, dynamic>>> page(String after);
  Future<Map<String, dynamic>> detail(String id);
  Future<ImportCandidate> mapContact(
    Map<String, dynamic> summary,
    Map<String, dynamic> detail,
  );
}

abstract interface class SystemContactsExportStrategy {
  Future<String> permission({bool request = false});
  Future<void> openSettings();

  /// Implementations must return an outcome for each record, never silently merge.
  Future<List<SystemContactExportResult>> exportContacts(
    List<Map<String, dynamic>> contacts,
  );
}

class SystemContactExportResult {
  final String contactId;
  final String? systemId, error;
  const SystemContactExportResult(this.contactId, {this.systemId, this.error});
}

class SystemContactsStrategy {
  final String name;
  final SystemContactsImportStrategy? importer;
  final SystemContactsExportStrategy? exporter;
  const SystemContactsStrategy(this.name, {this.importer, this.exporter});
}

class SystemContactsEnvironment {
  final String platform, manufacturer;
  const SystemContactsEnvironment(this.platform, this.manufacturer);
}

abstract interface class SystemContactsStrategyFactory {
  bool supports(SystemContactsEnvironment environment);
  SystemContactsStrategy create(SystemContactsEnvironment environment);
}

/// Most specific factories precede platform fallbacks. UI never branches by vendor.
class SystemContactsStrategyRegistry {
  final List<SystemContactsStrategyFactory> factories;
  const SystemContactsStrategyRegistry(this.factories);
  SystemContactsStrategy resolve(SystemContactsEnvironment environment) {
    for (final factory in factories) {
      if (factory.supports(environment)) return factory.create(environment);
    }
    return const SystemContactsStrategy('当前平台尚未支持系统通讯录');
  }
}

class AndroidContactsStrategyFactory implements SystemContactsStrategyFactory {
  @override
  bool supports(SystemContactsEnvironment environment) =>
      environment.platform == 'android';
  @override
  SystemContactsStrategy create(SystemContactsEnvironment environment) =>
      SystemContactsStrategy(
        'Android 系统通讯录',
        importer: AndroidContactsImportStrategy(AndroidContactsSource()),
      );
}

class AndroidContactsImportStrategy implements SystemContactsImportStrategy {
  final SystemContactsSource source;
  final SystemContactMapper mapper;
  const AndroidContactsImportStrategy(
    this.source, {
    this.mapper = const AndroidContactMapper(),
  });
  @override
  Future<String> permission({bool request = false}) =>
      source.permission(request: request);
  @override
  Future<void> openSettings() => source.openSettings();
  @override
  Future<List<Map<String, dynamic>>> page(String after) => source.page(after);
  @override
  Future<Map<String, dynamic>> detail(String id) =>
      source.detail(id, additionalMimeTypes: mapper.additionalMimeTypes);
  @override
  Future<ImportCandidate> mapContact(
    Map<String, dynamic> summary,
    Map<String, dynamic> detail,
  ) async {
    final candidate = await mapper.mapContact(summary, detail);
    // Transport and document constraints apply even to a fully custom mapper.
    candidate.error = detail['oversized'] == true
        ? '系统资料过大，请先在系统通讯录整理后重试'
        : detail['missing'] == true || (detail['rows'] as List? ?? []).isEmpty
        ? '源联系人已删除或没有可导入字段，请重新读取'
        : candidate.error ?? contactValidationError(candidate.contact);
    return candidate;
  }
}

Future<SystemContactsStrategy> systemContactsStrategy({
  required SolarToLunar convertSolarToLunar,
}) async {
  final manufacturer = Platform.isAndroid
      ? await AndroidContactsSource.channel.invokeMethod<String>(
              'manufacturer',
            ) ??
            ''
      : '';
  return SystemContactsStrategyRegistry([
    RealmeContactsStrategyFactory(convertSolarToLunar),
    AndroidContactsStrategyFactory(),
  ]).resolve(
    SystemContactsEnvironment(
      Platform.operatingSystem,
      manufacturer.toLowerCase(),
    ),
  );
}

class RealmeContactsStrategyFactory implements SystemContactsStrategyFactory {
  final SolarToLunar convertSolarToLunar;
  const RealmeContactsStrategyFactory(this.convertSolarToLunar);
  @override
  bool supports(SystemContactsEnvironment environment) =>
      environment.platform == 'android' &&
      environment.manufacturer.toLowerCase() == 'realme';
  @override
  SystemContactsStrategy create(SystemContactsEnvironment environment) =>
      SystemContactsStrategy(
        'realme 系统通讯录',
        importer: AndroidContactsImportStrategy(
          AndroidContactsSource(),
          mapper: RealmeContactMapper(convertSolarToLunar),
        ),
      );
}
