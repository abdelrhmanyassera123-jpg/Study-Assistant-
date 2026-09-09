import 'package:flutter/material.dart';

/// نصوص التطبيق بالعربي والإنجليزي.
/// App strings in Arabic and English.
///
/// كل نص هنا getter واحد — لو نسيت ترجمة، الكومبايلر هيقولك.
/// Each string is a single getter, so a missing translation is a compile error.
class AppL10n {
  const AppL10n(this.locale);

  final Locale locale;

  bool get isAr => locale.languageCode == 'ar';

  String _(String ar, String en) => isAr ? ar : en;

  static AppL10n of(BuildContext context) =>
      Localizations.of<AppL10n>(context, AppL10n) ?? const AppL10n(Locale('ar'));

  // ---------------------------------------------------------------- app
  String get appName => _('مساعد المذاكرة', 'Study Assistant');
  String get tagline => _(
        'ذاكر بتركيز، راجع في وقته، وشوف تقدمك',
        'Focus, review on time, see your progress',
      );

  // ------------------------------------------------------------ sections
  String get dashboard => _('الرئيسية', 'Home');
  String get timer => _('المؤقت', 'Timer');
  String get tasks => _('المهام', 'Tasks');
  String get flashcards => _('المراجعة', 'Flashcards');
  String get notes => _('الملاحظات', 'Notes');
  String get stats => _('الإحصائيات', 'Stats');
  String get subjects => _('المواد', 'Subjects');
  String get settings => _('الإعدادات', 'Settings');

  // -------------------------------------------------------------- common
  String get save => _('حفظ', 'Save');
  String get cancel => _('إلغاء', 'Cancel');
  String get delete => _('حذف', 'Delete');
  String get edit => _('تعديل', 'Edit');
  String get add => _('إضافة', 'Add');
  String get search => _('بحث', 'Search');
  String get close => _('إغلاق', 'Close');
  String get retry => _('إعادة المحاولة', 'Retry');
  String get loading => _('جاري التحميل...', 'Loading...');
  String get today => _('النهاردة', 'Today');
  String get tomorrow => _('بكرة', 'Tomorrow');
  String get yesterday => _('إمبارح', 'Yesterday');
  String get all => _('الكل', 'All');
  String get optional => _('اختياري', 'optional');
  String get somethingWrong => _('حصل خطأ', 'Something went wrong');
  String get minShort => _('د', 'm');
  String get hourShort => _('س', 'h');
  String get deleteConfirm => _('متأكد إنك عايز تمسح ده؟', 'Delete this permanently?');
  String get noSubject => _('بدون مادة', 'No subject');
  String get selectSubject => _('اختر المادة', 'Pick a subject');

  // ---------------------------------------------------------------- auth
  String get signIn => _('تسجيل الدخول', 'Sign in');
  String get signUp => _('إنشاء حساب', 'Create account');
  String get signOut => _('تسجيل الخروج', 'Sign out');
  String get email => _('الإيميل', 'Email');
  String get password => _('كلمة السر', 'Password');
  String get displayName => _('الاسم', 'Name');
  String get noAccountYet => _('لسه ماعندكش حساب؟', 'Need an account?');
  String get haveAccount => _('عندك حساب بالفعل؟', 'Already have an account?');
  String get emailInvalid => _('اكتب إيميل صحيح', 'Enter a valid email');
  String get passwordShort => _(
        'كلمة السر لازم تكون 6 حروف على الأقل',
        'Password must be at least 6 characters',
      );
  String get confirmEmailSent => _(
        'بعتنالك إيميل تأكيد. افتحه وبعدين سجّل دخول.',
        'We sent you a confirmation email. Open it, then sign in.',
      );
  String get signOutConfirm => _('تسجيل الخروج من الحساب؟', 'Sign out of your account?');

  String get setupNeededTitle => _('الاتصال بـ Supabase مش متظبط', 'Supabase is not configured');
  String get setupNeededBody => _(
        'افتح lib/core/supabase_config.dart وحط الـ Project URL و anon key بتوع مشروعك، '
            'وبعدين شغّل التطبيق تاني.',
        'Open lib/core/supabase_config.dart, paste your Project URL and anon key, '
            'then restart the app.',
      );

  // ------------------------------------------------------------ dashboard
  String get goodMorning => _('صباح الخير', 'Good morning');
  String get goodAfternoon => _('مساء الخير', 'Good afternoon');
  String get goodEvening => _('مساء الخير', 'Good evening');
  String get todayFocus => _('تركيز النهاردة', 'Today’s focus');
  String get dueToday => _('المستحق النهاردة', 'Due today');
  String get cardsToReview => _('كروت للمراجعة', 'Cards to review');
  String get currentStreak => _('أيام متتالية', 'Day streak');
  String get quickStart => _('ابدأ جلسة', 'Start a session');
  String get upcomingTasks => _('مهام قريبة', 'Upcoming tasks');
  String get recentNotes => _('آخر الملاحظات', 'Recent notes');
  String get allCaughtUp => _('مفيش حاجة مستحقة — تمام كده', 'All caught up');

