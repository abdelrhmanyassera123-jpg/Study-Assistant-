import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'audio_clip.dart';
import 'summarizer.dart';

/// حالة المسجّل.
/// The recorder's state.
enum RecorderState { idle, recording, paused }

/// بيسجّل من الميكروفون في المتصفح.
/// Records from the browser's microphone.
///
/// المعدّل 24 كيلوبت مونو: كلام المحاضرة بيطلع مفهوم تمامًا عند الحد ده،
/// والساعة بتبقى حوالي 11 ميجا بدل 60. الجودة الزيادة هنا مش بتزوّد دقة
/// التفريغ، بس بتقرّب المقطع من سقف الحجم بسرعة.
/// 24 kbps mono: lecture speech stays perfectly intelligible at that rate, and
/// an hour lands near 11 MB instead of 60. Extra bitrate buys no accuracy in
/// the transcript, it only pushes each part towards the size ceiling faster.
class MicRecorder {
  MicRecorder({
    this.segmentLimit = const Duration(minutes: 10),
    this.totalLimit = const Duration(hours: 3),
  });

  /// طول المقطع الواحد. عند 24 كيلوبت، العشر دقايق ≈ 1.8 ميجا — جوه السقف
  /// بمساحة مريحة حتى لو المتصفح رفع المعدّل من نفسه.
  /// How long one part runs. At 24 kbps ten minutes is about 1.8 MB — inside
  /// the ceiling with room to spare even if the browser raises the rate itself.
  final Duration segmentLimit;

  /// سقف للتسجيل كله. مش حد تقني — حد على عدد النداءات اللي هتتصرف من حصتك.
  /// A ceiling on the whole recording. Not a technical limit but a limit on how
  /// many calls one recording will spend from your quota.
  final Duration totalLimit;

  static const _bitsPerSecond = 24000;

  /// لو مقطع كبر عن كده بنقفله ونفتح غيره، حتى لو وقته لسه ما خلصش.
  /// If a part grows past this we close it and open another, even early.
  static const _maxPartBytes = 4 * 1024 * 1024;

  final List<Uint8List> _parts = [];
  final Stopwatch _watch = Stopwatch();

  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  Timer? _rotation;
  Future<void>? _loop;
  bool _stopping = false;
  String _mimeType = 'audio/webm';

  RecorderState state = RecorderState.idle;

  Duration get elapsed => _watch.elapsed;
  int get partCount => _parts.length + (state == RecorderState.idle ? 0 : 1);

  /// تقدير الحجم وهو بيسجّل — الجزء اللي لسه بيتكتب مش معروف حجمه بالظبط.
  /// A size estimate while recording; the part still being written has no exact
  /// size yet.
  int get estimatedBytes =>
      (elapsed.inMilliseconds * _bitsPerSecond / 8000).round();

  bool get atTotalLimit => elapsed >= totalLimit;

  /// المتصفح بيدعم التسجيل أصلاً؟
  /// Does this browser record at all?
  static bool get isSupported {
    try {
      return web.window.navigator.mediaDevices.isDefinedAndNotNull;
    } catch (_) {
      return false;
    }
  }

