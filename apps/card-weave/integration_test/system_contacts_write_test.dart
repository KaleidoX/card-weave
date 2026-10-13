import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/system_contacts/export/session.dart';
import 'package:card_weave/system_contacts/export/strategy.dart';
import 'package:card_weave/system_contacts/source.dart';
import 'package:card_weave/system_contacts/strategy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android provider create, link, update, baseline, stale preview and recovery',
    (t) async {
      await t.pumpWidget(const CupertinoApp(home: Text('系统通讯录写入验证')));
      const writer = AndroidContactsExportStrategy();
      expect(await writer.permission(), 'granted');
      final accounts = await writer.accounts();
      expect(accounts, isNotEmpty);
      final stamp = DateTime.now().microsecondsSinceEpoch.toString();
      final dataset = 'write-fixture-$stamp';
      final data = emptyContact()
        ..['display_name'] = 'Write Fixture $stamp'
        ..['phones'] = [
          {'label': '手机', 'value': '+1 202-555-0188'},
        ]
        ..['emails'] = [
          {'label': '个人', 'value': 'cw-write@example.invalid'},
        ]
        ..['dates'] = [
          {
            'kind': 'birthday',
            'label': '',
            'calendar': 'gregorian',
            'year': null,
            'month': 2,
            'day': 29,
            'is_leap_month': false,
          },
        ];
      Map<String, dynamic> record() => {
        'id': 'fixture-contact',
        'data': jsonDecode(jsonEncode(data)),
      };
      final first = ContactWriteSession(writer, dataset, record());
      await first.load();
      await first.choose(null, newAccount: accounts.first);
      final staleNew = ContactWriteSession(writer, dataset, record());
      await staleNew.load();
      await first.write();
      await expectLater(staleNew.write(), throwsA(isA<StateError>()));
      final rawId = first.target!['rawId'] as String;
      debugPrint('WRITE_FIXTURE_RAW_ID=$rawId');
      final source = AndroidContactsSource();
      final summary = {
        'id': first.target!['contactId'],
        'name': data['display_name'],
      };
      final importer = AndroidContactsImportStrategy(source);
      final read = await importer.mapContact(
        summary,
        await importer.detail(summary['id'] as String),
      );
      expect(read.contact['phones'], data['phones']);
      expect(read.contact['emails'], data['emails']);
      expect(read.contact['dates'], data['dates']);
      expect(read.warnings, isEmpty);
      final again = ContactWriteSession(writer, dataset, record());
      await again.load();
      expect(again.target!['rawId'], rawId);
      expect(again.fields, isEmpty);
      // Simulate an app-local edit; no system copy is created.
      data['organization'] = 'App organization';
      final edited = ContactWriteSession(writer, dataset, record());
      await edited.load();
      expect(edited.fields.single.key, 'organization');
      expect(edited.fields.single.selected, isTrue);
      await edited.write();
      expect(edited.target!['rawId'], rawId);
      expect(
        writer.mapper
            .project(await writer.snapshot(rawId))['organization']!
            .single['data1'],
        'App organization',
      );
      // A second actor edits the provider through its public transaction endpoint.
      Future<void> externalNote(String value) async {
        final snap = await writer.snapshot(rawId);
        final fields = writer.mapper.project(snap);
        fields['notes'] = [
          {'data1': value},
        ];
        await writer.write({
          'token': writeToken(),
          ...{
            for (final k in [
              'rawId',
              'lookup',
              'version',
              'accountName',
              'accountType',
            ])
              k: snap[k],
          },
          'patches': writer.mapper.patches(snap, fields, {'notes'}),
        });
      }

      await externalNote('System note');
      final systemOnly = ContactWriteSession(writer, dataset, record());
      await systemOnly.load();
      final note = systemOnly.fields.singleWhere((f) => f.key == 'notes');
      expect(note.selected, isFalse);
      expect(note.conflict, isFalse);
      data['notes'] = 'App note';
      final conflict = ContactWriteSession(writer, dataset, record());
      await conflict.load();
      final disputed = conflict.fields.singleWhere((f) => f.key == 'notes');
      expect(disputed.conflict, isTrue);
      expect(disputed.selected, isFalse);
      disputed.selected = true;
      await conflict.write();
      expect(
        writer.mapper
            .project(await writer.snapshot(rawId))['notes']!
            .single['data1'],
        'App note',
      );
      // Provider changes after preview: transaction must reject without partial edits.
      data['organization'] = 'New organization';
      final stale = ContactWriteSession(writer, dataset, record());
      await stale.load();
      await externalNote('Later system note');
      await expectLater(stale.write(), throwsA(anything));
      expect(
        writer.mapper
            .project(await writer.snapshot(rawId))['organization']!
            .single['data1'],
        'App organization',
      );
      expect(stale.pending, isTrue);
      await stale.discardUnapplied();
      expect(stale.pending, isFalse);
      await stale.write();
      expect(stale.target!['rawId'], rawId);
      // Simulate lost acknowledgement by retaining the journal after provider commit.
      data['website'] = 'https://example.invalid';
      final recovering = ContactWriteSession(writer, dataset, record());
      await recovering.load();
      final target = recovering.target!;
      final encoded = writer.mapper.encode(data);
      final request = {
        'token': writeToken(),
        ...{
          for (final k in [
            'rawId',
            'lookup',
            'version',
            'accountName',
            'accountType',
          ])
            k: target[k],
        },
        'patches': writer.mapper.patches(target, encoded.fields, {'website'}),
      };
      await writer.saveLink(recovering.key, {
        ...recovering.association!,
        'pending': {
          'request': request,
          'app': encoded.fields,
          'selected': ['website'],
        },
      });
      await writer.write(request);
      final resumed = ContactWriteSession(writer, dataset, record());
      await resumed.load();
      expect(resumed.pending, isTrue);
      await resumed.write();
      expect(resumed.pending, isFalse);
      expect(resumed.target!['rawId'], rawId);
      // Imported contacts remember an unambiguous source; another dataset does not inherit it.
      expect(
        await associateImported(
          writer,
          dataset,
          summary['id'] as String,
          'imported',
          read.contact,
        ),
        isTrue,
      );
      expect(
        (await writer.link(associationKey(dataset, 'imported')))!['rawId'],
        rawId,
      );
      expect(
        await writer.link(associationKey('$dataset-other', 'imported')),
        isNull,
      );
      // Missing linked targets fail closed; they never silently create a replacement.
      final saved = await writer.link(
        associationKey(dataset, 'fixture-contact'),
      );
      await writer.saveLink(associationKey(dataset, 'missing'), {
        ...saved!,
        'rawId': '999999999',
      });
      final missing = ContactWriteSession(writer, dataset, {
        'id': 'missing',
        'data': data,
      });
      await expectLater(missing.load(), throwsA(anything));
      await writer.saveLink(associationKey(dataset, 'missing'), null);

      // The host prepares this standard Provider fixture, including an unowned department.
      final protected = (await source.page('0'))
          .singleWhere((v) => v['name'] == 'Write Protected Fixture');
      final protectedTarget = (await writer.targets(protected['id'] as String))
          .single;
      final preserving = ContactWriteSession(writer, dataset, {
        'id': 'protected',
        'data': {
          ...emptyContact(),
          'display_name': 'Write Protected Fixture',
          'organization': 'Changed company',
        },
      });
      await preserving.choose(protectedTarget);
      for (final f in preserving.fields) {
        f.selected = f.key == 'organization';
      }
      await preserving.write();
      final rows = preserving.target!['rows'] as List;
      expect(
        rows.singleWhere(
          (r) => r['mime'] == 'vnd.android.cursor.item/organization',
        )['data5'],
        'Keep department',
      );
      expect(
        rows.singleWhere((r) => r['mime'] == 'vnd.fixture/contact')['data1'],
        'Keep extension',
      );
      expect(
        rows.singleWhere(
          (r) => r['mime'] == 'vnd.android.cursor.item/phone_v2',
        )['data1'],
        '+1 202-555-0190',
      );
      expect(preserving.warnings.any((w) => w.contains('只读')), isTrue);
      await writer.saveLink(associationKey(dataset, 'protected'), null);

      // Exercise the remaining standard fields and explicit clearing.
      data.addAll({
        'nickname': 'Writer nickname',
        'name_prefix': '',
        'name_suffix': '',
        'phonetic_given_name': 'Writer',
        'addresses': [
          {'label': '住宅', 'value': '123 Test Street'},
        ],
        'instant_messages': [
          {'label': 'Matrix', 'value': '@writer:example.invalid'},
        ],
        'relations': [
          {'label': '同事', 'value': 'Another Fixture'},
        ],
        'job_title': 'Engineer',
      });
      final expanded = ContactWriteSession(writer, dataset, record());
      await expanded.load();
      for (final f in expanded.fields) {
        f.selected = true;
      }
      await expanded.write();
      final expandedRead = await importer.mapContact(
        summary,
        await importer.detail(summary['id'] as String),
      );
      for (final key in [
        'nickname',
        'phonetic_given_name',
        'addresses',
        'instant_messages',
        'relations',
        'job_title',
      ]) {
        expect(expandedRead.contact[key], data[key], reason: key);
      }
      data['phones'] = [];
      data['addresses'] = [];
      data['website'] = '';
      final clearing = ContactWriteSession(writer, dataset, record());
      await clearing.load();
      await clearing.write();
      final cleared = writer.mapper.project(await writer.snapshot(rawId));
      expect(cleared['phones'], isEmpty);
      expect(cleared['addresses'], isEmpty);
      expect(cleared['website'], isEmpty);

      final lunar = {
        ...data,
        'dates': [
          {
            'kind': 'birthday',
            'label': '',
            'calendar': 'chinese_lunar',
            'year': null,
            'month': 1,
            'day': 1,
            'is_leap_month': false,
          },
        ],
      };
      expect(writer.mapper.encode(lunar).blocked, contains('dates'));
      await writer.saveLink(associationKey(dataset, 'imported'), null);
      await writer.saveLink(associationKey(dataset, 'fixture-contact'), null);
    },
  );
}
