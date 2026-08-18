import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget table() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(flex: 3, child: Text('Role')),
              Expanded(flex: 1, child: Text('Level')),
            ],
          ),
          Row(
            children: [
              Expanded(flex: 3, child: Text('Admin')),
              Expanded(flex: 1, child: Text('10')),
            ],
          ),
        ],
      );

  testWidgets(
      'bounded maxWidth ConstrainedBox renders in horizontal scroll '
      '(roles/designations tables)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 760,
                  maxWidth:
                      constraints.maxWidth.isFinite && constraints.maxWidth > 760
                          ? constraints.maxWidth
                          : 760,
                ),
                child: table(),
              ),
            );
          },
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'min == max width ConstrainedBox renders in horizontal scroll '
      '(manager_team/attendance_log tables)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            const minWidth = 1040.0;
            final width = constraints.maxWidth > minWidth
                ? constraints.maxWidth
                : minWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: width, maxWidth: width),
                child: table(),
              ),
            );
          },
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SizedBox-width table renders in horizontal scroll',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 800,
            child: table(),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });
}
