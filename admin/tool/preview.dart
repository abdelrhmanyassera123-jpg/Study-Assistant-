// أداة تطوير مش جزء من اللوحة: بتفتحها بداتا تجريبية من غير تسجيل دخول ولا
// سيرفر، عشان الشكل يتراجع. التعديلات بتشتغل على الداتا دي في الذاكرة.
// A development tool, not part of the dashboard: it opens with sample data,
// no sign-in and no server, so the design can be reviewed. Changes act on
// that data in memory.
//
// flutter build web -t tool/preview.dart -o build/preview
import 'package:flutter/material.dart';
import 'package:study_admin/api.dart';
import 'package:study_admin/main.dart';

void main() => runApp(AdminApp(api: _FakeApi()));

final _now = DateTime.now();

class _FakeApi implements AdminApi {
  final _users = <UserRow>[
    UserRow(id: 'u1', email: 'abdelrhmanyassera123@gmail.com', createdAt: DateTime(2026, 9, 8), lastSignIn: _now, source: 'legacy', usedToday: 12),
    UserRow(id: 'u2', email: 'gannahtabrizy@gmail.com', createdAt: DateTime(2026, 10, 14), lastSignIn: _now.subtract(const Duration(days: 1)), source: 'legacy', usedToday: 4),
    UserRow(id: 'u3', email: 'ahmed.student@gmail.com', createdAt: _now.subtract(const Duration(days: 5)), lastSignIn: _now, source: 'code', endsAt: _now.add(const Duration(days: 2, hours: 3)), code: 'SA-7K3P-Q9XM', usedToday: 7),
    UserRow(id: 'u4', email: 'mona.m@gmail.com', createdAt: _now.subtract(const Duration(days: 40)), lastSignIn: _now.subtract(const Duration(days: 2)), source: 'code', endsAt: _now.add(const Duration(days: 24)), code: 'SA-M2RT-8HCW'),
    UserRow(id: 'u5', email: 'old.user@gmail.com', createdAt: _now.subtract(const Duration(days: 20)), source: 'code', endsAt: _now.subtract(const Duration(days: 4)), code: 'SA-XQ4N-2BKD'),
    UserRow(id: 'u6', email: 'newcomer@gmail.com', createdAt: _now.subtract(const Duration(hours: 5))),
  ];

  late final _codes = <CodeRow>[
    CodeRow(id: 'c1', code: 'SA-7K3P-Q9XM', kind: 'trial', days: 7, note: 'أحمد — تجربة', disabled: false, createdAt: _now.subtract(const Duration(days: 6)), redeemedBy: 'u3', redeemedAt: _now.subtract(const Duration(days: 5))),
    CodeRow(id: 'c2', code: 'SA-M2RT-8HCW', kind: 'paid', days: 30, note: 'منى — فودافون كاش', disabled: false, createdAt: _now.subtract(const Duration(days: 7)), redeemedBy: 'u4', redeemedAt: _now.subtract(const Duration(days: 6))),
    CodeRow(id: 'c3', code: 'SA-XQ4N-2BKD', kind: 'trial', days: 7, note: '', disabled: false, createdAt: _now.subtract(const Duration(days: 12)), redeemedBy: 'u5', redeemedAt: _now.subtract(const Duration(days: 11))),
    CodeRow(id: 'c4', code: 'SA-HV9D-3PZE', kind: 'paid', days: 30, note: 'دفعة الترم الأول', disabled: false, createdAt: _now.subtract(const Duration(days: 1)), validUntil: _now.add(const Duration(days: 20))),
    CodeRow(id: 'c5', code: 'SA-B6WQ-NJ7R', kind: 'trial', days: 7, note: '', disabled: true, createdAt: _now.subtract(const Duration(days: 2))),
  ];

  late final _events = <EventRow>[
    EventRow(at: _now.subtract(const Duration(hours: 2)), action: 'updated', codeId: 'c5', detail: const {'disabled': true}),
    EventRow(at: _now.subtract(const Duration(days: 1)), action: 'created', codeId: 'c4', detail: const {'days': 30, 'kind': 'paid'}),
    EventRow(at: _now.subtract(const Duration(days: 5)), action: 'redeemed', codeId: 'c1', userId: 'u3', detail: {'days': 7, 'ends_at': _now.add(const Duration(days: 2)).toIso8601String()}),
    EventRow(at: _now.subtract(const Duration(days: 6)), action: 'redeemed', codeId: 'c2', userId: 'u4', detail: {'days': 30, 'ends_at': _now.add(const Duration(days: 24)).toIso8601String()}),
  ];

  @override
  Future<bool> isAdmin() async => true;
  @override
  Future<List<CodeRow>> codes() async => List.of(_codes);
  @override
  Future<List<UserRow>> users() async => List.of(_users);
  @override
  Future<List<EventRow>> events() async => List.of(_events);

  @override
  Future<Map<DateTime, int>> usage({int days = 14}) async {
    final today = DateTime(_now.year, _now.month, _now.day);
    return {for (var i = 0; i < days; i++) today.subtract(Duration(days: i)): [3, 8, 12, 5, 0, 9, 14, 6, 2, 11, 7, 4, 10, 23][i % 14]};
  }

  var _n = 0;
  @override
  Future<List<CodeRow>> createCodes({required int count, required int days, required String kind, DateTime? validUntil, String note = ''}) async {
    final made = [
      for (var i = 0; i < count; i++)
        CodeRow(id: 'n${_n++}', code: 'SA-NEW${i % 10}-${(1000 + _n).toString().substring(0, 4)}', kind: kind, days: days, note: note, disabled: false, createdAt: DateTime.now(), validUntil: validUntil),
    ];
    _codes.insertAll(0, made);
    return made;
  }

  @override
  Future<void> updateCode(String id, {int? days, bool? disabled, String? note}) async {}
  @override
  Future<void> deleteCode(String id) async => _codes.removeWhere((c) => c.id == id);
  @override
  Future<void> updateUser(String userId, {int? addDays, DateTime? endsAt, bool forever = false, bool? disabled}) async {}
}
