import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/main.dart';

void main() {
  testWidgets('renders TourisTrike loading screen', (tester) async {
    await tester.pumpWidget(const TourisTrikeApp());

    expect(find.text('TourisTrike'), findsOneWidget);
  });
}
