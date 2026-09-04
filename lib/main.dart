import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/config/app_config.dart';
import 'package:touristrike/core/services/developer_settings.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/guest/guest_trip_access_screen.dart';
import 'package:touristrike/screens/tourist/tourist_spots_screen.dart';
import 'package:touristrike/screens/driver/driver_home_screen.dart';
import 'screens/auth/loading_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12dHFoc3JkZ3R3ZGVvb3RnamNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIwODYxMDcsImV4cCI6MjA4NzY2MjEwN30.TI-q2wAlBtd5qAZkZGhUo45rKFFooXfXLyB6kZu070o',
  );

  if (kDebugMode) {
    await DeveloperSettings.instance.initialize();
    unawaited(
      TourisTrikeRepository().logDeveloperTestDiagnostics(
        bookingId: DeveloperSettings.instance.testBookingId,
        event: 'app_start',
      ),
    );
  }

  runApp(const TourisTrikeApp());
}

class TourisTrikeApp extends StatelessWidget {
  const TourisTrikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // On web: intercept /trip/:token before showing the main app
    if (kIsWeb) {
      final segments = Uri.base.pathSegments;
      if (segments.length >= 2 && segments[0] == 'trip') {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: GuestTripAccessScreen(publicToken: segments[1]),
        );
      }
    }

    // Debug override: allow forcing a role when running on web for quick UI checks.
    // Use query param `?force_role=tourist` or dart define `--dart-define=FORCE_ROLE=tourist`.
    final forceRoleQuery = Uri.base.queryParameters['force_role']
        ?.toLowerCase();
    final forceRoleEnv = const String.fromEnvironment('FORCE_ROLE');
    final forceRole =
        (forceRoleQuery ?? (forceRoleEnv.isNotEmpty ? forceRoleEnv : null))
            ?.toLowerCase();
    // Log for debugging when running on web so we can see why override may not apply.
    if (kIsWeb) {
      debugPrint('WEB DEBUG: Uri.base: ${Uri.base}');
      debugPrint(
        'WEB DEBUG: force_role query="$forceRoleQuery" env="$forceRoleEnv" resolved="$forceRole"',
      );
    }

    if (forceRole == 'tourist') {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const TouristSpotsScreen(),
      );
    }

    if (forceRole == 'driver') {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const DriverHomeScreen(),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const TourisTrikeLoadingScreen(),
      theme: AppTheme.light(),
    );
  }
}
