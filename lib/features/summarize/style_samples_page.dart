import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'page_look_card.dart';

/// إدارة أمثلة الأسلوب — التلخيصات اللي المستخدم بيكتبها بنفسه.
/// Manages the style examples: summaries the user writes themselves.
class StyleSamplesPage extends ConsumerWidget {
  const StyleSamplesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final samplesAsync = ref.watch(styleSamplesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l.styleSamples)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openStyleSampleEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addStyleSample),
      ),
      body: samplesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(styleSamplesProvider),
        ),
        data: (samples) {
          return PageBody(
            maxWidth: 860,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Insets.sm),
                InfoBanner(message: l.samplesIntro),
                const SizedBox(height: Insets.lg),
                const PageLookCard(),
                if (samples.isEmpty)
                  EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: l.noSamplesYet,
                    message: l.samplesEmptyHint,
                    action: FilledButton.icon(
                      onPressed: () => openStyleSampleEditor(context, ref, null),
                      icon: const Icon(Icons.add_rounded, size: 19),
                      label: Text(l.addStyleSample),
                    ),
                  )
                else ...[
                  SectionHeader(l.styleSamples, subtitle: l.samplesListHint),
                  CardGrid(
                    children: [
                      for (final s in samples) _SampleCard(sample: s),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SampleCard extends ConsumerWidget {
  const _SampleCard({required this.sample});

  final StyleSample sample;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subject = ref.watch(subjectMapProvider)[sample.subjectId];

    return AppCard(
      onTap: () => openStyleSampleEditor(context, ref, sample),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sample.title.isEmpty ? context.l.sampleTitle : sample.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall,
          ),
          const SizedBox(height: Insets.sm),
          Text(
            sample.body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Flexible(child: SubjectChip(subject: subject, dense: true)),
              const Spacer(),
              Text(
                '~${sample.approxTokens} ${context.l.approxTokens}',
                style:
                    text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openStyleSampleEditor(
  BuildContext context,
  WidgetRef ref,
  StyleSample? existing,
) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => _SampleEditorPage(existing: existing)),
  );
  if (changed == true) ref.invalidate(styleSamplesProvider);
}

class _SampleEditorPage extends ConsumerStatefulWidget {
  const _SampleEditorPage({this.existing});

  final StyleSample? existing;

  @override
  ConsumerState<_SampleEditorPage> createState() => _SampleEditorPageState();
}

class _SampleEditorPageState extends ConsumerState<_SampleEditorPage> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late String? _subjectId = widget.existing?.subjectId;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      showSnack(context, context.l.sampleBody);
      return;
    }
    setState(() => _busy = true);

    final repo = ref.read(repositoryProvider);
    final existing = widget.existing;
    final sample = StyleSample(
      id: existing?.id ?? '',
      title: _title.text.trim(),
      body: body,
      subjectId: _subjectId,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    try {
      if (existing == null) {
        await repo.addStyleSample(sample);
      } else {
        await repo.updateStyleSample(sample);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final existing = widget.existing;

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? l.addStyleSample : l.editStyleSample),
        actions: [
          if (existing != null)
            IconButton(
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (!await confirmDelete(context)) return;
                await ref
                    .read(repositoryProvider)
                    .deleteStyleSample(existing.id);
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          TextButton(onPressed: _busy ? null : _save, child: Text(l.save)),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: '${l.sampleTitle} (${l.optional})',
              ),
            ),
            const SizedBox(height: Insets.lg),
            SubjectDropdown(
              subjects: subjects,
              value: _subjectId,
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _body,
              autofocus: existing == null,
              maxLines: null,
              minLines: 14,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: l.sampleBody,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
