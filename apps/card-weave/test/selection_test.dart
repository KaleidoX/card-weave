import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/design.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Selection remains usable at 320px and 200 percent in $brightness',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        bool selected = false, done = false;
        const label = '包含很长姓名与组织描述的联系人资料';
        await t.pumpWidget(
          CupertinoApp(
            theme: AppTheme(brightness).cupertino,
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 640),
                textScaler: TextScaler.linear(2),
                platformBrightness: brightness,
              ),
              child: StatefulBuilder(
                builder: (context, setState) => AppSelectionPageShell(
                  title: '选择联系人',
                  onDone: () => done = true,
                  body: ListView(
                    children: [
                      AppGroup(
                        children: [
                          AppSelectionRow(
                            title: label,
                            subtitle: '已有资料保留，请选择要加入的联系人',
                            selected: selected,
                            onTap: () => setState(() => selected = !selected),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        expect(t.takeException(), isNull);
        await t.tap(find.text(label));
        await t.pumpAndSettle();
        expect(selected, isTrue);
        await t.tap(find.text('完成'));
        await t.pumpAndSettle();
        expect(done, isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }
}
