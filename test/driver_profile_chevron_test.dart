import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';

void main() {
  testWidgets('driver profile rows keep chevrons aligned on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var onlineTapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DriverSectionCard(
                  title: 'Account',
                  children: [
                    DriverSettingsTile(
                      key: const Key('personal-row'),
                      icon: Icons.person_outline_rounded,
                      title: 'Personal Info',
                      subtitle:
                          'A deliberately long subtitle that wraps safely without moving the chevron',
                      showDivider: false,
                      onTap: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                DriverSectionCard(
                  title: 'Vehicle & Status',
                  children: [
                    DriverSettingsTile(
                      key: const Key('plate-row'),
                      icon: Icons.directions_bike_outlined,
                      title: 'Plate Number',
                      trailingText: 'ABC-1234-LONG',
                      onTap: () {},
                    ),
                    DriverSettingsTile(
                      key: const Key('online-row'),
                      icon: Icons.circle_outlined,
                      title: 'Online Status',
                      trailingText: 'Online',
                      trailingColor: const Color(0xFF16A34A),
                      showDivider: false,
                      onTap: () => onlineTapped = true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final chevrons = find.byIcon(Icons.chevron_right_rounded);
    expect(chevrons, findsNWidgets(3));
    final xPositions = List<double>.generate(
      3,
      (index) => tester.getCenter(chevrons.at(index)).dx,
    );
    expect(xPositions.toSet(), hasLength(1));
    expect(tester.widget<Icon>(chevrons.first).size, 21);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('online-row')));
    expect(onlineTapped, isTrue);
  });
}
