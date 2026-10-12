import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:card_weave/main.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/contacts/date_format.dart';
import 'package:card_weave/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Typed dates save, edit and reopen through Android SQLite', (
    tester,
  ) async {
    await RustLib.init();
    final model = AppModel();
    final given = 'Fixture${DateTime.now().microsecondsSinceEpoch}';
    final name = '$given 明 张';
    await tester.pumpWidget(CardWeaveApp(model: model));
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        if (condition()) {
          await tester.pumpAndSettle();
          return;
        }
      }
      fail('Timed out');
    }

    Future<void> tap(String label) async {
      await tester.pumpAndSettle();
      final f = ['新建联系人', '展开姓名细分', '收起姓名细分'].contains(label)
          ? find.bySemanticsLabel(RegExp(label))
          : find.text(label).last;
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    await waitFor(() => model.ready && !model.loading);
    if (!model.initialized) {
      await tap('创建本地通讯录');
      await waitFor(() => model.initialized && !model.loading);
    }
    expect(model.listError, isNull);
    String? id;
    try {
      await tap('新建联系人');
      final field = find.byKey(const ValueKey('input-姓名'));
      await tester.enterText(field, name);
      expect(find.byKey(const ValueKey('input-姓氏')), findsNothing);
      expect(find.byKey(const ValueKey('input-名字')), findsNothing);
      await tap('展开姓名细分');
      await tester.enterText(find.byKey(const ValueKey('input-姓氏')), '张');
      await tester.enterText(find.byKey(const ValueKey('input-名字')), given);
      await tester.enterText(find.byKey(const ValueKey('input-中间名')), '明');
      await tap('收起姓名细分');
      expect(find.byKey(const ValueKey('input-姓氏')), findsNothing);
      Future<void> pick(int wheel, int index) async {
        final picker = find.byType(CupertinoPicker).at(wheel);
        await tester.ensureVisible(picker);
        tester
            .widget<CupertinoPicker>(picker)
            .scrollController!
            .jumpToItem(index);
        await tester.pumpAndSettle();
      }

      await tap('添加日期');
      await pick(1, 2);
      await pick(2, 29);
      await tap('添加日期');
      expect(find.text('农历生日'), findsOneWidget);
      await pick(1, 2);
      await pick(2, 1);
      await tap('完成');
      await waitFor(
        () => model.contacts.any((c) => c['data']['display_name'] == name),
      );
      id =
          model.contacts.firstWhere(
                (c) => c['data']['display_name'] == name,
              )['id']
              as String;
      final saved = (await model.get(id))!['data'];
      expect(saved['version'], 2);
      expect(saved['display_name'], name);
      expect(saved['family_name'], '张');
      expect(saved['given_name'], given);
      expect(saved['middle_name'], '明');
      expect(saved['dates'].length, 2);
      expect(saved['dates'][0]['kind'], 'birthday');
      expect(saved['dates'][0]['calendar'], 'gregorian');
      expect(saved['dates'][1]['calendar'], 'chinese_lunar');
      expect(saved['dates'][1]['year'], null);
      expect(saved['dates'][1]['is_leap_month'], true);
      await tap(name);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tap('2月29日');
      await pick(2, 28);
      await tester.tap(find.byKey(const ValueKey('cancel-contact')));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tap('继续编辑');
      await tap('公历生日');
      await tap('纪念日');
      await tap('完成');
      await waitFor(
        () => !model.loading && find.text('编辑').evaluate().isNotEmpty,
      );
      await model.command('close');
      unwrap(
        await model.host.initialize(
          path: '${model.directory.path}/book',
          create: false,
        ),
      );
      final reopened = (await model.get(id))!['data'];
      expect(reopened['family_name'], '张');
      expect(reopened['given_name'], given);
      expect(reopened['middle_name'], '明');
      expect(reopened['dates'][0]['kind'], 'anniversary');
      expect(reopened['dates'][1], saved['dates'][1]);
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await tap(dateText(Map<String, dynamic>.from(saved['dates'][1])));
      expect(find.text('闰月'), findsNothing);
      await pick(0, 2025 - 1901 + 1);
      expect(find.text('选择月份'), findsOneWidget);
      await pick(1, 7);
      await pick(2, 1);
      await tap('完成');
      await waitFor(
        () => !model.loading && find.text('编辑').evaluate().isNotEmpty,
      );
      await model.command('close');
      unwrap(
        await model.host.initialize(
          path: '${model.directory.path}/book',
          create: false,
        ),
      );
      final lunar = (await model.get(id))!['data']['dates'][1];
      expect(lunar['year'], 2025);
      expect(lunar['month'], 6);
      expect(lunar['day'], 1);
      expect(lunar['is_leap_month'], true);
      expect(tester.takeException(), isNull);
    } finally {
      if (id != null) {
        final contact = await model.get(id);
        if (contact != null) await model.delete(contact);
      }
      await model.command('close');
    }
  });
}
