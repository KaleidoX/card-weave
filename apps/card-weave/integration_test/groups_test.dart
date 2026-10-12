import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:card_weave/main.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android groups and linked contacts preserve user choices', (
    t,
  ) async {
    await RustLib.init();
    final m = AppModel();
    await t.pumpWidget(CardWeaveApp(model: m));
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 150; i++) {
        await t.pump(const Duration(milliseconds: 200));
        if (condition()) {
          await t.pumpAndSettle();
          return;
        }
      }
      fail('app state timeout');
    }

    Future<void> tap(String text) async {
      await waitFor(() => find.text(text).evaluate().isNotEmpty);
      final f = find.text(text).last;
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await waitFor(() => m.ready && !m.loading);
    if (!m.initialized) {
      await tap('创建本地通讯录');
      await waitFor(() => m.initialized && !m.loading);
    }
    final a = object(
      await m.command('create', {
        'contact': {...emptyContact(), 'display_name': 'Alpha fixture'},
      }),
    );
    final b = object(
      await m.command('create', {
        'contact': {...emptyContact(), 'display_name': 'Beta fixture'},
      }),
    );
    await m.refresh();
    await t.pumpAndSettle();
    try {
      await tap('列表');
      await tap('新建群组');
      await t.enterText(
        find.byType(CupertinoTextField).last,
        'Friends fixture',
      );
      await t.pumpAndSettle();
      await tap('完成');
      await waitFor(
        () => find.byIcon(CupertinoIcons.ellipsis_circle).evaluate().isNotEmpty,
      );
      final manage = find.byIcon(CupertinoIcons.ellipsis_circle);
      await t.tap(manage);
      await t.pumpAndSettle();
      await tap('管理成员');
      await tap('Alpha fixture');
      await tap('Beta fixture');
      await tap('完成');
      final groups = await m.groups({'operation': 'list'}) as List;
      expect(groups.single['count'], 2);
      await waitFor(() => find.text('管理成员').evaluate().isNotEmpty);
      Navigator.of(t.element(find.text('管理成员'))).pop();
      await t.pumpAndSettle();
      await tap('Friends fixture');
      await t.pumpAndSettle();
      expect(m.contacts.length, 2);
      await tap('Alpha fixture');
      await tap('群组');
      await tap('Friends fixture');
      await tap('取消');
      expect(
        (await m.groups({
          'operation': 'contact_groups',
          'id': a['id'],
        }) as List).single['state'],
        'joined',
      );
      await tap('编辑');
      await tap('更多信息');
      await t.ensureVisible(find.bySemanticsLabel('选择联系人').last);
      await t.tap(find.bySemanticsLabel('选择联系人').last);
      await t.pumpAndSettle();
      await tap('Beta fixture');
      await tap('完成');
      await waitFor(() => find.text('编辑').evaluate().isNotEmpty);
      final linked = await m.get(a['id'] as String);
      expect(linked!['data']['relations'][0]['target_contact_id'], b['id']);
      await tap('编辑');
      await tap('Beta fixture');
      await tap('改为手动填写');
      await tap('取消');
      // Existing unsaved-changes confirmation retains persisted binding.
      if (find.text('放弃修改').evaluate().isNotEmpty) await tap('放弃修改');
      expect(
        (await m.get(
          a['id'] as String,
        ))!['data']['relations'][0]['target_contact_id'],
        b['id'],
      );
      await tap('编辑');
      await t.ensureVisible(find.bySemanticsLabel('选择联系人').last);
      await t.tap(find.bySemanticsLabel('选择联系人').last);
      await t.pumpAndSettle();
      await tap('Beta fixture');
      expect(find.text('已添加此关联'), findsOneWidget);
      await tap('知道了');
      await tap('取消');
      expect((await m.get(a['id'] as String))!['data']['relations'].length, 1);
      expect(t.takeException(), isNull);
    } finally {
      await m.command('close');
    }
  });
}
