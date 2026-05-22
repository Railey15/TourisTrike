import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const TourisTrikeLoadingScreen(),
      theme: AppTheme.light(),
    );
  }
}
