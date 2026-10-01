import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../summarize/style_profile.dart';
import '../summarize/styled_result.dart';
import '../summarize/summary_images.dart';
import 'lecture_job.dart';

/// المحاضرات اللي بتتلخص على السيرفر، وحالة كل واحدة.
/// The lectures being summarized on the server, and where each one stands.
class JobsPanel extends ConsumerStatefulWidget {
  const JobsPanel({super.key});

  @override
  ConsumerState<JobsPanel> createState() => _JobsPanelState();
}

class _JobsPanelState extends ConsumerState<JobsPanel> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// بيسأل كل 10 ثواني طول ما فيه شغل لسه ماشي، وبيقف لما كله يخلص.
  /// Asks every 10 seconds while anything is still running, and stops once
  /// everything is done.
  void _keepPolling(bool pending) {
    if (pending && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 10), (_) {
        ref.invalidate(recentJobsProvider);
      });
    } else if (!pending && _poll != null) {
      _poll?.cancel();
      _poll = null;
      // الشغل خلص: الملاحظات والكروت الجديدة لازم تبان في باقي التطبيق.
      // Work finished: the new notes and cards must show across the app.
      ref.invalidate(notesProvider);
      ref.invalidate(cardsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final jobs = ref.watch(recentJobsProvider).value ?? const <LectureJob>[];
    final week = DateTime.now().subtract(const Duration(days: 7));
    final shown = jobs.where((j) => j.isPending || j.createdAt.isAfter(week)).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keepPolling(shown.any((j) => j.isPending));
    });

    if (shown.isEmpty) return const SizedBox.shrink();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.backgroundJobs, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            l.backgroundJobsHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: Insets.md),
          for (final job in shown) _JobRow(job: job),
        ],
      ),
    );
  }
}

class _JobRow extends ConsumerWidget {
  const _JobRow({required this.job});

  final LectureJob job;

  String _status(AppL10n l) {
    if (job.isDone) {
      return job.cardsMade > 0 ? l.jobDoneWithCards(job.cardsMade) : l.jobDone;
    }
    if (job.isFailed) return job.error ?? l.jobFailed;
    final step = job.step;
    if (step.startsWith('transcribe:')) {
      final nums = step.substring('transcribe:'.length).split('/');
      return l.jobTranscribing(int.tryParse(nums.first) ?? 1, int.tryParse(nums.last) ?? 1);
    }
    return switch (step) {
      'summarize' => l.jobSummarizing,
      'missed' => l.jobCheckingMissed,
      'note' || 'cards' => l.jobMakingCards,
      _ => job.error == null ? l.jobQueued : l.jobRetrying,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final subject = ref.watch(subjectMapProvider)[job.subjectId];

    final icon = job.isDone
        ? Icon(Icons.check_circle_rounded, color: scheme.primary)
        : job.isFailed
            ? Icon(Icons.error_outline_rounded, color: scheme.error)
            : const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              );

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: icon,
      title: Text(job.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (subject != null) subject.name, _status(l)].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: job.isDone ? () => openJobResult(context, job.id) : null,
      trailing: job.isFailed
          ? IconButton(
              tooltip: l.retry,
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () async {
                await ref.read(lectureJobsProvider).retry(job.id);
                ref.invalidate(recentJobsProvider);
              },
            )
          : job.isDone
              ? IconButton(
                  tooltip: l.delete,
                  icon: const Icon(Icons.close_rounded, size: 19),
                  onPressed: () async {
                    await ref.read(lectureJobsProvider).delete(job.id);
                    ref.invalidate(recentJobsProvider);
                  },
                )
              : null,
    );
  }
}

Future<void> openJobResult(BuildContext context, String jobId) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => JobResultPage(jobId: jobId),
    ));

/// نتيجة تلخيص اتعمل في الخلفية — نفس عرض التلخيص العادي بكل أدواته.
/// A summary made in the background, shown with the same view and tools as
/// a normal one.
class JobResultPage extends ConsumerStatefulWidget {
  const JobResultPage({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<JobResultPage> createState() => _JobResultPageState();
}

class _JobResultPageState extends ConsumerState<JobResultPage> {
  LectureJob? _job;
  SummaryPage? _page;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final jobs = ref.read(lectureJobsProvider);
      final job = await jobs.byId(widget.jobId);
      var page = job?.result;
      // الصور بتتدوّر عليها هنا مرة واحدة وتتحفظ، عشان المرة الجاية تفتح على طول.
      // Pictures are looked up here once and saved, so next time it opens
      // straight away.
      if (job != null &&
          page != null &&
          page.blocks.any((b) => b.type == BlockType.image && b.imageUrl == null)) {
        page = await attachImages(page);
        await jobs.saveResult(job.id, page);
      }
      if (mounted) {
        setState(() {
          _job = job;
          _page = page;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _changed(SummaryPage page) async {
    setState(() => _page = page);
    try {
      await ref.read(lectureJobsProvider).saveResult(widget.jobId, page);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  /// الملاحظة اتعملت على السيرفر — الحفظ هنا بيحدّثها بالتعديلات.
  /// The note was made on the server; saving here updates it with the edits.
  Future<void> _saveNote() async {
    final job = _job;
    final page = _page;
    if (job == null || page == null) return;
    final db = ref.read(supabaseProvider);
    final fields = {
      'title': page.title.isEmpty ? job.title : page.title,
      'body': readableMath(page.toPlainText()),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      if (job.noteId != null) {
        await db.from('notes').update(fields).eq('id', job.noteId!);
      } else {
        await db.from('notes').insert({
          ...fields,
          'user_id': db.auth.currentUser!.id,
          'subject_id': job.subjectId,
        });
      }
      ref.invalidate(notesProvider);
      if (mounted) showSnack(context, context.l.savedAsNote);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final page = _page;
    final profiles = ref.watch(styleProfilesProvider).value ?? const {};
    final raw = profiles[job?.subjectId] ?? profiles[null];

    return Scaffold(
      appBar: AppBar(title: Text(job?.title ?? context.l.theSummary)),
      body: PageBody(
        maxWidth: 860,
        child: _error != null
            ? ErrorView(error: _error!, onRetry: _load)
            : job == null
                ? const LoadingView()
                : page == null
                    ? EmptyState(
                        icon: Icons.hourglass_top_rounded,
                        message: job.error ?? context.l.jobQueued,
                      )
                    : StyledResult(
                        page: page,
                        profile: raw == null
                            ? const StyleProfile()
                            : StyleProfile.fromJson(raw),
                        subjectId: job.subjectId,
                        source: job.transcript,
                        onPageChanged: _changed,
                        onSaveNote: _saveNote,
                      ),
      ),
    );
  }
}
