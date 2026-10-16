import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'offline_store.dart';
import 'providers.dart';

/// حالة اشتراك الحساب — جاية من my_access على السيرفر.
/// The account's subscription state, from my_access on the server.
class Access {
  const Access({
    required this.active,
    required this.reason,
    this.source,
    this.endsAt,
    this.isAdmin = false,
  });

  final bool active;

  /// ok، admin، none (مالوش اشتراك)، expired، disabled، signed_out.
  /// ok, admin, none (no subscription), expired, disabled, signed_out.
  final String reason;

  /// legacy (حساب قديم مجاني)، code، admin.
  /// legacy (an older free account), code, admin.
  final String? source;

  /// null = من غير نهاية.
  /// null = no end.
  final DateTime? endsAt;
  final bool isAdmin;

  /// الأيام الفاضلة، مقرّبة لفوق — "فاضل يوم" لحد آخر لحظة فيه.
  /// Days left, rounded up: "1 day left" until its very last moment.
  int? get daysLeft {
    final end = endsAt;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    if (left.isNegative) return 0;
    return (left.inMinutes / (24 * 60)).ceil();
  }

  factory Access.fromJson(Map<String, dynamic> m) => Access(
        active: m['active'] == true,
        reason: '${m['reason'] ?? 'none'}',
        source: m['source'] as String?,
        endsAt: m['ends_at'] == null ? null : DateTime.tryParse('${m['ends_at']}')?.toLocal(),
        isAdmin: m['is_admin'] == true,
      );

  Map<String, dynamic> toJson() => {
        'active': active,
        'reason': reason,
        'source': source,
        'ends_at': endsAt?.toUtc().toIso8601String(),
        'is_admin': isAdmin,
      };

  /// النسخة المحفوظة لسه شغالة دلوقتي؟ — اشتراك محفوظ "شغال" ممكن يكون
  /// خلص من ساعتها.
  /// Is the saved copy still live now? A subscription saved as live may have
  /// ended since.
  Access get asOfNow => active && endsAt != null && endsAt!.isBefore(DateTime.now()) && !isAdmin
      ? Access(active: false, reason: 'expired', source: source, endsAt: endsAt)
      : this;
}

/// الاشتراك: بيتسأل أول ما الحساب يدخل، وبيتسأل تاني لما:
///   • الأدمن يغيّر صف الاشتراك (Realtime) — القفل بيوصل في نفس اللحظة.
///   • ميعاد النهاية ييجي والتطبيق مفتوح.
///   • كل 10 دقايق، احتياطي لو الـ Realtime وقع.
/// من غير نت بيستخدم آخر نسخة محفوظة؛ ولو مفيش نسخة، التطبيق بيفتح (السيرفر
/// نفسه بيرفض الذكاء الاصطناعي لأي حد مالوش اشتراك).
///
/// The subscription: asked as the account signs in, and again when
///   • the admin changes the subscription row (Realtime): a lock lands that
///     moment.
///   • the end time arrives with the app open.
///   • every 10 minutes, in case Realtime dropped.
/// Offline it uses the last saved copy; with none, the app opens (the server
/// itself refuses AI to anyone without a subscription).
class AccessNotifier extends AsyncNotifier<Access> {
  Timer? _timer;
  RealtimeChannel? _channel;

  @override
  Future<Access> build() async {
    final uid = ref.watch(currentUserIdProvider);
    ref.onDispose(_stop);
    if (uid == null) return const Access(active: false, reason: 'signed_out');

    _listen(uid);
    return _fetch(uid);
  }

  Future<Access> _fetch(String uid) async {
    final db = ref.read(supabaseProvider);
    final cacheKey = '$uid/access';
    try {
      final raw = await db.rpc('my_access').timeout(const Duration(seconds: 8));
      final access = Access.fromJson((raw as Map).cast<String, dynamic>());
      OfflineStore.put(cacheKey, access.toJson());
      _scheduleEnd(access);
      return access;
    } catch (_) {
      final cached = await OfflineStore.get(cacheKey);
      if (cached is Map) {
        final access = Access.fromJson(cached.cast<String, dynamic>()).asOfNow;
        _scheduleEnd(access);
        return access;
      }
      return const Access(active: true, reason: 'unknown');
    }
  }

  /// بيسأل السيرفر تاني دلوقتي — بعد تفعيل كود مثلًا.
  /// Asks the server again now, after redeeming a code for instance.
  Future<void> refresh() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    state = AsyncData(await _fetch(uid));
  }

  void _listen(String uid) {
    final db = ref.read(supabaseProvider);
    _channel = db
        .channel('subscription-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => refresh(),
        )
        .subscribe();
  }

  void _scheduleEnd(Access access) {
    _timer?.cancel();
    final end = access.endsAt;
    var wait = const Duration(minutes: 10);
    if (access.active && end != null) {
      final untilEnd = end.difference(DateTime.now()) + const Duration(seconds: 2);
      if (untilEnd < wait) wait = untilEnd.isNegative ? Duration.zero : untilEnd;
    }
    _timer = Timer(wait, refresh);
  }

  void _stop() {
    _timer?.cancel();
    final channel = _channel;
    if (channel != null) ref.read(supabaseProvider).removeChannel(channel);
    _channel = null;
  }
}

final accessProvider = AsyncNotifierProvider<AccessNotifier, Access>(AccessNotifier.new);

/// تفعيل كود. بيرجّع null لو نجح، وإلا سبب الرفض من السيرفر (invalid، used،
/// trial_used، ...).
/// Redeems a code. Returns null on success, or the server's reason for
/// refusing (invalid, used, trial_used, ...).
Future<({String? error, DateTime? endsAt})> redeemCode(WidgetRef ref, String code) async {
  final raw = await ref.read(supabaseProvider).rpc('redeem_code', params: {'p_code': code});
  final m = (raw as Map).cast<String, dynamic>();
  if (m['ok'] == true) {
    await ref.read(accessProvider.notifier).refresh();
    return (error: null, endsAt: DateTime.tryParse('${m['ends_at']}')?.toLocal());
  }
  return (error: '${m['error'] ?? 'invalid'}', endsAt: null);
}
