import 'package:butterfly/helpers/eink.dart';
import 'package:butterfly/views/toolbar/color.dart';
import 'package:butterfly/widgets/color_field.dart';
import 'package:butterfly/widgets/number_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_leap/material_leap.dart';

void main() {
  tearDown(() => EinkDisplay.enabled = false);

  testWidgets('Magic Pie hides a color property field', (tester) async {
    EinkDisplay.enabled = true;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ColorField(title: Text('Ink color'))),
      ),
    );

    expect(find.text('Ink color'), findsNothing);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('normal devices keep a color property field', (tester) async {
    EinkDisplay.enabled = false;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ColorField(title: Text('Ink color'))),
      ),
    );

    expect(find.text('Ink color'), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('Magic Pie toolbar keeps actions and line width', (tester) async {
    EinkDisplay.enabled = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height: 64,
            child: ColorToolbarView(
              color: SRGBColor.black,
              onChanged: (_) {},
              strokeWidth: 2,
              onStrokeWidthChanged: (_) {},
              actions: const [
                IconButton(onPressed: null, icon: Icon(Icons.undo)),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byType(NumberInput), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
