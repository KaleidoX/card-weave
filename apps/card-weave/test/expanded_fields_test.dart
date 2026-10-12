import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/contacts/extra_fields.dart';
import 'package:card_weave/contacts/contact_content.dart';
import 'package:card_weave/contacts/fields.dart';
import 'package:card_weave/contacts/name_group.dart';
import 'package:card_weave/ui/theme.dart';

void main() {
  testWidgets(
    'Optional fields stay out of the draft until input and can be removed',
    (t) async {
      final data = <String, dynamic>{'display_name': 'Fixture'};
      final events = <String>[];
      final form = GlobalKey<FormState>();
      await t.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: ContactExtraFields(
                  data: data,
                  onChanged: (k, v) {
                    data[k] = v;
                    events.add(k);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String label) async {
        final f = find.text(label).last;
        await t.ensureVisible(f);
        await t.tap(f);
        await t.pumpAndSettle();
      }

      await tap('添加更多信息');
      await tap('昵称');
      expect(events, isEmpty);
      final input = find.byKey(const ValueKey('input-昵称'));
      await t.enterText(input, '汉' * 342);
      await t.pumpAndSettle();
      expect(form.currentState!.validate(), false);
      await t.pumpAndSettle();
      expect(find.text('内容过长，最多 1024 字节'), findsOneWidget);
      await t.enterText(input, 'Nickname');
      await t.pumpAndSettle();
      expect(form.currentState!.validate(), true);
      await t.tap(find.bySemanticsLabel(RegExp('移除昵称')));
      await t.pumpAndSettle();
      expect(contactDocument(data).containsKey('nickname'), false);
      expect(find.byKey(const ValueKey('input-昵称')), findsNothing);
    },
  );
  testWidgets(
    'Affixes preserve name order and custom display requires confirmation',
    (t) async {
      Map<String, String>? result;
      bool pending = false;
      await t.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: SingleChildScrollView(
              child: ContactNameGroup(
                data: const {
                  'display_name': 'Custom Display',
                  'given_name': 'Alex',
                  'family_name': 'Taylor',
                },
                onChanged: (v) => result = v,
                onPendingChanged: (v) => pending = v,
              ),
            ),
          ),
        ),
      );
      await t.tap(find.bySemanticsLabel(RegExp('展开姓名细分')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('input-姓名前缀')), 'Dr');
      await t.pumpAndSettle();
      expect(pending, true);
      expect(result, isNull);
      await t.tap(find.text('使用新姓名'));
      await t.pumpAndSettle();
      expect(result!['display_name'], 'Dr Alex Taylor');
      expect(pending, false);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'Expanded detail and comparison at 320px, 200 percent, $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final data = <String, dynamic>{
          for (final k in contactFieldLabels.keys) k: '资料-$k',
          for (final k in [
            'phones',
            'emails',
            'addresses',
            'instant_messages',
            'relations',
          ])
            k: [
              {'label': '较长的自定义标签', 'value': '测试资料值'},
            ],
          'dates': <dynamic>[],
        };
        await t.pumpWidget(
          CupertinoApp(
            theme: AppTheme(brightness).cupertino,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: CupertinoPageScaffold(
              child: SingleChildScrollView(
                child: ContactContent(
                  data,
                  differences: {
                    'nickname',
                    'job_title',
                    'addresses',
                    'instant_messages',
                    'relations',
                  },
                  grouped: false,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        for (final key in [
          'name_prefix',
          'name_suffix',
          'phonetic_family_name',
          'phonetic_middle_name',
          'phonetic_given_name',
          'nickname',
          'job_title',
          'website',
        ]) {
          final f = find.text('资料-$key');
          await t.ensureVisible(f);
          await t.pumpAndSettle();
          expect(f, findsOneWidget);
          expect(t.takeException(), isNull);
        }
        for (final title in ['地址', '即时消息', '关联人']) {
          expect(find.text(title), findsOneWidget);
        }
      },
    );
  }
}
