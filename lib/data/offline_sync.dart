import 'dart:js_interop';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'providers.dart';

/// بيبعت المراجعات اللي اتعملت من غير نت: أول ما التطبيق يفتح، وكل ما النت
/// يرجع. محتاج حد يعمله watch (HomeShell) عشان يشتغل.
/// Sends reviews made offline: when the app opens, and whenever the
/// connection returns. Needs a watcher (HomeShell) to run.
final offlineSyncProvider = Provider<void>((ref) {
  ref.watch(currentUserIdProvider);

  Future<void> flush() async {
    final sent = await ref.read(repositoryProvider).flushPendingReviews();
    if (sent > 0) {
      ref.invalidate(cardsProvider);
      ref.invalidate(weeklyReviewsProvider);
    }
  }

  final onOnline = ((web.Event _) {
    flush();
  }).toJS;
  web.window.addEventListener('online', onOnline);
  ref.onDispose(() => web.window.removeEventListener('online', onOnline));

  flush();
});
