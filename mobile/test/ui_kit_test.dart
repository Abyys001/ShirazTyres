import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_driver/core/theme.dart';
import 'package:shiraztyres_driver/widgets/ui_kit.dart';

/// The kit is what stops the two apps drifting apart, so the pieces that carry a
/// decision are checked here rather than only on a device.
void main() {
  Widget host(Widget child, {Brightness brightness = Brightness.dark}) => MaterialApp(
        theme: buildTheme(brightness),
        home: Scaffold(body: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: child,
        ))),
      );

  testWidgets('the issue grid lays six options out two to a row without overflowing',
      (WidgetTester tester) async {
    // The narrowest phone the apps target. A label that wraps out of its tile is
    // the failure this guards against — it is what a drop-down was replacing.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const labels = <String>[
      'Puncture',
      'Blowout',
      'Tyre damage',
      'Wheel change',
      'Locking wheel nut',
      'Something else',
    ];

    var chosen = '';
    await tester.pumpWidget(host(
      StatefulBuilder(
        builder: (context, setState) => ChoiceGrid(
          children: <Widget>[
            for (final label in labels)
              ChoiceTile(
                label: label,
                icon: Icons.tire_repair,
                selected: chosen == label,
                onTap: () => setState(() => chosen = label),
              ),
          ],
        ),
      ),
    ));

    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }

    // Two per row: the six tiles occupy three distinct vertical positions.
    final tops = tester
        .widgetList<ChoiceTile>(find.byType(ChoiceTile))
        .map((tile) => tester.getTopLeft(find.byWidget(tile)).dy)
        .toSet();
    expect(tops.length, 3);

    await tester.tap(find.text('Blowout'));
    await tester.pumpAndSettle();
    expect(chosen, 'Blowout');
  });

  testWidgets('a slide action fires only once dragged most of the way across',
      (WidgetTester tester) async {
    var fired = 0;
    await tester.pumpWidget(host(
      SlideAction(
        label: 'Start driving',
        onConfirm: () async => fired++,
      ),
    ));

    final thumb = find.byIcon(Icons.chevron_right);

    // A nudge is not a commitment — this is the mis-tap the control exists for.
    await tester.drag(thumb, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(fired, 0);

    await tester.drag(thumb, const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(fired, 1);
  });

  testWidgets('an expandable card keeps its detail closed until it is asked for',
      (WidgetTester tester) async {
    await tester.pumpWidget(host(
      const ExpandableCard(
        title: 'Your request',
        child: Text('205/55R16'),
      ),
    ));

    expect(find.text('Your request'), findsOneWidget);
    expect(find.text('205/55R16'), findsNothing);

    await tester.tap(find.text('Your request'));
    await tester.pumpAndSettle();
    expect(find.text('205/55R16'), findsOneWidget);
  });

  testWidgets('the kit takes its colours from the theme, in either brightness',
      (WidgetTester tester) async {
    Future<Color> cardColour(Brightness brightness) async {
      await tester.pumpWidget(host(
        const SurfaceCard(child: Text('Anything')),
        brightness: brightness,
      ));
      // MaterialApp lerps between themes, so read the colour once it lands.
      await tester.pumpAndSettle();
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(SurfaceCard), matching: find.byType(DecoratedBox)).first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    // The same widget, no arguments changed: a card is dark at night and white
    // in daylight because it asks the theme rather than a constant.
    expect(await cardColour(Brightness.dark), Palette.dark.surface);
    expect(await cardColour(Brightness.light), Palette.light.surface);
  });
}
