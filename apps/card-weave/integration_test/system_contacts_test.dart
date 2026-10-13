import 'package:card_weave/system_contacts/export/strategy.dart';

import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:card_weave/system_contacts/page.dart';
import 'package:card_weave/system_contacts/session.dart';
import 'package:card_weave/system_contacts/strategy.dart';
import 'package:card_weave/system_contacts/source.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/src/rust/frb_generated.dart';
import 'package:card_weave/ui/theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'System provider preview, import, reopen and duplicate detection',
    (t) async {
      await RustLib.init();
      final directory = await (await getApplicationSupportDirectory())
          .createTemp('cw-system-import-');
      final canonical = await directory.resolveSymbolicLinks();
      final m = AppModel();
      final opened = await m.host.initialize(
        path: '$canonical/book',
        create: true,
      );
      expect(jsonDecode(opened)['ok'], true, reason: opened);
      m.identity = object(unwrap(opened));
      m.ready = true;
      m.initialized = true;
      final strategy = await systemContactsStrategy(
        convertSolarToLunar: (year, month, day) async => object(
          await m.command('calendar_date', {
            'calendar': 'chinese_lunar',
            'year': year,
            'month': month,
            'day': day,
          }),
        ),
      );
      expect(strategy.importer, isNotNull);
      expect(strategy.exporter, isNotNull);
      await t.pumpWidget(
        CupertinoApp(
          theme: const AppTheme(Brightness.light).cupertino,
          home: SystemContactsImportPage(m),
        ),
      );
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 200; i++) {
          await t.pump(const Duration(milliseconds: 200));
          if (condition()) {
            await t.pumpAndSettle();
            return;
          }
        }
        fail('Expected import UI state');
      }

      Future<void> tap(String text) async {
        final f = find.text(text).last;
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pump();
      }

      await waitFor(() => find.text('读取系统通讯录').evaluate().isNotEmpty);
      await tap('读取系统通讯录');
      await waitFor(() => find.text('取消全选').evaluate().isNotEmpty);
      await tap('取消全选');
      final field = find.byType(CupertinoSearchTextField);
      await t.enterText(field, 'Fixture');
      await t.pumpAndSettle();
      final list = await strategy.importer!.page('0');
      final summary = list.singleWhere(
        (v) => (v['name'] as String).contains('Fixture'),
      );
      final source = AndroidContactsSource();
      final ordinary = await source.detail(summary['id'] as String);
      final extra = (ordinary['rows'] as List).singleWhere(
        (r) => r['mime'] == 'vnd.fixture/contact',
      );
      expect(extra.containsKey('data1'), false);
      final opted = await source.detail(
        summary['id'] as String,
        additionalMimeTypes: {'vnd.fixture/contact'},
      );
      expect(
        (opted['rows'] as List).singleWhere(
          (r) => r['mime'] == 'vnd.fixture/contact',
        )['data1'],
        'Vendor fixture',
      );
      final name = summary['name'] as String;
      await tap(name);
      await tap('导入已选 1 位');
      await t.pumpAndSettle();
      await tap('导入');
      await waitFor(
        () => find.textContaining('已导入 1 位，失败 0 位').evaluate().isNotEmpty,
      );
      final contacts =
          await m.command('list', {'search': '', 'offset': 0}) as List;
      expect(contacts.length, 1);
      final link = await strategy.exporter!.link(
        associationKey(
          m.identity['dataset'] as String,
          contacts.single['id'] as String,
        ),
      );
      expect(link, isNotNull);
      expect(link!['pending'], isNull);
      final data = contacts.single['data'];
      expect(data['phones'].single['value'], '+1 202-555-0199');
      expect(data['emails'].single['value'], 'cw-import@example.invalid');
      expect(data['dates'].single['year'], isNull);
      expect(data['dates'].single['month'], 2);
      expect(data['dates'].single['day'], 29);
      expect((await m.command('status'))['pending_outbox'], 1);
      await m.command('close');
      unwrap(await m.host.initialize(path: '$canonical/book', create: false));
      final second = ContactsImportSession(
        strategy: strategy.importer!,
        command: m.command,
        refresh: m.refresh,
      );
      await second.load();
      final duplicate = second.candidates.singleWhere(
        (v) => v.sourceId == summary['id'],
      );
      expect(duplicate.selected, isFalse);
      expect(duplicate.duplicates, isNotEmpty);
      expect(
        (await m.command('list', {'search': '', 'offset': 0}) as List).length,
        1,
      );
      second.dispose();
      await t.pumpWidget(const SizedBox());
      await m.command('close');
      m.dispose();
      await directory.delete(recursive: true);
    },
  );
}
