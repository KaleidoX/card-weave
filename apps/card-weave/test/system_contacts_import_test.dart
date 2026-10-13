import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/system_contacts/mapping.dart';
import 'package:card_weave/system_contacts/session.dart';
import 'package:card_weave/system_contacts/source.dart';
import 'package:card_weave/system_contacts/strategy.dart';
import 'package:card_weave/system_contacts/contact_mapper.dart';
import 'package:card_weave/system_contacts/vendors/realme/dates.dart';
import 'package:card_weave/model.dart';

Map<String, dynamic> summary(String id, String name) => {
  'id': id,
  'name': name,
};
Map<String, dynamic> detail(List<Map<String, dynamic>> rows) => {
  'rows': rows,
  'oversized': false,
};
Map<String, dynamic> row(
  String mime,
  String value, {
  String? type,
  String? label,
}) => {
  'mime': 'vnd.android.cursor.item/$mime',
  'data1': value,
  'data2': ?type,
  'label': ?label,
};

class FixtureSource implements SystemContactsSource {
  String state = 'granted';
  bool revoked = false;
  int reads = 0;
  @override
  Future<String> permission({bool request = false}) async => state;
  @override
  Future<void> openSettings() async {}
  @override
  Future<List<Map<String, dynamic>>> page(String after) async {
    reads++;
    if (revoked) throw PlatformException(code: 'permission');
    return [summary('1', 'Import One'), summary('2', 'Import Two')];
  }

  @override
  Future<Map<String, dynamic>> detail(
    String id, {
    Set<String> additionalMimeTypes = const {},
  }) async => {
    'rows': [row('name', id == '1' ? 'Import One' : 'Import Two')],
    'oversized': false,
  };
}

class FixtureVendorFactory implements SystemContactsStrategyFactory {
  @override
  bool supports(SystemContactsEnvironment e) =>
      e.platform == 'android' && e.manufacturer == 'fixture-vendor';
  @override
  SystemContactsStrategy create(SystemContactsEnvironment e) =>
      SystemContactsStrategy(
        'Fixture vendor',
        importer: AndroidContactsImportStrategy(FixtureSource()),
      );
}

class WholeContactMapper extends AndroidContactMapper {
  @override
  Set<String> get additionalMimeTypes => const {'vnd.fixture/contact'};
  @override
  Future<ImportCandidate> mapContact(
    Map<String, dynamic> summary,
    Map<String, dynamic> detail,
  ) async {
    final vendor = (detail['rows'] as List).singleWhere(
      (r) => r['mime'] == 'vnd.fixture/contact',
    );
    return super.mapContact(
      {...summary, 'name': vendor['data1']},
      {
        ...detail,
        'rows': [
          row('phone_v2', vendor['data2'] as String, label: '工作'),
          row('postal-address_v2', vendor['data3'] as String, label: '单位'),
          row('note', 'Converted vendor contact'),
        ],
      },
    );
  }
}

