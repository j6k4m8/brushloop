import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:brushloop_app/src/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('app renders BrushLoop auth shell', (WidgetTester tester) async {
    await tester.pumpWidget(const BrushLoopApp());
    await tester.pumpAndSettle();

    expect(find.text('BRUSHLOOP'), findsOneWidget);
    expect(find.text('Sign in to your studio'), findsOneWidget);
  });
}
