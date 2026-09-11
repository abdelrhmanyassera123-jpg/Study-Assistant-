import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import 'model_usage.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';

/// اختيار موديل Gemini المستخدم في التلخيص.
/// Picks the Gemini model used for summarizing.
class ModelSettingsSheet extends ConsumerStatefulWidget {
  const ModelSettingsSheet({super.key});

  @override
  ConsumerState<ModelSettingsSheet> createState() => _ModelSettingsSheetState();
}

class _ModelSettingsSheetState extends ConsumerState<ModelSettingsSheet> {
  List<String>? _models;
  bool _loading = false;
  SummarizerException? _error;

  @override
  void initState() {
    super.initState();
    // بنجيب القايمة على طول عشان المستخدم يلاقيها جاهزة قدامه.
    // Fetch on open so the list is already there when the sheet appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
      _models = null;
    });

    try {
      final models = await ref.read(activeSummarizerProvider).listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        _loading = false;
      });

      // القايمة جاية مرتّبة بالفايدة من الـ Edge Function، فأول عنصر افتراضي
      // معقول. بنحترم اختيار المستخدم المحفوظ طالما لسه موجود.
      // The Edge Function ranks the list by usefulness, so the first entry is a
      // sensible default. A stored choice is kept as long as it still exists.
      final current = ref.read(settingsProvider).geminiModel;
      if (models.isNotEmpty && !models.contains(current)) {
        ref.read(settingsProvider.notifier).setGeminiModel(models.first);
      }
    } on SummarizerException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final settings = ref.watch(settingsProvider);
    final usage = ref.watch(modelUsageProvider);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        left: Insets.xl,
        right: Insets.xl,
        top: Insets.xs,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.section,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.modelSettings,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: l.testConnection,
                  onPressed: _loading ? null : _refresh,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            Text(
              l.providerGeminiHint,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: Insets.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.autoModel),
              subtitle: Text(l.autoModelHint, style: const TextStyle(height: 1.5)),
              value: settings.autoModel,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setAutoModel(v),
            ),
            const SizedBox(height: Insets.md),

            // في الوضع التلقائي مفيش داعي لقايمة من 97 موديل — اللي يهم هو
            // استهلاكك، وده معروض تحت.
            // In auto mode a list of 97 models serves nobody; what matters is
            // your usage, shown below.
            if (!settings.autoModel && _models != null && _models!.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 15, color: scheme.primary),
                  const SizedBox(width: Insets.sm),
                  Text(
                    '${l.connectedModels}: ${_models!.length}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: Insets.md),
              DropdownButtonFormField<String>(
                initialValue: _models!.contains(settings.geminiModel)
                    ? settings.geminiModel
                    : null,
                isExpanded: true,
                itemHeight: 58,
                decoration: InputDecoration(labelText: l.chooseModel),
                // بنعرض استهلاكك تحت كل موديل: جوجل ما بتعرضش الحصة المتبقية
                // في أي API، فالعدّاد المحلي هو الرقم الوحيد الحقيقي.
                // Your own usage sits under each model: Google exposes no
                // remaining-quota API, so this local count is the real number.
                selectedItemBuilder: (context) => [
                  for (final m in _models!)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(m,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr),
                    ),
                ],
                items: [
                  for (final m in _models!)
                    DropdownMenuItem(
                      value: m,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr),
                          Text(
                            usage.describe(m, isAr: l.isAr),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: usage.countFor(m) > 0
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(settingsProvider.notifier).setGeminiModel(v);
                  }
                },
              ),
            ] else if (!settings.autoModel && _loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                ),
              ),

            if (settings.autoModel) ...[
              Text(l.usageTitle,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Insets.sm),
              if (usage.counts.isEmpty)
                Text(
                  l.noUsageYet,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                )
              else
                for (final entry in (usage.counts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value))))
                  Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.key,
                            textDirection: TextDirection.ltr,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          usage.describe(entry.key, isAr: l.isAr),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: Insets.lg),
            ],

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(Insets.lg),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: Radii.all(Radii.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error!.message,
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                    SelectableText(
                      _error!.hint ?? l.geminiKeyHint,
                      style: TextStyle(
                        color: scheme.onErrorContainer.withValues(alpha: 0.85),
                        fontSize: 12,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