  // -------------------------------------------------------------- subjects
  String get addSubject => _('إضافة مادة', 'Add subject');
  String get editSubject => _('تعديل المادة', 'Edit subject');
  String get subjectName => _('اسم المادة', 'Subject name');
  String get subjectColor => _('اللون', 'Color');
  String get noSubjectsYet => _(
        'ابدأ بإضافة المواد اللي بتذاكرها',
        'Start by adding the subjects you study',
      );
  String get subjectDeleteWarning => _(
        'هيتمسح كل المهام والكروت والملاحظات المربوطة بالمادة دي.',
        'This also deletes every task, card and note linked to this subject.',
      );

  // ----------------------------------------------------------------- tasks
  String get addTask => _('إضافة مهمة', 'Add task');
  String get editTask => _('تعديل المهمة', 'Edit task');
  String get taskTitle => _('المهمة', 'Task');
  String get taskNotes => _('تفاصيل', 'Details');
  String get dueDate => _('تاريخ التسليم', 'Due date');
  String get noDueDate => _('بدون تاريخ', 'No due date');
  String get priority => _('الأولوية', 'Priority');
  String get priorityHigh => _('عالية', 'High');
  String get priorityMedium => _('متوسطة', 'Medium');
  String get priorityLow => _('منخفضة', 'Low');
  String get pending => _('مفتوحة', 'Open');
  String get completed => _('خلصت', 'Done');
  String get overdue => _('متأخرة', 'Overdue');
  String get noTasksYet => _('مفيش مهام لسه', 'No tasks yet');
  String get noTasksDone => _('مفيش مهام خلصت', 'Nothing completed yet');

  // ------------------------------------------------------------ flashcards
  String get addCard => _('إضافة كارت', 'Add card');
  String get editCard => _('تعديل الكارت', 'Edit card');
  String get cardFront => _('السؤال', 'Question');
  String get cardBack => _('الإجابة', 'Answer');
  String get startReview => _('ابدأ المراجعة', 'Start review');
  String get showAnswer => _('اعرض الإجابة', 'Show answer');
  String get againLabel => _('تاني', 'Again');
  String get hardLabel => _('صعب', 'Hard');
  String get goodLabel => _('كويس', 'Good');
  String get easyLabel => _('سهل', 'Easy');
  String get noCardsYet => _('مفيش كروت لسه', 'No cards yet');
  String get nothingDueNow => _(
        'مفيش كروت مستحقة دلوقتي — ارجع بعدين',
        'Nothing due right now — come back later',
      );
  String get reviewFinished => _('خلصت المراجعة', 'Review complete');
  String get totalCards => _('إجمالي الكروت', 'Total cards');
  String get dueNow => _('مستحق دلوقتي', 'Due now');
  String get newCards => _('جديدة', 'New');
  String get nextReview => _('المراجعة الجاية', 'Next review');

  // ----------------------------------------------------------------- timer
  String get focus => _('تركيز', 'Focus');
  String get shortBreak => _('راحة قصيرة', 'Short break');
  String get longBreak => _('راحة طويلة', 'Long break');
  String get start => _('ابدأ', 'Start');
  String get pause => _('إيقاف مؤقت', 'Pause');
  String get resume => _('كمّل', 'Resume');
  String get reset => _('إعادة', 'Reset');
  String get skip => _('تخطي', 'Skip');
  String get round => _('الجولة', 'Round');
  String get whatStudying => _('بتذاكر إيه؟', 'What are you studying?');
  String get sessionSaved => _('اتسجلت الجلسة', 'Session saved');
  String get focusLength => _('مدة التركيز (دقيقة)', 'Focus length (min)');
  String get shortBreakLength => _('الراحة القصيرة (دقيقة)', 'Short break (min)');
  String get longBreakLength => _('الراحة الطويلة (دقيقة)', 'Long break (min)');
  String get roundsBeforeLong => _('جولات قبل الراحة الطويلة', 'Rounds before long break');
  String get autoStartNext => _('ابدأ المرحلة الجاية تلقائي', 'Auto-start next phase');

