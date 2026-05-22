import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/guest/guest_trip_access_screen.dart';
import 'screens/auth/loading_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: 'https://mvtqhsrdgtwdeootgjci.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12dHFoc3JkZ3R3ZGVvb3RnamNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIwODYxMDcsImV4cCI6MjA4NzY2MjEwN30.TI-q2wAlBtd5qAZkZGhUo45rKFFooXfXLyB6kZu070o',
  );

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

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const TourisTrikeLoadingScreen(),
      theme: AppTheme.light(),
    );
  }
}
