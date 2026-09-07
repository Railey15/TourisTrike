import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:touristrike/core/models/emergency_photo.dart';
import 'package:touristrike/core/services/emergency_service.dart';
import 'package:touristrike/widgets/emergency_alert_form.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.red, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(2, 2);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });

  Future<void> open(
    WidgetTester tester,
    SubmitEmergencyAlert submit, {
    Future<XFile?> Function()? picker,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<EmergencyAlertResult>(
                context: context,
                builder: (_) =>
                    EmergencyAlertForm(onSubmit: submit, pickPhoto: picker),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'opening/cancelling confirmation has no submission; note and photo survive',
    (tester) async {
      var submissions = 0;
      await open(tester, (id, note, photo) async {
        submissions++;
        expect(note, 'Please assist at the pickup.');
        expect(photo?.bytes, png);
        return EmergencyAlertResult(
          alertId: id,
          triggeredAt: DateTime.now(),
          emailSent: true,
        );
      }, picker: () async => XFile.fromData(png, name: 'photo.png'));
      await tester.enterText(
        find.byType(TextField),
        'Please assist at the pickup.',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Attach Photo'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Attached photo'), findsOneWidget);
      await tester.tap(find.text('Send Alert'));
      await tester.pumpAndSettle();
      expect(find.text('Send Emergency Alert?'), findsOneWidget);
      expect(submissions, 0);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Please assist at the pickup.'), findsOneWidget);
      expect(find.text('Attached photo'), findsOneWidget);
      expect(submissions, 0);
      await tester.tap(find.text('Send Alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, Send Alert'));
      await tester.pumpAndSettle();
      expect(submissions, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'only final Yes sends; repeated taps cannot duplicate, both dialogs close',
    (tester) async {
      final pending = Completer<EmergencyAlertResult>();
      var submissions = 0;
      await open(tester, (id, note, photo) {
        submissions++;
        expect(note, 'Help');
        expect(photo, isNull);
        return pending.future;
      });
      await tester.enterText(find.byType(TextField), 'Help');
      await tester.tap(find.text('Send Alert'));
      await tester.pumpAndSettle();
      final yes = find.text('Yes, Send Alert');
      await tester.tap(yes);
      await tester.tap(yes);
      await tester.pump();
      expect(submissions, 1);
      expect(find.text('Sending...'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('Sending...'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      pending.complete(
        EmergencyAlertResult(
          alertId: 'saved',
          triggeredAt: DateTime.now(),
          emailSent: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'failed submission preserves form and reuses the alert ID on retry',
    (tester) async {
      final ids = <String>[];
      await open(tester, (id, note, photo) async {
        ids.add(id);
        throw StateError('offline');
      });
      await tester.enterText(find.byType(TextField), 'Keep this note');
      await tester.tap(find.text('Send Alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, Send Alert'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Please retry'), findsOneWidget);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Keep this note'), findsOneWidget);
      await tester.tap(find.text('Send Alert'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, Send Alert'));
      await tester.pumpAndSettle();
      expect(ids, hasLength(2));
      expect(ids[0], ids[1]);
    },
  );

  test('photo validation rejects oversized and non-image files', () async {
    await expectLater(
      EmergencyPhoto.fromFile(
        XFile.fromData(Uint8List(EmergencyPhoto.maxBytes + 1)),
      ),
      throwsFormatException,
    );
    await expectLater(
      EmergencyPhoto.fromFile(
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fake.jpg'),
      ),
      throwsFormatException,
    );
    final photo = await EmergencyPhoto.fromFile(
      XFile.fromData(png, name: 'image.png'),
    );
    expect(photo.extension, 'png');
    expect(photo.toJson()['filename'], 'emergency-photo.png');
  });

  testWidgets(
    'photo permission failure is visible and does not block a photo-free alert',
    (tester) async {
      var submitted = false;
      await open(
        tester,
        (id, note, photo) async {
          expect(photo, isNull);
          submitted = true;
          return EmergencyAlertResult(alertId: id, triggeredAt: DateTime.now());
        },
        picker: () async =>
            throw PlatformException(code: 'photo_access_denied'),
      );
      await tester.tap(find.text('Attach Photo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Check photo permissions'), findsOneWidget);
      await tester.tap(find.text('Send Alert'));
      await tester.pumpAndSettle();
      expect(submitted, isFalse);
      await tester.tap(find.text('Yes, Send Alert'));
      await tester.pumpAndSettle();
      expect(submitted, isTrue);
    },
  );
}