  // ----------------------------------------------------------------- notes
  String get addNote => _('إضافة ملاحظة', 'Add note');
  String get editNote => _('تعديل الملاحظة', 'Edit note');
  String get noteTitle => _('العنوان', 'Title');
  String get noteBody => _('المحتوى', 'Content');
  String get noNotesYet => _('مفيش ملاحظات لسه', 'No notes yet');
  String get searchNotes => _('دوّر في الملاحظات', 'Search notes');
  String get noResults => _('مفيش نتايج', 'No results');

  // ----------------------------------------------------------------- stats
  String get last7Days => _('آخر 7 أيام', 'Last 7 days');
  String get totalFocusTime => _('إجمالي وقت التركيز', 'Total focus time');
  String get thisWeek => _('الأسبوع ده', 'This week');
  String get sessionsCount => _('عدد الجلسات', 'Sessions');
  String get bySubject => _('حسب المادة', 'By subject');
  String get dailyAverage => _('المتوسط اليومي', 'Daily average');
  String get tasksCompleted => _('مهام خلصت', 'Tasks completed');
  String get cardsReviewed => _('كروت اتراجعت', 'Cards reviewed');
  String get notEnoughData => _(
        'ذاكر شوية الأول وهتلاقي إحصائياتك هنا',
        'Study a bit and your stats will show up here',
      );

  // -------------------------------------------------------------- settings
  String get language => _('اللغة', 'Language');
  String get theme => _('المظهر', 'Theme');
  String get textSize => _('حجم النص', 'Text size');
  String get textSizeHint => _(
        'زوم المتصفح (Ctrl + عجلة) مش شغال جوه التطبيق، فاستخدم ده بدله.',
        'Browser zoom (Ctrl + wheel) does not work inside the app; use this.',
      );
  String get themeLight => _('فاتح', 'Light');
  String get themeDark => _('غامق', 'Dark');
  String get themeSystem => _('حسب النظام', 'System');
  String get account => _('الحساب', 'Account');
  String get about => _('عن التطبيق', 'About');

  // ------------------------------------------------------------- summarize
  String get summarize => _('التلخيص', 'Summarize');
  String get styleSamples => _('أمثلة أسلوبك', 'Your style');
  String get addStyleSample => _('إضافة مثال', 'Add example');
  String get editStyleSample => _('تعديل المثال', 'Edit example');
  String get sampleTitle => _('عنوان المثال', 'Example title');
  String get sampleBody => _('نص التلخيص', 'Summary text');
  String get noSamplesYet =>
      _('مفيش أمثلة لأسلوبك لسه', 'No style examples yet');
  String get samplesIntro => _(
        'اكتب 3-5 من تلخيصاتك بنفسك. الموديل هيقلد شكلها ونبرتها. '
            'اختار أحسن اللي عندك، مش أول اللي يقع تحت إيدك.',
        'Write out 3-5 of your own summaries. The model copies their shape and '
            'tone, so pick your best ones, not the first ones to hand.',
      );
  String get samplesUsedHere => _('الأمثلة اللي هتتستخدم', 'Examples in use');
  String get noSamplesWarning => _(
        'من غير أمثلة، التلخيص هيبقى عام مش بأسلوبك.',
        'Without examples the summary will be generic, not yours.',
      );

  String get pickLectureFile => _('اختار ملف المحاضرة', 'Choose lecture file');
  String get supportedFiles => _('pdf · pptx · docx · txt · md', 'pdf · pptx · docx · txt · md');
  String get orPasteText => _('أو الزق النص', 'or paste the text');
  String get lectureText => _('نص المحاضرة', 'Lecture text');
  String get unsupportedFileType =>
      _('نوع الملف ده مش مدعوم', 'That file type is not supported');
  String get fileHasNoText => _(
        'مفيش نص في الملف ده — يمكن يكون صور بس.',
        'No text in this file — it may be images only.',
      );
  String get extractedFrom => _('اتقرا من', 'Read from');
  String get blocksFound => _('قطعة', 'blocks');
  String get approxTokens => _('توكن تقريبًا', 'approx. tokens');

  String get generateSummary => _('لخّص', 'Summarize');
  String get generating => _('بيلخص...', 'Summarizing...');
  String get stopGenerating => _('إيقاف', 'Stop');
  String get theSummary => _('التلخيص', 'Summary');
  String get saveAsNote => _('احفظ كملاحظة', 'Save as note');
  String get savedAsNote => _('اتحفظ في الملاحظات', 'Saved to notes');
  String get needLectureText =>
      _('حط نص المحاضرة الأول', 'Add the lecture text first');
  String get copyText => _('نسخ', 'Copy');
  String get copied => _('اتنسخ', 'Copied');

  // --------------------------------------------------------- model settings
  String get modelSettings => _('إعدادات الموديل', 'Model settings');
  String get chooseModel => _('الموديل', 'Model');
  String get testConnection => _('اختبار الاتصال', 'Test connection');
  String get connectedModels => _('متصل — الموديلات المتاحة', 'Connected — models found');

