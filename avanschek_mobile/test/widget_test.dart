import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:avanschek_mobile/main.dart';

void main() {
  setUpAll(() {
    // Initialize dotenv for tests without loading a file
    dotenv.testLoad(mergeWith: {
      'API_BASE_URL': 'http://127.0.0.1:5000',
    });
  });

  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const AvanschekApp());
    await tester.pumpAndSettle();

    // Verify that the app bar title is present.
    expect(find.text('Авансовый отчёт'), findsOneWidget);

    // Verify that the generate button is present.
    expect(find.text('Сгенерировать документы'), findsOneWidget);
  });
}
