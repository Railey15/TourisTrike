import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/tourist/tourist_wallet_screen.dart';
import 'screens/auth/loading_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://mvtqhsrdgtwdeootgjci.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12dHFoc3JkZ3R3ZGVvb3RnamNpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzIwODYxMDcsImV4cCI6MjA4NzY2MjEwN30.TI-q2wAlBtd5qAZkZGhUo45rKFFooXfXLyB6kZu070o',
  );

  Uri? initialDeepLink;
  try {
    initialDeepLink = await AppLinks().getInitialLink();
  } catch (error) {
    debugPrint('Initial app link unavailable: $error');
  }

  runApp(TourisTrikeApp(initialDeepLink: initialDeepLink));
}

class TourisTrikeApp extends StatelessWidget {
  const TourisTrikeApp({super.key, this.initialDeepLink});

  final Uri? initialDeepLink;

  bool _isWalletDeepLink(Uri? uri) {
    if (uri == null) return false;
    return uri.scheme.toLowerCase() == 'touristrike' &&
        uri.host.toLowerCase() == 'wallet';
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final home = currentUser != null && _isWalletDeepLink(initialDeepLink)
        ? TouristWalletScreen(initialDeepLink: initialDeepLink)
        : const TourisTrikeLoadingScreen();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: home,
      theme: AppTheme.light(),
    );
  }
}
