import 'dart:async';

import 'package:card_weave/design.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Lazy list loads near end once and stops when exhausted', (
    t,
  ) async {
    var count = 50;
    var enabled = true;
    var requests = 0;
    final pending = Completer<void>();
    late StateSetter update;
    await t.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AppPagination(
              enabled: enabled,
              onLoad: () async {
                requests++;
                await pending.future;
                update(() {
                  count += 10;
                  enabled = false;
                });
              },
              builder: (_, controller) => ListView.builder(
                controller: controller,
                itemCount: count,
                itemBuilder: (_, i) =>
                    SizedBox(height: 60, child: Text('Contact $i')),
              ),
            );
          },
        ),
      ),
    );
    expect(find.text('Contact 49'), findsNothing);
    expect(requests, 0);
    await t.drag(find.byType(ListView), const Offset(0, -2800));
    await t.pumpAndSettle();
    expect(requests, 1);
    await t.drag(find.byType(ListView), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(requests, 1);
    pending.complete();
    await t.pumpAndSettle();
    await t.drag(find.byType(ListView), const Offset(0, -800));
    await t.pumpAndSettle();
    expect(find.text('Contact 59'), findsOneWidget);
    expect(requests, 1);
  });

  testWidgets('Short pages fill viewport; disabled loading waits for retry', (
    t,
  ) async {
    var count = 1;
    var enabled = true;
    var requests = 0;
    late StateSetter update;
    await t.pumpWidget(
      CupertinoApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return AppPagination(
              enabled: enabled,
              onLoad: () async {
                requests++;
                update(() {
                  if (requests == 1) {
                    enabled = false;
                  } else {
                    count += 50;
                  }
                });
              },
              builder: (_, controller) => ListView.builder(
                controller: controller,
                itemCount: count,
                itemBuilder: (_, i) =>
                    SizedBox(height: 60, child: Text('Contact $i')),
              ),
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Contact 0'), findsOneWidget);
    update(() => enabled = true);
    await t.pumpAndSettle();
    expect(requests, 2);
    expect(find.text('Contact 50'), findsNothing);
  });
}
