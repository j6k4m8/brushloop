import 'package:flutter_test/flutter_test.dart';

import 'package:brushloop_app/src/app.dart';

void main() {
  testWidgets('app renders BrushLoop auth shell', (WidgetTester tester) async {
    await tester.pumpWidget(const BrushLoopApp());

    expect(find.text('BRUSHLOOP'), findsOneWidget);
    expect(find.text('Sign in to your studio'), findsOneWidget);
  });
}
