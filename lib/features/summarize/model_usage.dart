import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// بيعدّ كام طلب راح لكل موديل النهاردة، وبيفتكر حدّه المجاني.
/// Counts how many requests each model took today, and remembers its free limit.
///
/// جوجل مش بتعرض الحصة المتبقية في أي API، فالرقم الوحيد الصادق هو اللي
/// بنعدّه بنفسنا. والحد بيتعلم من رسالة الـ 429 نفسها لما توصل.
/// Google exposes no remaining-quota endpoint, so the only honest number is the
/// one we count ourselves. The limit is learned from the 429 message when one
/// arrives.
class ModelUsage {
  const ModelUsage({this.counts = const {}, this.limits = const {}});

  /// طلبات النهاردة لكل موديل.
  /// Today's request count per model.
  final Map<String, int> counts;

  /// الحد المجاني اللي اتعرف من رسالة تجاوز الحصة.
  /// The free limit learned from a quota-exceeded message.
  final Map<String, int> limits;

  int countFor(String model) => counts[model] ?? 0;
  int? limitFor(String model) => limits[model];

  /// وصف مختصر يتحط جنب اسم الموديل في القايمة.
  /// A short line to sit beside the model's name in the list.
  String describe(String model, {required bool isAr}) {
    final used = countFor(model);
    final limit = limitFor(model);

    if (used == 0 && limit == null) {
      return isAr ? 'ما استخدمتوش' : 'unused';
    }
    final usedText = isAr ? '$used النهاردة' : '$used today';
    if (limit == null) return usedText;
    return isAr ? '$usedText · الحد $limit' : '$usedText · limit $limit';
  }
}

class ModelUsageNotifier extends Notifier<ModelUsage> {
  @override
  ModelUsage build() {
    _load();
    return const ModelUsage();
  }

  static String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  static const _countPrefix = 'model_used_';
  static const _limitPrefix = 'model_limit_';

  SharedPreferences? _prefs;

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    final day = _today();

    final counts = <String, int>{};
    final limits = <String, int>{};

    for (final key in p.getKeys()) {
      // العدادات بتتخزن باليوم، فعدادات الأيام القديمة بتتشال لوحدها.
      // Counters are keyed by day, so older days fall away on their own.
      if (key.startsWith(_countPrefix) && key.endsWith('_$day')) {
        final model = key
            .substring(_countPrefix.length, key.length - day.length - 1);
        counts[model] = p.getInt(key) ?? 0;
      } else if (key.startsWith(_limitPrefix)) {
        limits[key.substring(_limitPrefix.length)] = p.getInt(key) ?? 0;
      }
    }

    state = ModelUsage(counts: counts, limits: limits);
  }

  void record(String model) {
    if (model.isEmpty) return;
    final next = state.countFor(model) + 1;
    state = ModelUsage(
      counts: {...state.counts, model: next},
      limits: state.limits,
    );
    _prefs?.setInt('$_countPrefix${model}_${_today()}', next);
  }

  void noteLimit(String model, int limit) {
    if (model.isEmpty || limit <= 0 || state.limitFor(model) == limit) return;
    state = ModelUsage(
      counts: state.counts,
      limits: {...state.limits, model: limit},
    );
    _prefs?.setInt('$_limitPrefix$model', limit);
  }
}

final modelUsageProvider =
    NotifierProvider<ModelUsageNotifier, ModelUsage>(ModelUsageNotifier.new);
