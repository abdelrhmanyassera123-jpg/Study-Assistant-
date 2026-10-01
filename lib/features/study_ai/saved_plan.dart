import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/providers.dart';
import 'study_ai.dart';

/// خطة الأسبوع المحفوظة على الجهاز، لكل حساب لوحده.
/// The week plan saved on this device, per account.
///
/// بتتحفظ محليًا مش في الداتابيز: هي ناتج نداء واحد بيتعاد كل أسبوع، ومحتاجة
/// تفتح على طول في شاشة "النهاردة" حتى من غير نت.
/// Kept locally rather than in the database: it is one call's output, remade
/// weekly, and the "Today" card needs it instantly, even offline.
class SavedPlan {
  const SavedPlan({required this.plan, required this.madeAt, required this.done});

  final StudyPlan plan;
  final DateTime madeAt;

  /// البنود اللي اتعلّم عليها النهاردة، بالفهرس جوه يوم النهاردة.
  /// Items ticked today, by index within today's day.
  final Set<int> done;

  /// الخطة بتغطي سبع أيام من يوم ما اتعملت.
  /// A plan covers seven days from the day it was made.
  bool get isCurrent => DateTime.now().difference(madeAt).inDays < 7;

  PlanDay? get today {
    final w = DateTime.now().weekday;
    return plan.days.where((d) => d.weekday == w).firstOrNull;
  }
}

String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

class SavedPlanNotifier extends AsyncNotifier<SavedPlan?> {
  String get _uid => ref.read(currentUserIdProvider) ?? 'anon';
  String get _planKey => 'week_plan_$_uid';
  String get _doneKey => 'plan_done_${_uid}_${_day(DateTime.now())}';

  @override
  Future<SavedPlan?> build() async {
    ref.watch(currentUserIdProvider);
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_planKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return SavedPlan(
        plan: StudyPlan.fromJson((m['plan'] as Map).cast<String, dynamic>()),
        madeAt: DateTime.tryParse('${m['made_at']}') ?? DateTime(2000),
        done: (p.getStringList(_doneKey) ?? const []).map(int.parse).toSet(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(StudyPlan plan) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _planKey,
      jsonEncode({'plan': plan.toJson(), 'made_at': DateTime.now().toIso8601String()}),
    );
    await p.remove(_doneKey);
    ref.invalidateSelf();
  }

  Future<void> toggleDone(int index) async {
    final current = state.value;
    if (current == null) return;
    final done = {...current.done};
    done.contains(index) ? done.remove(index) : done.add(index);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_doneKey, done.map((i) => '$i').toList());
    state = AsyncData(SavedPlan(plan: current.plan, madeAt: current.madeAt, done: done));
  }
}

final savedPlanProvider =
    AsyncNotifierProvider<SavedPlanNotifier, SavedPlan?>(SavedPlanNotifier.new);
