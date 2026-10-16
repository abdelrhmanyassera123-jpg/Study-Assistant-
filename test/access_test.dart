import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/data/access.dart';

void main() {
  test('reads the server answer', () {
    final a = Access.fromJson({
      'active': true,
      'reason': 'ok',
      'source': 'code',
      'ends_at': DateTime.now().add(const Duration(days: 6, hours: 3)).toUtc().toIso8601String(),
      'is_admin': false,
    });
    expect(a.active, isTrue);
    expect(a.source, 'code');
    // 6 أيام و3 ساعات = "فاضل 7" — اليوم الناقص بيتحسب لحد آخر لحظة فيه.
    // Six days and three hours reads as 7 left: a part day counts until its
    // last moment.
    expect(a.daysLeft, 7);
  });

  test('an open-ended subscription has no days count', () {
    final a = Access.fromJson({'active': true, 'reason': 'ok', 'source': 'legacy', 'ends_at': null});
    expect(a.daysLeft, isNull);
    expect(a.asOfNow.active, isTrue);
  });

  // نسخة محفوظة من غير نت كانت "شغال" — لو ميعادها عدّى، تتقفل برضو.
  // An offline copy saved as live locks too once its end has passed.
  test('a saved copy that has since ended reads as expired', () {
    final saved = Access(
      active: true,
      reason: 'ok',
      source: 'code',
      endsAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    expect(saved.asOfNow.active, isFalse);
    expect(saved.asOfNow.reason, 'expired');
    expect(saved.daysLeft, 0);
  });

  test('a saved copy round-trips', () {
    final a = Access(active: true, reason: 'ok', source: 'admin', endsAt: DateTime(2027, 1, 2, 3, 4));
    final b = Access.fromJson(a.toJson());
    expect(b.endsAt, a.endsAt);
    expect(b.source, 'admin');
  });

  test('an admin never expires from a saved copy', () {
    final admin = Access(active: true, reason: 'admin', isAdmin: true, endsAt: DateTime(2000));
    expect(admin.asOfNow.active, isTrue);
  });
}
