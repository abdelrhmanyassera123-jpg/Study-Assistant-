/// نسخة من غير تخزين للاختبارات — شوف offline_store_web.dart.
/// A storage-less stand-in for tests; see offline_store_web.dart.
class OfflineStore {
  const OfflineStore._();

  static Future<void> put(String key, Object? value) async {}

  static Future<Object?> get(String key) async => null;
}
