import 'package:card_weave/contacts/directory_page.dart';
import 'package:card_weave/contacts/search_page.dart';
import 'package:card_weave/design.dart';
import 'package:card_weave/model.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

class DirectoryFixture extends AppModel {
  final offsets = <int>[];
  @override
  Future<dynamic> command(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    if (action == 'directory') {
      final offset = args['offset'] as int;
      offsets.add(offset);
      return {
        'revision': 1,
        'total': 1001,
        'sections': [
          {'initial': 'A', 'offset': 0, 'count': 1000},
          {'initial': 'Z', 'offset': 1000, 'count': 1},
        ],
        'entries': List.generate(
          offset == 1000 ? 1 : 50,
          (i) => {
            'id': '${offset + i}',
            'display_name': offset == 1000 ? '张先生' : 'Alice ${offset + i}',
            'subtitle': '123456789',
            'has_conflict': false,
          },
        ),
      };
    }
    if (action == 'list') {
      return List.generate(
        50,
        (i) => {
          'id': '$i',
          'has_conflict': false,
          'data': {
            'display_name': '${args['search']} $i',
            'phones': [],
            'emails': [],
            'organization': '',
          },
        },
      );
    }
    throw StateError(action);
  }
}

void main() {
  for (final factor in [1.0, 2.0]) {
    testWidgets('Index jumps beyond loaded pages at text scale $factor', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final m = DirectoryFixture();
      await m.load(reset: true);
      String? opened;
      await t.pumpWidget(
        CupertinoApp(
          theme: const AppTheme(Brightness.light).cupertino,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(320, 640),
              textScaler: TextScaler.linear(factor),
            ),
            child: AppPage(
              safeTop: false,
              body: ListenableBuilder(
                listenable: m,
                builder: (_, _) => ContactDirectoryPage(
                  model: m,
                  onCreate: () {},
                  onOpen: (id) async {
                    opened = id;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Alice 0'), findsOneWidget);
      expect(find.text('Alice 999'), findsNothing);
      await t.tap(find.bySemanticsLabel('跳转到 Z'));
      await t.pumpAndSettle();
      expect(find.text('张先生'), findsOneWidget);
      expect(m.offsets, contains(1000));
      expect(m.offsets.length, lessThan(6));
      await t.tap(find.text('张先生'));
      expect(opened, '1000');
      expect(t.takeException(), isNull);
      await t.tap(find.bySemanticsLabel('跳转到 A'));
      await t.pumpAndSettle();
      expect(find.text('Alice 0'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Search field stays visible while results scroll; clearing resets results',
    (t) async {
      final m = DirectoryFixture();
      await t.pumpWidget(
        CupertinoApp(
          home: ContactSearchPage(
            model: m,
            groupTitle: '联系人',
            onOpen: (_) async {},
          ),
        ),
      );
      await t.enterText(find.byType(CupertinoSearchTextField), 'Alice');
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.text('Alice 0'), findsOneWidget);
      await t.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await t.pumpAndSettle();
      expect(
        find.byType(CupertinoSearchTextField).hitTestable(),
        findsOneWidget,
      );
      await t.enterText(find.byType(CupertinoSearchTextField), '');
      await t.pumpAndSettle();
      expect(find.text('搜索联系人'), findsNWidgets(2));
      expect(find.text('Alice 0'), findsNothing);
    },
  );
}
