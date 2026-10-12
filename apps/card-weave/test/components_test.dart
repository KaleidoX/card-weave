import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:card_weave/ui/gallery.dart';
import 'package:card_weave/ui/theme.dart';

void main() {
  for (final width in [320.0, 360.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('Component catalog $width $brightness at 200 percent', (
        t,
      ) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          CupertinoApp(
            theme: AppTheme(brightness).cupertino,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const AppComponentGallery(),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.tap(find.text('手机'));
        await t.pumpAndSettle();
        await t.tap(find.text('工作'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.drag(find.byType(ListView).first, const Offset(0, -600));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}
