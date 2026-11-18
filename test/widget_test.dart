import 'package:flutter_test/flutter_test.dart';
import 'package:rcz_kanyama/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first launch asks for the member name', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(RczKanyamaApp(preferences: preferences));

    expect(find.text('Welcome home'), findsOneWidget);
    expect(
      find.text('Tell us how you would like to be greeted.'),
      findsOneWidget,
    );
    expect(find.text('Your name'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}
