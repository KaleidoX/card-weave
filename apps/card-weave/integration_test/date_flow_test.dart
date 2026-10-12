import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:card_weave/main.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Typed dates save, edit and reopen through Android SQLite', (
    tester,
  ) async {
    await RustLib.init();
    final model = AppModel();
    final name = 'Date fixture ${DateTime.now().microsecondsSinceEpoch}';
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
      final f = find.text(label).last;
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
      final field = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '姓名',
      );
      await tester.enterText(field, name);
      await tap('添加日期');
      await tap('确定');
      await tap('添加日期');
      expect(find.text('农历生日'), findsOneWidget);
      await tester.ensureVisible(find.text('请选择'));
      await tester.drag(find.text('请选择'), const Offset(0, -44));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('正月'));
      await tester.drag(find.text('正月'), const Offset(0, -44));
      await tester.pumpAndSettle();
      await tap('确定');
      await tap('保存');
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
      expect(saved['dates'].length, 2);
      expect(saved['dates'][0]['kind'], 'birthday');
      expect(saved['dates'][0]['calendar'], 'gregorian');
      expect(saved['dates'][1]['calendar'], 'chinese_lunar');
      expect(saved['dates'][1]['year'], null);
      expect(saved['dates'][1]['is_leap_month'], true);
      await tap(name);
      await tester.tap(find.byTooltip('编辑联系人'));
      await tester.pumpAndSettle();
      await tap('公历生日 ▾');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('放弃未保存的修改？'), findsOneWidget);
      await tap('继续编辑');
      await tap('公历生日');
      await tap('纪念日');
      await tap('确定');
      await tap('保存');
      await waitFor(() => !model.loading);
      await model.command('close');
      unwrap(
        await model.host.initialize(
          path: '${model.directory.path}/book',
          create: false,
        ),
      );
      final reopened = (await model.get(id))!['data'];
      expect(reopened['dates'][0]['kind'], 'anniversary');
      expect(reopened['dates'][1], saved['dates'][1]);
      await tester.tap(find.byTooltip('编辑联系人'));
      await tester.pumpAndSettle();
      await tap('农历生日 ▾');
      expect(find.text('闰月'), findsNothing);
      await tap('不指定年份');
      await waitFor(
        () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
      );
      final current = DateTime.now().year.clamp(1901, 2100);
      for (var y = current; y != 2025; y += y > 2025 ? -1 : 1) {
        await tester.ensureVisible(find.text('$y 年'));
        await tester.drag(find.text('$y 年'), Offset(0, y > 2025 ? 44 : -44));
        await tester.pumpAndSettle();
      }
      expect(find.text('选择月份'), findsOneWidget);
      for (var step = 0; step < 7; step++) {
        final monthWheel = find.byType(CupertinoPicker).at(1);
        await tester.ensureVisible(monthWheel);
        await tester.drag(monthWheel, const Offset(0, -44));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('请选择'));
      await tester.drag(find.text('请选择'), const Offset(0, -44));
      await tester.pumpAndSettle();
      await tap('确定');
      await tap('保存');
      await waitFor(() => !model.loading);
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
