import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:card_weave/main.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Expanded contact fields survive Android edit, reopen and search',
    (t) async {
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
        fail('Expected app state did not arrive');
      }

      Future<void> tap(String text) async {
        await t.pumpAndSettle();
        final finder = ['新建联系人', '展开姓名细分', '收起姓名细分'].contains(text)
            ? find.bySemanticsLabel(RegExp(text))
            : find.text(text).last;
        await t.ensureVisible(finder);
        await t.pumpAndSettle();
        await t.tap(finder);
        await t.pumpAndSettle();
      }

      Future<void> enter(String label, String value, [int index = 0]) async {
        final f = find.byKey(ValueKey('input-$label')).at(index);
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.enterText(f, value);
        await t.pumpAndSettle();
      }

      Future<void> extra(String label) async {
        await tap('添加更多信息');
        await tap(label);
      }

      await waitFor(() => m.ready && !m.loading);
      if (!m.initialized) {
        await tap('创建本地通讯录');
        await waitFor(() => m.initialized && !m.loading);
      }
      String? id;
      try {
        await tap('新建联系人');
        await extra('昵称');
        await t.tap(find.byKey(const ValueKey('cancel-contact')));
        await t.pumpAndSettle();
        expect(find.text('放弃未保存的修改？'), findsNothing);
        await tap('新建联系人');
        await enter('姓名', 'Alex');
        await tap('展开姓名细分');
        await enter('姓名前缀', 'Dr');
        await enter('姓氏', 'Taylor');
        await enter('中间名', 'Jordan');
        await enter('姓名后缀', 'Jr');
        await tap('收起姓名细分');
        await enter('公司', 'Example Studio');
        await enter('职位', 'Designer');
        await extra('昵称');
        await enter('昵称', 'NicknameFixture');
        await extra('姓名拼音');
        await enter('姓氏拼音', 'Tai');
        await enter('中间名拼音', 'Jo');
        await enter('名字拼音', 'A');
        await extra('地址');
        await enter('地址', 'First address');
        await enter('地址', 'Second address', 1);
        final remove = find.bySemanticsLabel(RegExp('删除地址')).first;
        await t.ensureVisible(remove);
        await t.tap(remove);
        await t.pumpAndSettle();
        await extra('即时消息');
        await enter('即时消息', 'AccountFixture');
        await extra('网站');
        await enter('网站', 'https://example.invalid');
        await extra('关联人');
        await enter('关联人', 'FriendFixture');
        await enter('备注', 'Multiline\nFixture');
        await tap('完成');
        await waitFor(
          () => m.contacts.any(
            (c) => c['data']['display_name'] == 'Dr Alex Jordan Taylor Jr',
          ),
        );
        id = m.contacts.firstWhere(
          (c) => c['data']['display_name'] == 'Dr Alex Jordan Taylor Jr',
        )['id'];
        final saved = object((await m.get(id!))!['data']);
        expect(saved['name_prefix'], 'Dr');
        expect(saved['name_suffix'], 'Jr');
        expect(saved['phonetic_family_name'], 'Tai');
        expect(saved['phonetic_middle_name'], 'Jo');
        expect(saved['phonetic_given_name'], 'A');
        expect(saved['nickname'], 'NicknameFixture');
        expect(saved['job_title'], 'Designer');
        expect(saved['addresses'], [
          {'label': '住宅', 'value': 'Second address'},
        ]);
        expect(saved['instant_messages'], [
          {'label': 'QQ', 'value': 'AccountFixture'},
        ]);
        expect(saved['relations'], [
          {'label': '朋友', 'value': 'FriendFixture'},
        ]);
        expect(saved['website'], 'https://example.invalid');
        await tap('Dr Alex Jordan Taylor Jr');
        await tap('编辑');
        await enter('昵称', 'CanceledNickname');
        await t.tap(find.byKey(const ValueKey('cancel-contact')));
        await t.pumpAndSettle();
        await tap('放弃修改');
        expect((await m.get(id))!['data'], saved);
        await tap('编辑');
        await t.ensureVisible(find.bySemanticsLabel(RegExp('移除网站')));
        await t.tap(find.bySemanticsLabel(RegExp('移除网站')));
        await t.pumpAndSettle();
        await tap('完成');
        await waitFor(
          () => !m.loading && find.text('编辑').evaluate().isNotEmpty,
        );
        expect((await m.get(id))!['data'].containsKey('website'), false);
        await m.command('close');
        unwrap(
          await m.host.initialize(
            path: '${m.directory.path}/book',
            create: false,
          ),
        );
        expect((await m.get(id))!['data'], {...saved}..remove('website'));
        await t.pageBack();
        await t.pumpAndSettle();
        for (final text in [
          'NicknameFixture',
          'Designer',
          'Second address',
          'AccountFixture',
          'FriendFixture',
          'Tai',
          'Jordan',
        ]) {
          await t.enterText(find.byType(CupertinoSearchTextField), text);
          await t.pump(const Duration(milliseconds: 400));
          await waitFor(() => !m.loading);
          expect(m.contacts.map((c) => c['id']), contains(id));
        }
        expect(t.takeException(), isNull);
      } finally {
        if (id != null) {
          final c = await m.get(id);
          if (c != null) await m.delete(c);
        }
        await m.command('close');
      }
    },
  );
}
