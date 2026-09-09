import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'document_text.dart';
import 'file_input.dart';
import 'model_settings_sheet.dart';
import 'style_samples_page.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';

class SummarizePage extends ConsumerStatefulWidget {
  const SummarizePage({super.key});

  @override
  ConsumerState<SummarizePage> createState() => _SummarizePageState();
}

class _SummarizePageState extends ConsumerState<SummarizePage> {
  final _lecture = TextEditingController();
  final _outputScroll = ScrollController();

  ExtractedDocument? _extracted;
  String? _subjectId;
  String _output = '';
  bool _running = false;
  SummarizerException? _error;
  StreamSubscription<String>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _lecture.dispose();
    _outputScroll.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    // كل حاجة جوه try: لو اختيار الملف نفسه فشل، المستخدم لازم يشوف السبب
    // بدل ما الزرار يبان كأنه مش شغال.
    // Everything inside the try: if picking itself fails, the user must see why
    // instead of a button that looks dead.
    try {
      final file = await pickLocalFile(extensions: supportedDocumentExtensions);
      if (file == null || !mounted) return;

      final doc = extractDocumentText(file.name, file.bytes);
      if (doc.isEmpty) {
        showSnack(context, context.l.fileHasNoText);
        return;
      }
      setState(() {
        _extracted = doc;
        _lecture.text = doc.text;
        _output = '';
        _error = null;
      });
    } on UnsupportedDocumentException {
      if (mounted) showSnack(context, context.l.unsupportedFileType);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    setState(() => _running = false);
  }

  Future<void> _generate() async {
    final text = _lecture.text.trim();
    if (text.isEmpty) {
      showSnack(context, context.l.needLectureText);
      return;
    }

    final allSamples = ref.read(styleSamplesProvider).value ?? const <StyleSample>[];
    final samples = pickStyleSamples(allSamples, _subjectId);
    final summarizer = ref.read(activeSummarizerProvider);

    setState(() {
      _running = true;
      _output = '';
      _error = null;
    });

    try {
      final stream = summarizer.summarize(lectureText: text, samples: samples);
      _sub = stream.listen(
        (chunk) {
          if (!mounted) return;
          setState(() => _output += chunk);
          // نخلي آخر سطر ظاهر وهو بيتكتب.
          // Keep the newest line in view while it streams.
          if (_outputScroll.hasClients) {
            _outputScroll.jumpTo(_outputScroll.position.maxScrollExtent);
          }
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _running = false;
            _error = e is SummarizerException ? e : SummarizerException('$e');
          });
        },
        onDone: () {
          if (mounted) setState(() => _running = false);
        },
        cancelOnError: true,
      );
    } on SummarizerException catch (e) {
      setState(() {
        _running = false;
        _error = e;
      });
    }
  }

  Future<void> _saveAsNote() async {
    final l = context.l;
    final title = _extracted?.fileName.replaceAll(RegExp(r'\.[^.]+$'), '') ??
        _output.split('\n').first.replaceAll(RegExp(r'[#*]'), '').trim();

    try {
      await ref.read(repositoryProvider).addNote(Note(
            id: '',
            title: title.isEmpty ? l.theSummary : title,
            body: _output.trim(),
            subjectId: _subjectId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
      ref.invalidate(notesProvider);
      if (mounted) showSnack(context, l.savedAsNote);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final allSamples = ref.watch(styleSamplesProvider).value ?? const <StyleSample>[];
    final samples = pickStyleSamples(allSamples, _subjectId);

    // من غير موديل مختار مفيش تلخيص. بنقفل الزرار ونقول السبب بدل ما نسيب
    // المستخدم يضغط ويستنى ويلاقي رسالة خطأ.
    // No model means no summary. Disable the button and say why, rather than
    // letting the user press it and wait for an error.
    final settings = ref.watch(settingsProvider);
    final modelChosen = settings.summarizer == SummarizerProvider.gemini
        ? settings.geminiModel.isNotEmpty
        : settings.ollamaModel.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageBody(
        maxWidth: 820,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _StyleBanner(
              usedCount: samples.length,
              totalCount: allSamples.length,
              onManage: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const StyleSamplesPage()),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SubjectDropdown(
                    subjects: subjects,
                    value: _subjectId,
                    onChanged: (v) => setState(() => _subjectId = v),
                  ),
                ),
                const SizedBox(width: 10),
                // المزود المفعّل لازم يبان في الصفحة نفسها. لما كان مخبي جوه
                // الإعدادات، كان ممكن تظبط Gemini بالكامل والتطبيق لسه على
                // الموديل المحلي من غير أي إشارة.
                // The active provider has to be visible on the page itself.
                // Hidden inside settings, you could finish wiring Gemini while
                // the app quietly kept using the local model.
                _ProviderButton(
                  needsModel: !modelChosen,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => const ModelSettingsSheet(),
                  ),
                ),
              ],
            ),

            // ------------------------------------------------------- input
            SectionHeader(l.lectureText),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _running ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(l.pickLectureFile),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${l.supportedFiles}  ·  ${l.orPasteText}',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lecture,
              maxLines: 8,
              minLines: 5,
              onChanged: (_) {
                if (_extracted != null) setState(() => _extracted = null);
              },
              decoration: InputDecoration(
                hintText: l.lectureText,
                alignLabelWithHint: true,
              ),
            ),
            if (_extracted != null) ...[
              const SizedBox(height: 10),
              _ExtractionInfo(doc: _extracted!),
            ],

            const SizedBox(height: 18),
            if (_running)
              OutlinedButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop_rounded),
                label: Text(l.stopGenerating),
              )
            else
              FilledButton.icon(
                onPressed: modelChosen ? _generate : null,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: Text(modelChosen ? l.generateSummary : l.chooseModelFirst),
              ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBox(error: _error!),
            ],

            // ------------------------------------------------------ output
            if (_output.isNotEmpty || _running) ...[
              SectionHeader(
                _running ? l.generating : l.theSummary,
                action: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 460),
                    child: SingleChildScrollView(
                      controller: _outputScroll,
                      child: SelectableText(
                        _output.isEmpty ? '…' : _output,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(height: 1.9),
                      ),
                    ),
                  ),
                ),
              ),
              if (!_running && _output.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveAsNote,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: Text(l.saveAsNote),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _output.trim()));
                        if (context.mounted) showSnack(context, l.copied);
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(l.copyText),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// بيعرض المزود المفعّل وبيفتح إعداداته بضغطة.
/// Shows the active provider and opens its settings in one tap.
class _ProviderButton extends ConsumerWidget {
  const _ProviderButton({required this.onTap, this.needsModel = false});

