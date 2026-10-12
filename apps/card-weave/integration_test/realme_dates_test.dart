import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/src/rust/frb_generated.dart';
import 'package:card_weave/system_contacts/vendors/realme/mapper.dart';
import 'package:card_weave/system_contacts/source.dart';
import 'package:card_weave/system_contacts/vendors/realme/dates.dart';
import 'package:card_weave/system_contacts/strategy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'realme solar anchors and yearless lunar dates persist through Rust',
    (tester) async {
      await RustLib.init();
      final directory = await (await getApplicationSupportDirectory())
          .createTemp('cw-realme-dates-');
      final path = '${await directory.resolveSymbolicLinks()}/book';
      final model = AppModel();
      unwrap(await model.host.initialize(path: path, create: true));
      final decoder = RealmeEventDates(
        (year, month, day) async => object(
          await model.command('calendar_date', {
            'calendar': 'chinese_lunar',
            'year': year,
            'month': month,
            'day': day,
          }),
        ),
      );
      try {
        final cases = [
          ('20261012', '1000', '1000', 'chinese_lunar', 2026, 9, 3, false),
          ('20250725', '1000', '1000', 'chinese_lunar', 2025, 6, 1, true),
          ('20250201', '3', '1000', 'chinese_lunar', 2025, 1, 4, false),
          ('19000615', '1000', '1000', 'chinese_lunar', null, 6, 15, false),
          ('19001815', '1000', '1000', 'chinese_lunar', null, 6, 15, true),
          ('19000229', '3', '0', 'gregorian', null, 2, 29, false),
          ('1604-02-29', '3', '0', 'gregorian', null, 2, 29, false),
          ('--10-12', '3', '', 'gregorian', null, 10, 12, false),
          ('20001012', '3', '', 'gregorian', 2000, 10, 12, false),
        ];
        final ids = <String>[];
        final expected = <Map<String, dynamic>>[];
        for (var i = 0; i < cases.length; i++) {
          final c = cases[i];
          final candidate =
              await AndroidContactsImportStrategy(
                AndroidContactsSource(),
                mapper: RealmeContactMapper(decoder.convertSolarToLunar),
              ).mapContact(
                {'id': '$i', 'name': 'Date Fixture $i'},
                {
                  'rows': [
                    {
                      'mime': 'vnd.android.cursor.item/contact_event',
                      'data1': c.$1,
                      'data2': c.$2,
                      'data10': c.$3,
                    },
                  ],
                },
              );
          expect(candidate.error, isNull);
          expect(candidate.warnings, isEmpty);
          final date = {
            'kind': 'birthday',
            'label': '',
            'calendar': c.$4,
            'year': c.$5,
            'month': c.$6,
            'day': c.$7,
            'is_leap_month': c.$8,
          };
          expect(candidate.contact['dates'], [date]);
          expect(
            await model.command('validate_contact', {
              'contact': candidate.contact,
            }),
            true,
          );
          final saved = object(
            await model.command('create', {'contact': candidate.contact}),
          );
          ids.add(saved['id'] as String);
          expected.add(date);
        }
        final registry = SystemContactsStrategyRegistry([
          RealmeContactsStrategyFactory(decoder.convertSolarToLunar),
          AndroidContactsStrategyFactory(),
        ]);
        expect(
          registry
              .resolve(const SystemContactsEnvironment('android', 'realme'))
              .name,
          'realme 系统通讯录',
        );
        expect(
          registry
              .resolve(const SystemContactsEnvironment('android', 'other'))
              .name,
          'Android 系统通讯录',
        );
        await model.command('close');
        unwrap(await model.host.initialize(path: path, create: false));
        for (var i = 0; i < ids.length; i++) {
          final saved = await model.get(ids[i]);
          expect(saved!['data']['dates'], [expected[i]]);
        }
        expect((await model.command('status'))['pending_outbox'], cases.length);
      } finally {
        await model.command('close');
        model.dispose();
        if (await Directory(directory.path).exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
