import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:card_weave/main.dart';
import 'package:card_weave/model.dart';
import 'package:card_weave/src/rust/api.dart';
import 'package:card_weave/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android contacts, HTTPS sync, stale draft and explicit conflict resolution',
    (tester) async {
      await RustLib.init();
      final model = AppModel();
      await tester.pumpWidget(CardWeaveApp(model: model));
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (condition()) {
            await tester.pumpAndSettle();
            return;
          }
        }
        fail('Timed out waiting for expected UI state');
      }

      Future<void> tap(String text) async {
        final f = find.text(text).last;
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      Future<void> enter(String label, String value) async {
        final f = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        );
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.enterText(f, value);
        await tester.pump();
      }

      await waitFor(() => model.ready);
      const reopen = bool.fromEnvironment('REOPEN');
      if (reopen) {
        await waitFor(() => model.initialized && !model.loading);
        expect(model.contacts.single['data']['display_name'], '最终联系人');
        expect(model.config['endpoint'], 'https://127.0.0.1:18941');
        expect(model.credentials['password'], 'synthetic-test-only');
        await tap('同步');
        await tap('立即同步');
        await waitFor(() => !model.syncing);
        expect(model.status['pending_outbox'], 0);
        expect(model.conflicts, isEmpty);
        await tap('通讯录');
        await tap('新建联系人');
        await enter('姓名', '待删除的验证联系人');
        await tap('添加日期');
        await tap('公历生日');
        await tap('农历生日');
        await tester.ensureVisible(find.text('请选择'));
        await tester.drag(find.text('请选择'), const Offset(0, -44));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(CupertinoPicker).first);
        await tester.drag(
          find.byType(CupertinoPicker).first,
          const Offset(0, -44),
        );
        await tester.pumpAndSettle();
        await tap('确定');
        await tap('保存');
        await waitFor(() => model.contacts.length == 2);
        final lunar = model.contacts
            .firstWhere(
              (c) => c['data']['display_name'] == '待删除的验证联系人',
            )['data']['dates']
            .single;
        expect(lunar['calendar'], 'chinese_lunar');
        expect(lunar['year'], isNull);
        expect(lunar['is_leap_month'], true);
        final search = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.hintText == '搜索姓名、电话、邮箱或备注',
        );
        await tester.enterText(search, '待删除');
        await tester.pump(const Duration(milliseconds: 400));
        await waitFor(() => !model.loading && model.contacts.length == 1);
        await tap('待删除的验证联系人');
        await tap('删除联系人');
        await tap('确认删除');
        await waitFor(() => model.contacts.isEmpty);
        await tester.tap(find.byTooltip('清除搜索'));
        await tester.pumpAndSettle();
        await waitFor(() => model.contacts.length == 1);
        expect(model.contacts.single['data']['display_name'], '最终联系人');
        expect(tester.takeException(), isNull);
        return;
      }
      expect(find.text('创建本地通讯录'), findsOneWidget);
      await tap('创建本地通讯录');
      await waitFor(() => model.initialized && !model.loading);
      await tap('新建联系人');
      await tap('保存');
      expect(find.text('请填写姓名'), findsOneWidget);
      await enter('姓名', '测试联系人 🌿');
      await enter('组织', 'CardWeave 验证');
      await tap('添加电话');
      await enter('电话', '13800138000');
      await tap('添加邮箱');
      await enter('邮箱', 'fixture@example.invalid');
      await tap('添加日期');
      await tap('确定');
      await tap('保存');
      await waitFor(() => model.contacts.length == 1);
      expect(
        model.contacts.single['data']['phones'][0]['value'],
        '13800138000',
      );
      final id = model.contacts.single['id'] as String;
      await tap('设置');
      await enter('HTTPS 服务地址', 'https://127.0.0.1:18941');
      await enter('用户名', 'm0-fixture');
      await enter('密码', 'synthetic-test-only');
      await tester.ensureVisible(find.text('记住凭据'));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tap('保存同步配置');
      await waitFor(() => model.config.isNotEmpty);
      expect(
        await File('${model.directory.path}/sync.json').readAsString(),
        isNot(contains('synthetic-test-only')),
      );
      await tap('同步');
      await tap('立即同步');
      await waitFor(() => !model.syncing);
      expect(model.status['pending_outbox'], 0, reason: model.syncMessage);
      final peer = AppHost();
      final peerPath = '${model.directory.path}/acceptance-peer';
      unwrap(
        await peer.initialize(
          path: peerPath,
          create: true,
          dataset: model.identity['dataset'],
        ),
      );
      Future<dynamic> command(
        String action, [
        Map<String, dynamic> args = const {},
      ]) async => unwrap(
        await peer.execute(request: jsonEncode({'action': action, ...args})),
      );
      Future<void> peerSync() async {
        expect(peer.beginSync(), isTrue);
        unwrap(
          await peer.synchronize(
            configuration: jsonEncode({
              ...publicBackend(model.config),
              ...model.credentials,
            }),
          ),
        );
      }

      await peerSync();
      var second = object(await command('get', {'id': id}));
      expect(second['data']['display_name'], '测试联系人 🌿');
      // A visible editor remains open while another device updates the saved document.
      await tap('通讯录');
      await tap('测试联系人 🌿');
      await tester.tap(find.byTooltip('编辑联系人'));
      await tester.pumpAndSettle();
      await enter('姓名', '未提交草稿');
      var data = object(second['data']);
      data['display_name'] = '另一设备修改';
      await command('save', {
        'id': id,
        'expected': second['data'],
        'contact': data,
      });
      await peerSync();
      await model.synchronize();
      await tester.pumpAndSettle();
      await tap('保存');
      await waitFor(() => find.textContaining('草稿已保留').evaluate().isNotEmpty);
      expect((await model.get(id))!['data']['display_name'], '另一设备修改');
      expect(find.text('未提交草稿'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tap('放弃修改');
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Two disconnected replicas now edit versus delete the same contact.
      await tap('另一设备修改');
      await tester.tap(find.byTooltip('编辑联系人'));
      await tester.pumpAndSettle();
      await enter('姓名', '最终联系人');
      await tap('保存');
      await waitFor(
        () => model.contacts.single['data']['display_name'] == '最终联系人',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      second = object(await command('get', {'id': id}));
      await command('delete', {'id': id, 'expected': second['data']});
      await peerSync();
      await tap('同步');
      await tap('立即同步');
      await waitFor(() => !model.syncing);
      expect(model.conflicts.length, 1);
      await tap('1 位联系人需要处理冲突');
      await tap('最终联系人');
      expect(find.text('删除版本'), findsOneWidget);
      await tap('采用此版本');
      await tap('确认采用');
      await waitFor(() => model.conflicts.isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap('立即同步');
      await waitFor(() => !model.syncing);
      await peerSync();
      expect(
        (await command('get', {'id': id}))['data']['display_name'],
        '最终联系人',
      );
      expect(await command('conflicts'), isEmpty);
      expect(model.status['pending_outbox'], 0);
      await command('close');
      await Directory(peerPath).delete(recursive: true);
      await tap('通讯录');
      expect(find.text('最终联系人'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