  String get providerGeminiHint => _(
        'بيشتغل من أي جهاز. المفتاح محفوظ على السيرفر مش في المتصفح.',
        'Works from any device. The key stays on the server, not in the browser.',
      );
  String get geminiKeyMissing => _(
        'مفتاح Gemini مش متظبط على السيرفر.',
        'The Gemini key is not set on the server.',
      );
  String get geminiKeyHint => _(
        'شغّل الأمر ده مرة واحدة:\nnpx supabase secrets set GEMINI_API_KEY=...',
        'Run this once:\nnpx supabase secrets set GEMINI_API_KEY=...',
      );
  String get signInForGemini => _(
        'لازم تكون مسجّل دخول عشان تستخدم Gemini.',
        'You must be signed in to use Gemini.',
      );
  String get chooseModelFirst => _('اختار موديل الأول', 'Choose a model first');
  String get autoModel => _('اختيار تلقائي', 'Pick automatically');
  String get autoModelHint => _(
        'الخدمة بتبدأ بأفضل موديل متاح وتنتقل للي بعده لو حصته خلصت أو كان '
            'مزحوم — من غير ما تعمل حاجة.',
        'The service starts with the best available model and moves to the next '
            'when one is out of quota or busy, with nothing to do on your side.',
      );
  String get autoLabel => _('تلقائي', 'Automatic');
  String get lastUsedModel => _('آخر موديل رد', 'Last model used');
  String get usageTitle => _('استهلاكك النهاردة', 'Your usage today');
  String get noUsageYet => _('لسه ما استخدمتش حاجة النهاردة', 'Nothing used today');
  String get attachedFile => _('ملف مرفق', 'Attached file');
  String get modelReadsFile => _(
        'الموديل هيقرا الملف بنفسه — بيشتغل مع الـ PDF المكتوب والمسكون.',
        'The model reads the file itself — works for text and scanned PDFs.',
      );
  String get removeFile => _('شيل الملف', 'Remove file');

  // ------------------------------------------------------- page look
  String get pageLook => _('شكل صفحتك', 'Your page layout');
  String get pageLookIntro => _(
        'ارفع صورة من كراستك، والتطبيق يقرا شكل صفحتك (ألوانك، مربعاتك، ترتيب '
            'أقسامك) وينقل نص تلخيصك كمان — فما تحتاجش تكتبه بإيدك.',
        'Upload a photo of your notebook: the app reads your page layout — '
            'colours, boxes, section order — and transcribes the summary too, '
            'so nothing needs retyping.',
      );
  String get uploadHandwriting =>
      _('ارفع صور تلخيصاتك', 'Upload page photos');
  String get pickManyImages => _(
        'تقدر تختار أكتر من صورة مرة واحدة — كل ما زودت صفحات، الأسلوب يبان أوضح.',
        'Pick several images at once; more pages make the style clearer.',
      );
  String get analyzingLook => _('بيحلل شكل الصفحة...', 'Reading your layout...');
  String get lookSaved => _('شكل صفحتك اتسجل', 'Layout saved');
  String lookAndPagesSaved(int pages) => _(
        'اتسجل شكل صفحتك و$pages ${pages == 1 ? "تلخيص" : "تلخيصات"} كأمثلة',
        'Saved your layout, and $pages ${pages == 1 ? "summary" : "summaries"} as examples',
      );
  String get noLookYet => _('لسه ما حللناش شكل صفحتك', 'No layout read yet');
  String get reanalyze => _('حلّل تاني', 'Read again');
  String get removeLook => _('امسح الشكل', 'Delete layout');
  String get colorsFound => _('الألوان', 'Colours');
  String get sectionsFound => _('الأقسام', 'Sections');
  String get handwritingNote => _(
        'الصور بتتحلل وما بتتخزنش — التحليل بس هو اللي بيتحفظ.',
        'Photos are analysed but never stored; only the analysis is saved.',
      );
  String get exportPng => _('صورة PNG', 'PNG image');
  String get exportPdf => _('ملف PDF', 'PDF file');
  String get styledPage => _('صفحة بشكلك', 'Your styled page');
  String get plainText => _('نص عادي', 'Plain text');
}

class AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const AppL10nDelegate();

  @override
  bool isSupported(Locale locale) => const ['ar', 'en'].contains(locale.languageCode);

  @override
  Future<AppL10n> load(Locale locale) async => AppL10n(locale);

  @override
  bool shouldReload(AppL10nDelegate old) => false;
}

extension L10nContext on BuildContext {
  AppL10n get l => AppL10n.of(this);
}
