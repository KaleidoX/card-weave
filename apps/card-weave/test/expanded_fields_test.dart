import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/contacts/extra_fields.dart';
import 'package:card_weave/contacts/contact_content.dart';
import 'package:card_weave/contacts/fields.dart';
import 'package:card_weave/contacts/name_group.dart';
import 'package:card_weave/design.dart';
import 'package:card_weave/contacts/values_group.dart';
import 'package:card_weave/contacts/value_kind.dart';

void main() {
  testWidgets(
    'Empty address and relation rows stay compact and address grows with input',
    (t) async {
      t.view.physicalSize = const Size(430, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var selected = false;
      await t.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final kind in [
                    ContactValueKind.address,
                    ContactValueKind.relation,
                  ])
                    ContactValuesGroup(
                      key: ValueKey(kind),
                      initial: const [],
                      kind: kind,
                      selectContact: kind == ContactValueKind.relation
                          ? () async {
                              selected = true;
                              return null;
                            }
                          : null,
                      onChanged: (_) {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final kind in [
        ContactValueKind.address,
        ContactValueKind.relation,
      ]) {
        expect(
          t.getSize(find.byKey(ValueKey(kind))).height,
          lessThanOrEqualTo(60),
        );
      }
      await t.tap(find.bySemanticsLabel('选择联系人'));
      await t.pumpAndSettle();
      expect(selected, isTrue);
      final labelTop = t.getTopLeft(find.text('住宅').first).dy;
      double baseline(RenderBox box) =>
          box.localToGlobal(Offset.zero).dy +
          box.getDryBaseline(
            BoxConstraints.tight(box.size),
            TextBaseline.alphabetic,
          )!;
      final labelBox = t.renderObject<RenderBox>(find.text('住宅').first);
      final inputBox = t
          .state<EditableTextState>(
            find.descendant(
              of: find.byKey(const ValueKey('input-地址')).first,
              matching: find.byType(EditableText),
            ),
          )
          .renderEditable;
      expect(baseline(inputBox), closeTo(baseline(labelBox), 1));
      final divider = find.byKey(const ValueKey('field-label-divider')).first;
      final dividerBefore = t.getRect(divider);
      await t.enterText(
        find.byKey(const ValueKey('input-地址')).first,
        '第一行\n第二行\n第三行',
      );
      await t.pumpAndSettle();
      expect(
        t.getSize(find.byKey(const ValueKey('input-地址')).first).height,
        greaterThan(50),
      );
      expect(t.getTopLeft(find.text('住宅').first).dy, labelTop);
      expect(baseline(inputBox), closeTo(baseline(labelBox), 1));
      expect(t.getRect(divider).top, dividerBefore.top);
      expect(t.getRect(divider).height, greaterThan(dividerBefore.height));
      await t.enterText(find.byKey(const ValueKey('input-地址')).first, '短地址');
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('住宅').first).dy, labelTop);
      expect(baseline(inputBox), closeTo(baseline(labelBox), 1));
      expect(t.getRect(divider).height, dividerBefore.height);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'More information expands all fields without changing the draft',
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
                child: AppSectionList(
                  children: [
                    const AppGroup(
                      key: ValueKey('notes-card'),
                      children: [Text('备注')],
                    ),
                    ContactExtraFields(
                      key: const ValueKey('extra-section'),
                      data: data,
                      onChanged: (k, v) {
                        data[k] = v;
                        events.add(k);
                      },
                    ),
                  ],
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

      double extraGap() =>
          t.getTopLeft(find.byKey(const ValueKey('extra-section'))).dy -
          t.getBottomLeft(find.byKey(const ValueKey('notes-card'))).dy;
      expect(extraGap(), 20);
      await tap('更多信息');
      expect(extraGap(), 20);
      final first = find.byKey(const ValueKey('extra-nickname'));
      final second = find.byKey(const ValueKey('extra-phonetic'));
      expect(t.getTopLeft(second).dy - t.getBottomLeft(first).dy, 20);
      for (final label in ['昵称', '姓氏拼音', '地址', '即时消息', '网站', '关联人']) {
        expect(find.byKey(ValueKey('input-$label')), findsOneWidget);
      }
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
      await t.enterText(input, '');
      await t.pumpAndSettle();
      expect(contactDocument(data).containsKey('nickname'), false);
      expect(find.byKey(const ValueKey('input-昵称')), findsOneWidget);
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
