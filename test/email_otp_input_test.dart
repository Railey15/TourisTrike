import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/widgets/email_otp_input.dart';

void main() {
  test('email masking keeps only a short local prefix and domain', () {
    expect(maskVerificationEmail('yellow@gmail.com'), 'ye••••@gmail.com');
    expect(maskVerificationEmail('a@example.com'), 'a••••@example.com');
  });

  testWidgets('a pasted six digit code fills six separate cells', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) => EmailOtpInput(controller: controller),
      ),
    )));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    for (final digit in '123456'.split('')) {
      expect(find.text(digit), findsOneWidget);
    }
    expect(controller.text, '123456');
  });
}
