/// عناوين المشروع — نفس اللي في التطبيق الرئيسي (lib/core/supabase_config.dart).
/// The project's addresses, the same as the main app's
/// (lib/core/supabase_config.dart).
///
/// الـ anon key معمول عشان يتحط في كود الواجهة: الحماية من RLS في الداتابيز.
/// The anon key is meant for client code: RLS in the database protects data.
library;

const siteUrl = 'https://study-assistant-ten-psi.vercel.app/';

const supabaseUrl = 'https://epcddoelvsqzbsiaeyem.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwY2Rkb2VsdnNxemJzaWFleWVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4Njc3MjUsImV4cCI6MjEwNDQ0MzcyNX0.e4u-BtZF2UMbiVB40cFPg5ssMVp6o96OfsQ7oOw_ZEg';

/// الريبو اللي GitHub بيبني فيه الـ APK وينشره كـ Release.
/// The repository where GitHub builds the APK and publishes it as a release.
const githubRepo = 'abdelrhmanyassera123-jpg/Study-Assistant-';
