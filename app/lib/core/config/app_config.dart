/// Application configuration read from compile-time `--dart-define` values.
/// Never hardcode credentials or API keys in source code.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// When Supabase compile-time environment values are not provided,
  /// the app runs in offline Demo Mode using sample Egyptian sanitary ware data.
  static bool get isDemoMode =>
      supabaseUrl.trim().isEmpty || supabaseAnonKey.trim().isEmpty;

  static const String appTitle = 'مسعّر الأدوات الصحية';
}
