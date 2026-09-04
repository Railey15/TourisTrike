class AppConfig {
  const AppConfig._();

  static const supabaseUrl = 'https://mvtqhsrdgtwdeootgjci.supabase.co';

  static const environmentName = String.fromEnvironment(
    'APP_ENVIRONMENT',
    defaultValue: 'default',
  );

  static const flavorName = String.fromEnvironment(
    'FLUTTER_APP_FLAVOR',
    defaultValue: 'none',
  );

  static const gitCommit = String.fromEnvironment(
    'GIT_COMMIT',
    defaultValue: 'not-provided',
  );

  static String get supabaseHost => Uri.parse(supabaseUrl).host;

  static String get supabaseProjectRef => supabaseHost.split('.').first;
}
