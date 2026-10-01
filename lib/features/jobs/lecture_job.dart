import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/providers.dart';
import '../../models/models.dart';
import '../study_ai/study_ai.dart';
import '../summarize/style_profile.dart';
import '../summarize/summarizer.dart';

/// محاضرة بتتلخص على السيرفر (جدول lecture_jobs).
/// A lecture being summarized on the server (the lecture_jobs table).
@immutable
class LectureJob {
  const LectureJob({
    required this.id,
    required this.title,
    required this.status,
    required this.step,
    required this.createdAt,
    this.subjectId,
    this.result,
    this.error,
    this.noteId,
    this.cardsMade = 0,
    this.partCount = 0,
    this.transcript = '',
    this.pdfPaths = const [],
    this.imageMode = ImageMode.web,
  });

  final String id;
  final String title;

  /// queued | working | done | failed
  final String status;

  /// "transcribe:2/5" | "summarize" | "missed" | "note" | "cards" | ""
  final String step;
  final DateTime createdAt;
  final String? subjectId;
  final SummaryPage? result;
  final String? error;
  final String? noteId;
  final int cardsMade;
  final int partCount;

  /// التفريغ بعد ما يخلص — بيستخدم لـ"إيه اللي اتنسى" والتعديل من المصدر.
  /// The transcript once finished, used for "what was missed" and edits.
  final String transcript;

  /// مسارات السلايدات (PDF) في التخزين، بترتيب إرفاقها للموديل.
  /// Storage paths of the slides (PDF), in the order they went to the model.
  final List<String> pdfPaths;
  final ImageMode imageMode;

  bool get isDone => status == 'done';
  bool get isFailed => status == 'failed';
  bool get isPending => status == 'queued' || status == 'working';

  factory LectureJob.fromMap(Map<String, dynamic> m) {
    final parts = (m['parts'] as List?) ?? const [];
    final docs = (m['docs'] as List?) ?? const [];
    final result = m['result'];
    return LectureJob(
      id: m['id'] as String,
      title: (m['title'] as String?) ?? '',
      status: (m['status'] as String?) ?? 'queued',
      step: (m['step'] as String?) ?? '',
      createdAt: DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
      subjectId: m['subject_id'] as String?,
      result: result is Map
          ? SummaryPage.fromJson(result.map((k, v) => MapEntry('$k', v)))
          : null,
      error: m['error'] as String?,
      noteId: m['note_id'] as String?,
      cardsMade: (m['cards_made'] as num?)?.toInt() ?? 0,
      partCount: parts.length,
      transcript: [
        (m['plain_text'] as String?) ?? '',
        for (final p in parts)
          if (p is Map && p['transcript'] is String) p['transcript'] as String,
      ].where((t) => t.trim().isNotEmpty).join('\n\n'),
      imageMode: ImageMode.parse((m['request'] as Map?)?['image_mode']),
      pdfPaths: [
        for (final d in docs)
          if (d is Map && d['mime'] == 'application/pdf' && d['path'] is String)
            d['path'] as String,
      ],
    );
  }
}

/// ملف هيترفع مع الشغل.
/// A file to be uploaded with the job.
@immutable
class JobFile {
  const JobFile({required this.name, required this.mimeType, required this.bytes});
  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// البرومبتات كلها بتتبني هنا مرة واحدة وتتحفظ مع الشغل، عشان العامل على
/// السيرفر يلخّص بنفس أسلوب المستخدم وشكل صفحته من غير ما يعيد كتابتها.
/// Every prompt is built here once and stored with the job, so the server
/// worker summarizes in the user's style and page look without rewriting
/// any of it.
Map<String, dynamic> buildJobRequest({
  required List<StyleSample> samples,
  required StyleProfile profile,
  required bool hasDocs,
  required String model,
  ImageMode images = ImageMode.web,
}) =>
    {
      'model': model,
      'transcribe_system': StudyPrompt.transcribeSystem,
      'transcribe_prompt': StudyPrompt.transcribePrompt,
      'no_speech_marker': StudyPrompt.noSpeechMarker,
      'image_mode': images.name,
      'summary_system': VisualPrompts.blocksSystem(profile, images: images),
      'summary_prompt': StudyPrompt.build(
        lectureText: '{{LECTURE}}',
        hasFile: hasDocs,
        samples: samples,
      ),
      'missed_system': ReworkPrompts.missedSystem,
      'missed_prompt': ReworkPrompts.missedPrompt('{{SOURCE}}', '{{SUMMARY}}'),
      'missed_box_title': 'نقط إضافية من المحاضرة',
      'cards_system': StudyAiPrompts.cardsSystem,
      'cards_prompt': StudyAiPrompts.cardsPrompt('{{SOURCE}}', 12),
      'done_title': 'التلخيص جاهز',
    };

/// أكبر ملف بيترفع للتخزين — سقف Supabase المجاني 50 ميجا للملف.
/// The largest file stored — Supabase's free plan caps a file at 50 MB.
const maxJobFileBytes = 48 * 1024 * 1024;

class LectureJobs {
  LectureJobs(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw StateError('No signed-in user');
    return id;
  }

