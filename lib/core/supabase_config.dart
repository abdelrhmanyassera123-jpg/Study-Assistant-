/// إعدادات الاتصال بـ Supabase / Supabase connection settings.
///
/// حط بيانات مشروعك هنا (Project Settings -> API):
/// Put your project credentials here (Project Settings -> API):
///   url     = Project URL      (https://xxxxxxxx.supabase.co)
///   anonKey = anon public key
///
/// الـ anon key آمن إنه يكون في كود الواجهة — الحماية بتيجي من RLS في الداتابيز.
/// The anon key is safe to ship in client code; RLS in the database is what protects data.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String _fallbackUrl = 'https://epcddoelvsqzbsiaeyem.supabase.co';
  static const String _fallbackAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwY2Rkb2VsdnNxemJzaWFleWVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4Njc3MjUsImV4cCI6MjEwNDQ0MzcyNX0.e4u-BtZF2UMbiVB40cFPg5ssMVp6o96OfsQ7oOw_ZEg';

  /// يقرأ من --dart-define أولاً، وإلا يستعمل القيمة المكتوبة فوق.
  /// Reads --dart-define first, otherwise falls back to the constant above.
  static const String url =
      String.fromEnvironment('SUPABASE_URL', defaultValue: _fallbackUrl);

  static const String anonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: _fallbackAnonKey);

  static bool get isConfigured =>
      url.startsWith('http') && anonKey.length > 20 && !anonKey.startsWith('YOUR_');
}
