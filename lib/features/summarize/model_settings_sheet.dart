import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';

/// إعدادات التلخيص: المزود، الموديل، وحجم السياق.
/// Summarization settings: provider, model, and context size.
class ModelSettingsSheet extends ConsumerStatefulWidget {
  const ModelSettingsSheet({super.key});

  @override
  ConsumerState<ModelSettingsSheet> createState() => _ModelSettingsSheetState();
}

class _ModelSettingsSheetState extends ConsumerState<ModelSettingsSheet> {
  late final TextEditingController _url =
      TextEditingController(text: ref.read(settingsProvider).ollamaBaseUrl);

  List<String>? _models;
  bool _testing = false;
  SummarizerException? _error;

  @override
  void initState() {
    super.initState();
    // بنجرب الاتصال على طول عشان المستخدم يلاقي الموديلات جاهزة قدامه.
    // Probe on open so the model list is already there when the sheet appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _testing = true;
      _error = null;
      _models = null;
    });

    final settings = ref.read(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    if (settings.summarizer == SummarizerProvider.ollama) {
      notifier.setOllamaConfig(baseUrl: _url.text.trim());
    }

    try {
      final models = await ref.read(activeSummarizerProvider).listModels();
      if (!mounted) return;

      setState(() {
        _models = models;
        _testing = false;
      });

      if (models.isEmpty) return;
      final isGemini = settings.summarizer == SummarizerProvider.gemini;
      final current = isGemini ? settings.geminiModel : settings.ollamaModel;
      if (models.contains(current)) return;

      // موديلات Gemini كلها جاية من جوجل ومفلترة على اللي بيدعم البث، فالاختيار
      // التلقائي آمن. أما موديلات Ollama فبتتحمّل من مصادر مختلفة وممكن تكون
      // مكسورة أصلاً — الاختيار العشوائي بينها بيوقع المستخدم في خطأ مش فاهمه،
      // فبنسيبه يختار إلا لو عنده واحد بس.
      // Gemini's list comes from Google filtered to streaming-capable models, so
      // auto-selecting is safe. Ollama models come from anywhere and some simply
      // fail to load, so guessing between them drops the user into an error they
      // cannot explain — leave the choice to them unless there is only one.
      if (isGemini || models.length == 1) {
        _selectModel(models.first);
      }
    } on SummarizerException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _testing = false;
        });
      }
    }
  }

  void _selectModel(String model) {
    final notifier = ref.read(settingsProvider.notifier);
    if (ref.read(settingsProvider).summarizer == SummarizerProvider.gemini) {
      notifier.setGeminiModel(model);
    } else {
      notifier.setOllamaConfig(model: model);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final isGemini = settings.summarizer == SummarizerProvider.gemini;
    final selected = isGemini ? settings.geminiModel : settings.ollamaModel;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.modelSettings,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),

            // ---------------------------------------------------- provider
            Text(l.whoSummarizes, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<SummarizerProvider>(
              segments: [
                ButtonSegment(
                  value: SummarizerProvider.ollama,
                  label: Text(l.providerOllama),
                  icon: const Icon(Icons.computer_rounded),
                ),
                ButtonSegment(
                  value: SummarizerProvider.gemini,
                  label: Text(l.providerGemini),
                  icon: const Icon(Icons.cloud_outlined),
                ),
              ],
              selected: {settings.summarizer},
              onSelectionChanged: (s) {
                notifier.setSummarizerProvider(s.first);
                _refresh();
              },
            ),
            const SizedBox(height: 8),
            Text(
              isGemini ? l.providerGeminiHint : l.providerOllamaHint,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 20),

            // ------------------------------------------------ ollama server
            if (!isGemini) ...[
              TextField(
                controller: _url,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: l.serverAddress,
                  suffixIcon: _refreshButton(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ------------------------------------------------------- models
            if (_models != null && _models!.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 15, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${l.connectedModels}: ${_models!.length}',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.primary),
                    ),
                  ),
                  if (isGemini) _refreshButton(),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _models!.contains(selected) ? selected : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.chooseModel),
                items: [
                  for (final m in _models!)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) _selectModel(v);
                },
              ),
            ] else if (_testing) ...[
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
            ],

            if (_error != null) ...[
              const SizedBox(height: 4),
              _ErrorPanel(
                error: _error!,
                extraHint: isGemini ? l.geminiKeyHint : l.corsHint,
                onRetry: _testing ? null : _refresh,
              ),
            ],

            // -------------------------------------------------- context size
            if (!isGemini) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(l.contextSize,
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  Text(
                    '${settings.ollamaNumCtx}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Slider(
                value: settings.ollamaNumCtx.toDouble().clamp(4096, 65536),
                min: 4096,
                max: 65536,
                divisions: 15,
                label: '${settings.ollamaNumCtx}',
                onChanged: (v) =>
                    notifier.setOllamaConfig(numCtx: (v / 4096).round() * 4096),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _refreshButton() => IconButton(
        tooltip: context.l.testConnection,
        onPressed: _testing ? null : _refresh,
        icon: _testing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh_rounded),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.extraHint, this.onRetry});

  final SummarizerException error;
  final String extraHint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.message,
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            extraHint,
            style: TextStyle(
              color: scheme.onErrorContainer.withValues(alpha: 0.85),
              fontSize: 12,
              height: 1.7,
            ),
          ),
          if (onRetry != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: Text(context.l.retry),
              ),
            ),
        ],
      ),
    );
  }
}