  final VoidCallback onTap;
  final bool needsModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final isGemini =
        ref.watch(settingsProvider).summarizer == SummarizerProvider.gemini;

    return OutlinedButton.icon(
      onPressed: onTap,
      style: needsModel
          ? OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error),
            )
          : null,
      icon: Icon(
        needsModel
            ? Icons.warning_amber_rounded
            : (isGemini ? Icons.cloud_outlined : Icons.computer_rounded),
        size: 18,
      ),
      label: Text(isGemini ? l.providerGemini : l.providerOllama),
    );
  }
}

/// بيقول للمستخدم كام مثال هيتبعت فعلاً — ده اللي بيحدد جودة الأسلوب.
/// Shows how many examples will actually be sent; that number drives the
/// quality of the style match more than anything else.
class _StyleBanner extends StatelessWidget {
  const _StyleBanner({
    required this.usedCount,
    required this.totalCount,
    required this.onManage,
  });

  final int usedCount;
  final int totalCount;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final empty = usedCount == 0;
    final color = empty ? scheme.error : scheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(empty ? Icons.warning_amber_rounded : Icons.auto_awesome_rounded,
              size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              empty
                  ? l.noSamplesWarning
                  : '${l.samplesUsedHere}: $usedCount / $totalCount',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600, height: 1.5),
            ),
          ),
          TextButton(onPressed: onManage, child: Text(l.styleSamples)),
        ],
      ),
    );
  }
}

class _ExtractionInfo extends StatelessWidget {
  const _ExtractionInfo({required this.doc});

  final ExtractedDocument doc;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.description_outlined, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${l.extractedFrom} ${doc.fileName} · ${doc.blocks} ${l.blocksFound} · '
            '~${doc.approxTokens} ${l.approxTokens}',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});

  final SummarizerException error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
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
          if (error.hint != null) ...[
            const SizedBox(height: 6),
            Text(
              error.hint!,
              style: TextStyle(
                color: scheme.onErrorContainer.withValues(alpha: 0.85),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
