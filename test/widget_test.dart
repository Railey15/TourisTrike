import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/maintenance/maintenance_service.dart';
import 'package:touristrike/core/maintenance/maintenance_settings.dart';
import 'package:touristrike/main.dart';

void main() {
  testWidgets('renders TourisTrike loading screen', (tester) async {
    await tester.pumpWidget(
      TourisTrikeApp(
        maintenanceService: _FakeMaintenanceService(),
        maintenanceAuthStateChanges: const Stream<AuthState>.empty(),
      ),
    );

    expect(find.text('TourisTrike'), findsOneWidget);
  });
}

class _FakeMaintenanceService implements MaintenanceStatusService {
  @override
  Future<MaintenanceSettings> fetchStatus() async {
    return const MaintenanceSettings.operational();
  }
}
