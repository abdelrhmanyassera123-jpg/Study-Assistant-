import 'package:supabase_flutter/supabase_flutter.dart';

/// كل اللي لوحة التحكم بتقراه وبتكتبه — بيعدّي على دوال الأدمن في الداتابيز
/// (supabase/migrations/20261016*.sql)، وكل واحدة منها بترفض أي حد مش أدمن.
/// Everything the dashboard reads and writes goes through the admin
/// functions in the database (supabase/migrations/20261016*.sql), each of
/// which refuses anyone who is not an admin.
abstract class AdminApi {
  Future<bool> isAdmin();
  Future<List<CodeRow>> codes();
  Future<List<UserRow>> users();
  Future<List<EventRow>> events();

  /// استهلاك الذكاء الاصطناعي آخر [days] يوم، يوم بيوم.
  /// AI calls over the last [days] days, day by day.
  Future<Map<DateTime, int>> usage({int days = 14});

  Future<List<CodeRow>> createCodes({
    required int count,
    required int days,
    required String kind,
    DateTime? validUntil,
    String note,
  });
  Future<void> updateCode(String id, {int? days, bool? disabled, String? note});
  Future<void> deleteCode(String id);
  Future<void> updateUser(String userId, {int? addDays, DateTime? endsAt, bool forever, bool? disabled});
}

class CodeRow {
  const CodeRow({
    required this.id,
    required this.code,
    required this.kind,
    required this.days,
    required this.note,
    required this.disabled,
    required this.createdAt,
    this.validUntil,
    this.redeemedBy,
    this.redeemedAt,
  });

  final String id;
  final String code;

  /// trial أو paid.
  /// trial or paid.
  final String kind;
  final int days;
  final String note;
  final bool disabled;
  final DateTime createdAt;
  final DateTime? validUntil;
  final String? redeemedBy;
  final DateTime? redeemedAt;

  bool get used => redeemedBy != null;
  bool get lapsed => !used && validUntil != null && validUntil!.isBefore(DateTime.now());

  factory CodeRow.fromJson(Map<String, dynamic> m) => CodeRow(
        id: '${m['id']}',
        code: '${m['code']}',
        kind: '${m['kind']}',
        days: (m['days'] as num).toInt(),
        note: '${m['note'] ?? ''}',
        disabled: m['disabled'] == true,
        createdAt: _date(m['created_at'])!,
        validUntil: _date(m['valid_until']),
        redeemedBy: m['redeemed_by'] as String?,
        redeemedAt: _date(m['redeemed_at']),
      );
}

class UserRow {
  const UserRow({
    required this.id,
    required this.email,
    required this.createdAt,
    this.lastSignIn,
    this.source,
    this.endsAt,
    this.disabled = false,
    this.usedToday = 0,
    this.code,
  });

  final String id;
  final String email;
  final DateTime createdAt;
  final DateTime? lastSignIn;

  /// legacy، code، admin — أو null لو مالوش اشتراك خالص.
  /// legacy, code, admin — or null with no subscription at all.
  final String? source;
  final DateTime? endsAt;
  final bool disabled;
  final int usedToday;
  final String? code;

  bool get active =>
      source != null && !disabled && (endsAt == null || endsAt!.isAfter(DateTime.now()));

  int? get daysLeft {
    final end = endsAt;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? 0 : (left.inMinutes / (24 * 60)).ceil();
  }

  factory UserRow.fromJson(Map<String, dynamic> m) => UserRow(
        id: '${m['user_id']}',
        email: '${m['email'] ?? ''}',
        createdAt: _date(m['created_at'])!,
        lastSignIn: _date(m['last_sign_in_at']),
        source: m['source'] as String?,
        endsAt: _date(m['ends_at']),
        disabled: m['disabled'] == true,
        usedToday: (m['used_today'] as num?)?.toInt() ?? 0,
        code: m['code'] as String?,
      );
}

class EventRow {
  const EventRow({
    required this.at,
    required this.action,
    required this.detail,
    this.codeId,
    this.userId,
    this.actor,
  });

  final DateTime at;

  /// created، redeemed، updated، user_updated.
  final String action;
  final Map<String, dynamic> detail;
  final String? codeId;
  final String? userId;
  final String? actor;

  factory EventRow.fromJson(Map<String, dynamic> m) => EventRow(
        at: _date(m['at'])!,
        action: '${m['action']}',
        detail: (m['detail'] as Map?)?.cast<String, dynamic>() ?? const {},
        codeId: m['code_id'] as String?,
        userId: m['user_id'] as String?,
        actor: m['actor'] as String?,
      );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class SupabaseAdminApi implements AdminApi {
  SupabaseAdminApi(this._db);

  final SupabaseClient _db;

  @override
  Future<bool> isAdmin() async {
    final raw = await _db.rpc('my_access');
    return (raw as Map)['is_admin'] == true;
  }

  @override
  Future<List<CodeRow>> codes() async {
    final rows = await _db.from('access_codes').select().order('created_at', ascending: false);
    return [for (final r in rows) CodeRow.fromJson(r)];
  }

  @override
  Future<List<UserRow>> users() async {
    final rows = await _db.rpc('admin_users') as List;
    return [for (final r in rows) UserRow.fromJson((r as Map).cast<String, dynamic>())];
  }

  @override
  Future<List<EventRow>> events() async {
    final rows = await _db.from('code_events').select().order('at', ascending: false).limit(300);
    return [for (final r in rows) EventRow.fromJson(r)];
  }

  @override
  Future<Map<DateTime, int>> usage({int days = 14}) async {
    final since = DateTime.now().subtract(Duration(days: days - 1));
    final rows = await _db
        .from('ai_usage')
        .select('day, calls')
        .gte('day', '${since.year}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}');
    final out = <DateTime, int>{};
    for (final r in rows) {
      final day = DateTime.parse('${r['day']}');
      out[day] = (out[day] ?? 0) + ((r['calls'] as num?)?.toInt() ?? 0);
    }
    return out;
  }

  @override
  Future<List<CodeRow>> createCodes({
    required int count,
    required int days,
    required String kind,
    DateTime? validUntil,
    String note = '',
  }) async {
    final rows = await _db.rpc('admin_create_codes', params: {
      'p_count': count,
      'p_days': days,
      'p_kind': kind,
      'p_valid_until': validUntil?.toUtc().toIso8601String(),
      'p_note': note,
    }) as List;
    return [for (final r in rows) CodeRow.fromJson((r as Map).cast<String, dynamic>())];
  }

  @override
  Future<void> updateCode(String id, {int? days, bool? disabled, String? note}) =>
      _db.rpc('admin_update_code', params: {
        'p_id': id,
        'p_days': days,
        'p_disabled': disabled,
        'p_note': note,
      });

  @override
  Future<void> deleteCode(String id) => _db.rpc('admin_delete_code', params: {'p_id': id});

  @override
  Future<void> updateUser(
    String userId, {
    int? addDays,
    DateTime? endsAt,
    bool forever = false,
    bool? disabled,
  }) =>
      _db.rpc('admin_update_user', params: {
        'p_user': userId,
        'p_add_days': addDays,
        'p_ends_at': endsAt?.toUtc().toIso8601String(),
        'p_forever': forever,
        'p_disabled': disabled,
      });
}
