import 'package:card_weave/contacts/value_kind.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/contacts/name_group.dart';
import 'package:card_weave/contacts/values_group.dart';

void main() {
  testWidgets(
    'Name disclosure does not edit the draft; changes compose the name',
    (t) async {
      Map<String, String>? changed;
      await t.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ContactNameGroup(
              data: const {'display_name': '张明'},
              onChanged: (v) => changed = v,
            ),
          ),
        ),
      );
      await t.tap(find.bySemanticsLabel(RegExp('展开姓名细分')));
      await t.pumpAndSettle();
      expect(changed, isNull);
      await t.enterText(find.byKey(const ValueKey('input-姓氏')), '张');
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('input-名字')), '三');
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('input-中间名')), '明');
      await t.pumpAndSettle();
      expect(changed!['display_name'], '张明三');
      expect(find.text('使用新姓名'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Phone trailing empty rows are not saved and deletion preserves remaining input',
    (t) async {
      List<Map<String, String>>? changed;
      await t.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ContactValuesGroup(
              initial: const [],
              kind: ContactValueKind.phone,
              onChanged: (v) => changed = v,
            ),
          ),
        ),
      );
      final fields = find.byKey(const ValueKey('input-电话'));
      expect(fields, findsOneWidget);
      await t.enterText(fields.first, '123');
      await t.pumpAndSettle();
      expect(fields, findsNWidgets(2));
      expect(changed!.map((v) => v['value']), ['123']);
      await t.enterText(fields.last, '456');
      await t.pumpAndSettle();
      expect(fields, findsNWidgets(3));
      await t.tap(find.bySemanticsLabel(RegExp('删除电话')).first);
      await t.pumpAndSettle();
      expect(changed!.map((v) => v['value']), ['456']);
      expect(find.text('456'), findsOneWidget);
      expect(fields, findsNWidgets(2));
      expect(t.takeException(), isNull);
    },
  );
}