  Future<List<LectureJob>> recent() async {
    final rows = await _db
        .from('lecture_jobs')
        .select()
        .order('created_at', ascending: false)
        .limit(30);
    return rows.map(LectureJob.fromMap).toList();
  }

  Future<LectureJob?> byId(String id) async {
    final row = await _db.from('lecture_jobs').select().eq('id', id).maybeSingle();
    return row == null ? null : LectureJob.fromMap(row);
  }

  /// بيرفع الملفات ويحط الشغل في الطابور، وبيصحّي العامل على طول.
  /// Uploads the files, queues the job, and wakes the worker right away.
  Future<String> enqueue({
    required String title,
    required String? subjectId,
    String? scheduleEntryId,
    required List<JobFile> audio,
    List<JobFile> docs = const [],
    String plainText = '',
    required Map<String, dynamic> request,
    void Function(int done, int total)? onUpload,
  }) async {
    final id = const Uuid().v4();
    final total = audio.length + docs.length;
    var done = 0;

    Future<Map<String, dynamic>> store(JobFile f, String kind, int i) async {
      final ext = f.name.contains('.') ? f.name.split('.').last.toLowerCase() : 'bin';
      final path = '$_uid/$id/$kind-$i.$ext';
      await _db.storage.from('lectures').uploadBinary(
            path,
            f.bytes,
            fileOptions: FileOptions(contentType: f.mimeType, upsert: true),
          );
      onUpload?.call(++done, total);
      return {'path': path, 'mime': f.mimeType, 'size': f.bytes.length};
    }

    final parts = [for (var i = 0; i < audio.length; i++) await store(audio[i], 'part', i)];
    final docRows = [for (var i = 0; i < docs.length; i++) await store(docs[i], 'doc', i)];

    await _db.from('lecture_jobs').insert({
      'id': id,
      'user_id': _uid,
      'title': title,
      'subject_id': subjectId,
      'schedule_entry_id': scheduleEntryId,
      'parts': parts,
      'docs': docRows,
      'plain_text': plainText,
      'request': request,
    });
    await nudge();
    return id;
  }

  /// بيصحّي العامل بدل ما يستنى دقيقة الكرون. الفشل هنا مش مشكلة — الكرون
  /// هيلحقه.
  /// Wakes the worker instead of waiting for the cron's minute. Failing here
  /// is harmless: the cron will catch it.
  Future<void> nudge() async {
    try {
      await _db.functions.invoke('lecture-worker', body: const {});
    } catch (_) {}
  }

  Future<void> retry(String id) async {
    await _db.from('lecture_jobs').update({
      'status': 'queued',
      'attempts': 0,
      'claims': 0,
      'error': null,
      'locked_until': null,
    }).eq('id', id);
    await nudge();
  }

  Future<void> saveResult(String id, SummaryPage page) => _db
      .from('lecture_jobs')
      .update({'result': page.toJson()}).eq('id', id);

  /// السلايدات بتفضل في التخزين بعد التلخيص عشان صفحاتها تترسم هنا.
  /// The slides stay in storage after summarizing so their pages can be drawn
  /// here.
  Future<List<Uint8List>> pdfs(LectureJob job) async {
    final out = <Uint8List>[];
    for (final path in job.pdfPaths) {
      try {
        out.add(await _db.storage.from('lectures').download(path));
      } catch (_) {}
    }
    return out;
  }