void main() async {
  test('Whole-contact strategy converts arbitrary fields and keeps size constraints', () async {
    final strategy = AndroidContactsImportStrategy(
      FixtureSource(),
      mapper: WholeContactMapper(),
    );
    final raw = detail([
      {
        'mime': 'vnd.fixture/contact',
        'data1': 'Vendor name',
        'data2': '2025550100',
        'data3': 'Fixture Street',
      },
    ]);
    final candidate = await strategy.mapContact(
      summary('source-id', 'Provider name'),
      raw,
    );
    expect(candidate.sourceId, 'source-id');
    expect(candidate.name, 'Vendor name');
    expect(candidate.contact['phones'], [
      {'label': '工作', 'value': '2025550100'},
    ]);
    expect(candidate.contact['addresses'], [
      {'label': '单位', 'value': 'Fixture Street'},
    ]);
    expect(candidate.contact['notes'], 'Converted vendor contact');
    expect(candidate.error, isNull);
    final oversized = await strategy.mapContact(
      summary('source-id', 'Provider name'),
      {...raw, 'oversized': true},
    );
    expect(oversized.error, isNotNull);
  });

  test('realme preserves one birthday per calendar and decodes yearless leap months', () async {
    final decoder = RealmeEventDates(
      (y, m, d) =>
          throw StateError('Yearless values do not need a reference year'),
    );
    final candidate = await mapSystemContact(
      summary('1', 'Fixture'),
      detail([
        {...row('contact_event', '19000229', type: '3'), 'data10': '0'},
        {...row('contact_event', '19001815', type: '1000'), 'data10': '1000'},
        {...row('contact_event', '19000616', type: '1000'), 'data10': '1000'},
      ]),
      decodeEventDate: decoder.decode,
    );
    final dates = candidate.contact['dates'] as List;
    expect(dates.length, 2);
    expect(dates[0]['year'], isNull);
    expect(dates[0]['day'], 29);
    expect(dates[1]['calendar'], 'chinese_lunar');
    expect(dates[1]['year'], isNull);
    expect(dates[1]['month'], 6);
    expect(dates[1]['is_leap_month'], true);
    expect(candidate.warnings.single, contains('多个农历生日'));
    expect(candidate.contact['notes'], contains('19000616'));
  });

  test('realme rejects unknown or contradictory encodings without losing raw metadata', () async {
    final decoder = RealmeEventDates(
      (y, m, d) => throw StateError('Invalid data must not be converted'),
    );
    for (final r in [
      {...row('contact_event', '20261012', type: '1000'), 'data10': '0'},
      {...row('contact_event', '20261012', type: '3'), 'data10': '42'},
      {...row('contact_event', '20261012', type: '1000'), 'data11': 'unknown'},
      row('contact_event', '19002501', type: '1000'),
      row('contact_event', '19000631', type: '1000'),
      row('contact_event', '20230229', type: '1000'),
      row('contact_event', '202610120', type: '1000'),
    ]) {
      final c = await mapSystemContact(
        summary('1', 'Fixture'),
        detail([r]),
        decodeEventDate: decoder.decode,
      );
      expect(c.contact['dates'], isEmpty);
      expect(c.warnings, isNotEmpty);
      expect(c.contact['notes'], contains(r['data1']));
      if (r.containsKey('data11')) {
        expect(c.contact['notes'], contains('data11=unknown'));
      }
    }
  });

  test('Standard Android fields preserve yearless birthdays and report ambiguous extra values', () async {
    final c = await mapSystemContact(
      summary('1', 'Fixture'),
      detail([
        {
          'mime': 'vnd.android.cursor.item/name',
          'data2': 'Given',
          'data3': 'Family',
          'data5': 'Middle',
        },
        row('phone_v2', '+1 (202) 555-0100', label: '手机'),
        row('email_v2', 'fixture@example.invalid', label: '工作'),
        row('postal-address_v2', 'Line1\nLine2', label: '住宅'),
        row('website', 'https://first.invalid'),
        row('website', 'https://second.invalid'),
        row('contact_event', '--02-29', type: '3'),
        row('contact_event', '1990-10-12', type: '3'),
        row('contact_event', '2023-02-29', type: '1'),
        {...row('contact_event', '2025-06-01', type: '1'), 'data4': 'lunar'},
        row('vendor_lunar', '2025-06-01'),
        row('relation', 'Synthetic Relative', label: '父亲'),
      ]),
    );
    expect(c.error, isNull);
    expect(c.contact['middle_name'], 'Middle');
    expect(c.contact['dates'], [
      {
        'kind': 'birthday',
        'label': '',
        'calendar': 'gregorian',
        'year': null,
        'month': 2,
        'day': 29,
        'is_leap_month': false,
      },
    ]);
    expect(c.contact['notes'], contains('https://second.invalid'));
    expect(c.contact['notes'], contains('1990-10-12'));
    expect(c.contact['notes'], contains('2023-02-29'));
    expect(c.contact['notes'], contains('2025-06-01'));
    expect(c.warnings.join(), contains('厂商'));
    expect((c.contact['relations'] as List).single, {
      'label': '父亲',
      'value': 'Synthetic Relative',
    });
  });

  test(
    'Duplicates are conservative and both incoming peers default unselected',
    () async {
      final index = ImportDuplicateIndex();
      index.addExisting({
        'display_name': 'Local',
        'phones': [
          {'value': '+1 202-555-0100'},
        ],
      });
      final a = await mapSystemContact(
        summary('1', 'A'),
        detail([row('phone_v2', '+1(202)5550100')]),
      );
      final b = await mapSystemContact(
        summary('2', 'B'),
        detail([row('phone_v2', '+1(202)5550100')]),
      );
      final c = await mapSystemContact(
        summary('3', 'C'),
        detail([row('phone_v2', '2025550100')]),
      );
      index.add(a);
      index.add(b);
      index.add(c);
      expect(a.selected, isFalse);
      expect(b.selected, isFalse);
      expect(c.selected, isTrue);
      expect(a.duplicates.join(), contains('本次'));
      expect(b.duplicates.join(), contains('已有'));
    },
  );

  test('Missing source detail cannot create a name-only record', () async {
    final c = await mapSystemContact(summary('1', 'Removed'), detail([]));
    expect(c.error, isNotNull);
  });

  test(
    'Limits block oversized contacts without silently truncating fields',
    () async {
      final c = await mapSystemContact(
        summary('1', 'A'),
        detail(List.generate(33, (i) => row('phone_v2', '$i'))),
      );
      expect(c.error, isNotNull);
      expect((c.contact['phones'] as List).length, 33);
    },
  );

  test(
    'Denied and revoked permission never yield an importable partial scan',
    () async {
      final source = FixtureSource()..state = 'blocked';
      final s = ContactsImportSession(
        strategy: AndroidContactsImportStrategy(source),
        command: (a, v) async => [],
        refresh: () async {},
      );
      await s.load();
      expect(source.reads, 0);
      expect(s.permission, 'blocked');
      expect(s.ready, isFalse);
      source.state = 'granted';
      source.revoked = true;
      await s.load();
      expect(s.permission, 'denied');
      expect(s.ready, isFalse);
      expect(s.error, isNotNull);
      s.dispose();
    },
  );

  test('Duplicate scan reads beyond first local page and includes conflict candidates', () async {
    final s = ContactsImportSession(
      strategy: AndroidContactsImportStrategy(FixtureSource()),
      command: (a, v) async {
        if (a == 'list') {
          return v['offset'] == 0
              ? List.generate(
                  50,
                  (i) => {
                    'data': {'display_name': 'Local $i'},
                  },
                )
              : [
                  {
                    'data': {'display_name': 'Import One'},
                  },
                ];
        }
        if (a == 'conflicts') {
          return [
            {
              'candidates': [
                {
                  'contact': {
                    'data': {'display_name': 'Import Two'},
                  },
                },
              ],
            },
          ];
        }
        return true;
      },
      refresh: () async {},
    );
    await s.load();
    expect(s.ready, isTrue);
    expect(s.selectedCount, 0);
    expect(s.candidates.every((c) => c.duplicates.isNotEmpty), isTrue);
    s.dispose();
  });

  test('Partial failure retries only failed records and cancel keeps completed writes', () async {
    var fail = true;
    final writes = <String>[];
    late ContactsImportSession s;
    var cancelAfterWrite = false;
    s = ContactsImportSession(
      strategy: AndroidContactsImportStrategy(FixtureSource()),
      command: (a, v) async {
        if (a == 'list' || a == 'conflicts') return [];
        if (a == 'validate_contact') return true;
        final name = v['contact']['display_name'] as String;
        if (name == 'Import Two' && fail) throw AppFailure('busy');
        writes.add(name);
        if (cancelAfterWrite) s.cancel();
        return {'id': 'id-${writes.length}'};
      },
      refresh: () async {},
    );
    await s.load();
    await s.run();
    expect(s.createdCount, 1);
    expect(s.failedCount, 1);
    fail = false;
    await s.run(retry: true);
    expect(writes, ['Import One', 'Import Two']);
    await s.run(retry: true);
    expect(writes.length, 2);
    await s.load();
    cancelAfterWrite = true;
    await s.run();
    expect(s.createdCount, 1);
    expect(s.selectedCount, 1);
    expect(writes.length, 3);
    s.dispose();
  });

  test('Unacknowledged writes cannot be blindly retried', () async {
    var writes = 0;
    final s = ContactsImportSession(
      strategy: AndroidContactsImportStrategy(FixtureSource()),
      command: (a, v) async {
        if (a == 'list' || a == 'conflicts') return [];
        if (a == 'validate_contact') return true;
        writes++;
        throw PlatformException(code: 'lost_response');
      },
      refresh: () async {},
    );
    await s.load();
    await s.run();
    expect(s.uncertainCount, 2);
    expect(s.failedCount, 0);
    await s.run(retry: true);
    expect(writes, 2);
    s.dispose();
  });

  test('Strategy registry prefers vendor adapter, falls back to Android and exposes no export', () async {
    final generic = SystemContactsStrategyRegistry([
      FixtureVendorFactory(),
      AndroidContactsStrategyFactory(),
    ]);
    expect(
      generic
          .resolve(const SystemContactsEnvironment('android', 'fixture-vendor'))
          .name,
      'Fixture vendor',
    );
    expect(
      generic
          .resolve(const SystemContactsEnvironment('android', 'realme'))
          .importer,
      isNotNull,
    );
    expect(
      generic
          .resolve(const SystemContactsEnvironment('android', 'realme'))
          .exporter,
      isNotNull,
    );
    expect(
      generic.resolve(const SystemContactsEnvironment('ios', 'apple')).importer,
      isNull,
    );
  });
}