  /// بيختار أول صيغة المتصفح يقدر يسجّل بيها. كروم بيدي `webm/opus`، وسفاري
  /// `mp4`. الاتنين اتجربوا على Gemini وعدّوا.
  /// Picks the first format this browser can record. Chrome gives `webm/opus`,
  /// Safari `mp4`. Both were tried against Gemini and pass.
  static String _pickMimeType() {
    const candidates = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
      'audio/mp4',
    ];
    for (final type in candidates) {
      if (web.MediaRecorder.isTypeSupported(type)) return type;
    }
    return '';
  }

  /// بيطلب إذن الميكروفون ويبدأ. بيرمي [SummarizerException] برسالة مفهومة لو
  /// الإذن اترفض أو مفيش ميكروفون.
  /// Asks for microphone permission and starts. Throws [SummarizerException]
  /// with a readable message if permission is refused or no mic exists.
  Future<void> start() async {
    if (state != RecorderState.idle) return;

    final type = _pickMimeType();
    if (type.isEmpty) {
      throw const SummarizerException(
        'المتصفح ده مش بيدعم التسجيل الصوتي.',
        hint: 'جرب كروم أو إيدج أو سفاري حديث.',
      );
    }
    _mimeType = type.split(';').first;

    try {
      // مونو بقصد: صوت المحاضرة مش ستيريو، والقناة التانية بتضاعف الحجم من
      // غير ما تضيف أي معلومة للموديل.
      // Mono on purpose: a lecture is not stereo, and the second channel
      // doubles the size without adding anything the model can use.
      final constraints = web.MediaStreamConstraints(
        audio: {
          'channelCount': 1,
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        }.jsify()!,
      );
      _stream =
          await web.window.navigator.mediaDevices.getUserMedia(constraints).toDart;
    } catch (e) {
      final message = '$e';
      throw SummarizerException(
        message.contains('NotAllowed') || message.contains('Permission')
            ? 'مفيش إذن للميكروفون.'
            : 'مش قادر أفتح الميكروفون.',
        hint: message.contains('NotFound')
            ? 'مفيش ميكروفون متوصّل بالجهاز.'
            : 'اسمح للموقع بالميكروفون من إعدادات المتصفح وحاول تاني.',
      );
    }

    _parts.clear();
    _stopping = false;
    _watch
      ..reset()
      ..start();
    state = RecorderState.recording;
    _loop = _record(type);
  }

  /// بيسجّل مقطع ورا التاني لحد ما نوقف. كل مقطع ملف كامل لوحده — وده اللي
  /// بيخلي التقسيم ممكن أصلاً: تقطيع بايتات ملف مضغوط بيدّي ملفات مكسورة.
  /// Records one part after another until stopped. Each part is a complete file
  /// on its own — which is what makes splitting possible at all: slicing the
  /// bytes of a compressed file yields broken ones.
  Future<void> _record(String type) async {
    while (!_stopping) {
      final bytes = await _recordOnePart(type);
      if (bytes.isNotEmpty) _parts.add(bytes);
      if (_stopping || atTotalLimit) break;
    }

    _watch.stop();
    _rotation?.cancel();
    _rotation = null;
    _releaseMic();
    state = RecorderState.idle;
  }

  Future<Uint8List> _recordOnePart(String type) {
    final done = Completer<Uint8List>();
    final chunks = <JSAny>[];
    var size = 0;

    final recorder = web.MediaRecorder(
      _stream!,
      web.MediaRecorderOptions(
        mimeType: type,
        audioBitsPerSecond: _bitsPerSecond,
      ),
    );

    recorder.addEventListener(
      'dataavailable',
      ((web.Event event) {
        final blob = (event as web.BlobEvent).data;
        if (blob.size == 0) return;
        chunks.add(blob);
        size += blob.size.toInt();
        // المقطع كبر بدري (المتصفح رفع المعدّل مثلاً) — نقفله دلوقتي بدل ما
        // نكتشف بعدين إنه مش هيعدي.
        // The part grew early — say the browser raised the rate — so close it
        // now instead of discovering later that it will not fit.
        if (size >= _maxPartBytes && recorder.state == 'recording') {
          recorder.stop();
        }
      }).toJS,
    );

    recorder.addEventListener(
      'stop',
      ((web.Event _) => _collect(chunks, done)).toJS,
    );

    recorder.addEventListener(
      'error',
      ((web.Event _) {
        if (!done.isCompleted) done.complete(Uint8List(0));
      }).toJS,
    );

    // بيانات كل ثانية: من غيرها مش هنعرف حجم المقطع غير بعد ما يقف.
    // A slice every second: without it the part's size is unknown until it ends.
    recorder.start(1000);
    _recorder = recorder;

    _rotation?.cancel();
    _rotation = Timer(segmentLimit, () {
      if (recorder.state != 'inactive') recorder.stop();
    });

    return done.future;
  }

  void _collect(List<JSAny> chunks, Completer<Uint8List> done) async {
    if (done.isCompleted) return;
    if (chunks.isEmpty) {
      done.complete(Uint8List(0));
      return;
    }
    try {
      final blob = web.Blob(
        chunks.toJS,
        web.BlobPropertyBag(type: _mimeType),
      );
      final buffer = await blob.arrayBuffer().toDart;
      done.complete(buffer.toDart.asUint8List());
    } catch (_) {
      done.complete(Uint8List(0));
    }
  }

  void pause() {
    if (state != RecorderState.recording) return;
    _recorder?.pause();
    _watch.stop();
    state = RecorderState.paused;
  }

  void resume() {
    if (state != RecorderState.paused) return;
    _recorder?.resume();
    _watch.start();
    state = RecorderState.recording;
  }

  /// بيوقف ويرجّع التسجيل كله.
  /// Stops and returns the whole recording.
  Future<AudioClip> stop({required String name}) async {
    if (state == RecorderState.idle && _parts.isEmpty) {
      return AudioClip(
        name: name,
        mimeType: _mimeType,
        parts: const [],
        duration: Duration.zero,
      );
    }

    _stopping = true;
    _rotation?.cancel();
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') recorder.stop();

    final duration = _watch.elapsed;
    await _loop;

    return AudioClip(
      name: name,
      mimeType: _mimeType,
      parts: List.of(_parts),
      duration: duration,
    );
  }

  /// بيرمي التسجيل ويقفل الميكروفون.
  /// Throws the recording away and closes the microphone.
  Future<void> cancel() async {
    if (state == RecorderState.idle) {
      _releaseMic();
      return;
    }
    _stopping = true;
    _rotation?.cancel();
    final recorder = _recorder;
    if (recorder != null && recorder.state != 'inactive') recorder.stop();
    await _loop;
    _parts.clear();
  }

  /// لمبة الميكروفون في المتصفح بتفضل مولّعة لحد ما المسارات تتقفل.
  /// The browser's recording indicator stays lit until the tracks are stopped.
  void _releaseMic() {
    final stream = _stream;
    if (stream == null) return;
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
    _stream = null;
    _recorder = null;
  }

  void dispose() {
    _stopping = true;
    _rotation?.cancel();
    _releaseMic();
  }
}