  Future<void> delete(String id) => _db.from('lecture_jobs').delete().eq('id', id);
}

final lectureJobsProvider = Provider<LectureJobs>(
  (ref) => LectureJobs(ref.watch(supabaseProvider)),
);

final recentJobsProvider = FutureProvider<List<LectureJob>>(
  (ref) => ref.watch(lectureJobsProvider).recent(),
);

// --------------------------------------------------- الرفع بالجملة / batch

/// ملف داخل في رفع جماعي.
/// A file in a batch upload.
@immutable
class BatchFile {
  const BatchFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
    this.modified,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
  final DateTime? modified;

  bool get isAudio => mimeType.startsWith('audio/') || mimeType == 'video/mp4';

  JobFile get asJobFile => JobFile(name: name, mimeType: mimeType, bytes: bytes);
}

/// محاضرة واحدة من رفع جماعي: صوت وملفاتها، ومادتها لو اتعرفت من الجدول.
/// One lecture from a batch: its audio and files, and its subject when the
/// timetable recognised it.
@immutable
class BatchLecture {
  const BatchLecture({
    required this.title,
    required this.audio,
    required this.docs,
    this.entry,
  });

  final String title;
  final List<BatchFile> audio;
  final List<BatchFile> docs;
  final ScheduleEntry? entry;
}

/// اسم الملف من غير امتداد ولا ترقيم النسخ، وبحروف صغيرة.
/// A file's name without extension or copy numbering, in lower case.
String normalizeLectureName(String name) => name
    .replaceAll(RegExp(r'\.[^.]+$'), '')
    .replaceAll(RegExp(r'\s*\(\d+\)$'), '')
    .replaceAll(RegExp(r'[_\-.]+'), ' ')
    .trim()
    .toLowerCase();

/// المحاضرة اللي التسجيل ده اتعمل وقتها: الملف بيتحفظ لما التسجيل يخلص، فوقته
/// بيقع جوه المحاضرة أو بعدها بشوية.
/// The lecture this recording was made during: the file is saved when the
/// recording ends, so its time falls inside the lecture or shortly after.
ScheduleEntry? lectureAt(DateTime? when, List<ScheduleEntry> schedule) {
  if (when == null) return null;
  final minutes = when.hour * 60 + when.minute;
  for (final e in schedule) {
    if (e.weekday != when.weekday) continue;
    final end = e.endMinutes ?? e.startMinutes + 120;
    if (minutes >= e.startMinutes + 10 && minutes <= end + 45) return e;
  }
  return null;
}

/// بيقسّم ملفات كتير لمحاضرات: كل صوت محاضرة، والسلايدات بتروح للصوت اللي
/// اسمه زيها أو للمحاضرة في نفس الميعاد؛ اللي ملهاش صوت بتبقى محاضرة لوحدها.
/// Splits many files into lectures: each audio file is one, slides go with
/// the audio whose name matches or whose timetable slot matches; slides with
/// no audio become a lecture of their own.
List<BatchLecture> groupBatch(List<BatchFile> files, List<ScheduleEntry> schedule) {
  final audio = files.where((f) => f.isAudio).toList();
  final docs = files.where((f) => !f.isAudio).toList();

  final groups = [
    for (final a in audio)
      (key: normalizeLectureName(a.name), entry: lectureAt(a.modified, schedule), audio: a, docs: <BatchFile>[]),
  ];
  final loose = <BatchFile>[];

  for (final d in docs) {
    final key = normalizeLectureName(d.name);
    final entry = lectureAt(d.modified, schedule);
    final match = groups.where((g) =>
        (key.isNotEmpty && (g.key.contains(key) || key.contains(g.key))) ||
        (entry != null && g.entry?.id == entry.id));
    if (match.isNotEmpty) {
      match.first.docs.add(d);
    } else {
      loose.add(d);
    }
  }

  String titleFor(BatchFile f, ScheduleEntry? e) {
    if (e == null) return f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
    final when = f.modified!;
    return '${e.title} ${when.day}/${when.month}';
  }

  return [
    for (final g in groups)
      BatchLecture(
        title: titleFor(g.audio, g.entry),
        audio: [g.audio],
        docs: g.docs,
        entry: g.entry,
      ),
    for (final d in loose)
      BatchLecture(
        title: titleFor(d, lectureAt(d.modified, schedule)),
        audio: const [],
        docs: [d],
        entry: lectureAt(d.modified, schedule),
      ),
  ];
}
