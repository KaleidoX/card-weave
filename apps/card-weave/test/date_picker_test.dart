import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/contacts/dates_group.dart';

Future<Map<String, dynamic>> fixtureOptions(String calendar, int? year) async =>
    {
      'min_year': calendar == 'gregorian' ? 1 : 1901,
      'max_year': calendar == 'gregorian' ? 9999 : 2100,
      'year_specific': year != null,
      'months': [
        for (var m = 1; m <= 12; m++) ...[
          {
            'month': m,
            'is_leap_month': false,
            'days': calendar == 'gregorian' && m == 2
                ? (year == 2023 ? 28 : 29)
                : 30,
          },
          if (calendar == 'chinese_lunar' &&
              (year == null || (year == 2025 && m == 6)))
            {'month': m, 'is_leap_month': true, 'days': year == null ? 30 : 29},
        ],
      ],
    };

void main() {
  final birthday = <String, dynamic>{
    'kind': 'birthday',
    'label': '',
    'calendar': 'gregorian',
    'year': 2024,
    'month': 2,
    'day': 29,
    'is_leap_month': false,
  };
  Future<void> open(
    WidgetTester tester,
    List<dynamic> initial,
    ValueChanged<List<dynamic>> changed, {
    CalendarOptionsProvider options = fixtureOptions,
  }) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setState) => ContactDatesEditor(
                dates: initial,
                options: options,
                onChanged: (v) {
                  setState(() {
                    initial = v;
                  });
                  changed(v);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label).last);
    await t.tap(find.text(label).last);
    await t.pumpAndSettle();
  }

  testWidgets(
    'Typed birthdays remain distinct and unfinished additions preserve source',
    (t) async {
      List<dynamic>? result;
      await open(t, [birthday], (v) => result = v);
      await tap(t, '添加日期');
      expect(find.text('农历生日'), findsOneWidget);
      await t.ensureVisible(find.text('选择月份'));
      await t.drag(find.text('选择月份'), const Offset(0, -88));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('请选择'));
      await t.drag(find.text('请选择'), const Offset(0, -44));
      await t.pumpAndSettle();
      expect(result!.length, 2);
      expect(result![1]['kind'], 'birthday');
      expect(result![1]['calendar'], 'chinese_lunar');
      expect(result![1]['year'], null);
      expect(result![1]['is_leap_month'], true);
      await tap(t, '添加日期');
      expect(find.text('纪念日'), findsOneWidget);
      expect(result!.length, 2);
      expect(result![0], birthday);
    },
  );
  testWidgets('Changing leap year requires an explicit valid day', (t) async {
    List<dynamic>? result;
    await open(t, [birthday], (v) => result = v);
    await tap(t, '2024年2月29日');
    await t.drag(find.text('2024'), const Offset(0, 44));
    await t.pumpAndSettle();
    expect(find.text('请选择有效月份和日期'), findsOneWidget);
    await t.drag(find.text('请选择'), const Offset(0, -44));
    await t.pumpAndSettle();
    expect(result!.single['year'], 2023);
    expect(result!.single['day'], 1);
    expect(birthday['day'], 29);
  });
  testWidgets(
    'Unknown-year date and custom label survive narrow large-text editing',
    (t) async {
      t.view.physicalSize = const Size(432, 900);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      List<dynamic>? result;
      await open(t, [
        {...birthday, 'year': null},
      ], (v) => result = v);
      await tap(t, '公历生日');
      await tap(t, '自定义');
      await t.enterText(find.byType(CupertinoTextField), '相识日');
      await t.pumpAndSettle();
      await tap(t, '完成');
      expect(result!.single, {
        ...birthday,
        'year': null,
        'kind': 'custom',
        'label': '相识日',
      });
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'A leap month absent in the newly selected year requires reselection',
    (t) async {
      final original = {
        ...birthday,
        'calendar': 'chinese_lunar',
        'year': 2025,
        'month': 6,
        'day': 29,
        'is_leap_month': true,
      };
      List<dynamic>? result;
      await open(t, [original], (v) => result = v);
      await tap(t, '2025年闰六月廿九');
      expect(find.text('闰月'), findsNothing);
      await t.drag(find.text('2025'), const Offset(0, 44));
      await t.pumpAndSettle();
      expect(find.text('选择月份'), findsOneWidget);
      expect(find.text('请选择有效月份和日期'), findsOneWidget);
      expect(result!.single, original);
      expect(original['is_leap_month'], true);
    },
  );

  testWidgets('Calendar failure blocks confirmation and retry recovers', (
    t,
  ) async {
    var failure = true;
    List<dynamic>? result;
    await open(
      t,
      [birthday],
      (v) => result = v,
      options: (c, y) async {
        if (failure) throw StateError('fixture unavailable');
        return fixtureOptions(c, y);
      },
    );
    await tap(t, '2024年2月29日');
    expect(find.text('无法获取日历，请重试。'), findsOneWidget);
    failure = false;
    await tap(t, '重试');
    expect(result!.single, birthday);
  });

  testWidgets('Late calendar responses cannot replace a newer year selection', (
    t,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    List<dynamic>? result;
    await open(
      t,
      [birthday],
      (v) => result = v,
      options: (c, y) => y == 2023 ? old.future : fixtureOptions(c, y),
    );
    await tap(t, '2024年2月29日');
    await t.drag(find.text('2024'), const Offset(0, 44));
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await t.drag(find.text('2023'), const Offset(0, -44));
    await t.pumpAndSettle();
    old.complete(await fixtureOptions('gregorian', 2023));
    await t.pumpAndSettle();
    expect(result!.single, birthday);
  });
}
