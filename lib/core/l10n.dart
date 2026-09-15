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

  String get workspace => _('مساحة المذاكرة', 'YOUR WORKSPACE');
  String get focusTitle => _('خطوة صغيرة النهاردة، فرق كبير بكرة.', 'Small steps today. A brighter tomorrow.');
  String get focusSubtitle => _('رتّب أفكارك، اختار هدفك، وابدأ وقتك بتركيز.', 'Clear your mind, pick a goal, and make time to focus.');
  String get personalSpace => _('كل أدواتك، في مكان واحد', 'A little space for big ideas');
  String get more => _('المزيد', 'More');
  String get summarizeLecture => _('لخّص محاضرة', 'Summarize a lecture');
  String get reviewNow => _('راجع دلوقتي', 'Review now');
  /// كام كارت مستنّي المراجعة — الصيغة بتتغير مع العدد في اللغتين.
  /// How many cards are waiting; the wording changes with the count in both
  /// languages.
  String cardsWaiting(int n) {
    if (!isAr) return n == 1 ? '1 card waiting' : '$n cards waiting';
    if (n == 1) return 'كارت واحد مستنيك';
    if (n == 2) return 'كارتين مستنيينك';
    if (n <= 10) return '$n كروت مستنيينك';
    return '$n كارت مستنيك';
  }
  String get onePlace => _('كله في مكان واحد', 'All in one place');
  String get viewAll => _('عرض الكل', 'View all');
  String get stepContent => _('المحتوى', 'Content');
  String get stepContentHint => _(
        'سجّل المحاضرة، أو ارفع ملفها، أو الزق نصها — وتقدر تجمّع أكتر من مصدر',
        'Record the lecture, upload it, or paste its text — sources combine',
      );
  String get stepStyle => _('أسلوبك', 'Your style');
  String get stepStyleHint => _(
        'الأمثلة والتخطيط اللي التلخيص هيتبعهم',
        'The examples and layout the summary will follow',
      );
  String get stepResult => _('النتيجة', 'Result');
  String get stepResultHint =>
      _('راجعها، احفظها، أو صدّرها', 'Review it, save it, or export it');

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
  /// أسماء مختصرة للعدّادات: "1 مهام" أخف من "1 المهام".
  /// Short names for counters: "1 tasks" reads better than "1 the tasks".
  String get countTasks => _('مهام', 'tasks');
  String get countCards => _('كروت', 'cards');
  String get countNotes => _('ملاحظات', 'notes');

  String get subjectsHint => _(
        'المواد بتلمّ المهام والكروت والملاحظات في مكان واحد.',
        'Subjects gather tasks, cards and notes in one place.',
      );
  String get subjectsEmptyHint => _(
        'ابدأ بمادة واحدة — تقدر تضيف الباقي في أي وقت.',
        'Start with one subject; you can add the rest whenever.',
      );
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
  String get tasksEmptyHint => _(
        'اكتب اللي عليك النهارده وخليه قدام عينك.',
        'Write down what today needs and keep it in sight.',
      );
  String get doneHint => _(
        'أول ما تخلّص مهمة هتلاقيها هنا.',
        'Tasks you finish will collect here.',
      );

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
  String get cardsEmptyHint => _(
        'اكتب السؤال والإجابة، والتطبيق هيرجّعهملك في الوقت المناسب.',
        'Write a question and an answer; the app brings them back on time.',
      );
  String get allCards => _('كل الكروت', 'All cards');
  String get cardsListHint => _(
        'اضغط على أي كارت لتعديله.',
        'Tap any card to edit it.',
      );
  String get reviewCardHint => _(
        'مراجعة قصيرة دلوقتي أنفع من مذاكرة طويلة قبل الامتحان.',
        'A short review now beats a long one the night before.',
      );
  String get saveAndAddAnother =>
      _('حفظ وإضافة تاني', 'Save and add another');
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
  String get notesEmptyHint => _(
        'اكتب ملخّصك بنفسك، أو احفظ اللي بيطلع من التلخيص.',
        'Write a summary yourself, or save one the summarizer produces.',
      );
  String get clear => _('مسح', 'Clear');

  /// عدد الملاحظات الظاهرة — العربي بيفرّق بين المفرد والمثنى والجمع.
  /// How many notes are showing; Arabic separates one, two and many.
  String notesCount(int n) {
    if (!isAr) return n == 1 ? '1 note' : '$n notes';
    if (n == 1) return 'ملاحظة واحدة';
    if (n == 2) return 'ملاحظتان';
    if (n <= 10) return '$n ملاحظات';
    return '$n ملاحظة';
  }

  // ------------------------------------------ أدوات الذكاء / study tools
  String get studyAi => _('أدوات المذاكرة', 'Study tools');

  // الكروت / cards
  String get makeCards => _('اعمل كروت مراجعة', 'Make review cards');
  String get makeCardsHint => _(
        'الموديل بيطلّع الكروت من المحتوى ده بس. راجعها قبل ما تتحفظ.',
        'The model builds cards from this material only. Check them before they are saved.',
      );
  String get makingCards => _('بيطلّع الكروت...', 'Making the cards...');

  String saveCards(int n) {
    if (!isAr) return n == 1 ? 'Save 1 card' : 'Save $n cards';
    if (n == 1) return 'احفظ كارت واحد';
    if (n == 2) return 'احفظ الكارتين';
    if (n <= 10) return 'احفظ $n كروت';
    return 'احفظ $n كارت';
  }

  String cardsSaved(int n) {
    if (!isAr) return n == 1 ? '1 card saved' : '$n cards saved';
    if (n == 1) return 'اتحفظ كارت واحد';
    if (n == 2) return 'اتحفظوا كارتين';
    if (n <= 10) return 'اتحفظوا $n كروت';
    return 'اتحفظ $n كارت';
  }

  // اسأل / ask
  String get askLecture => _('اسأل عن المحاضرة', 'Ask about the lecture');
  String get askTitle => _(
        'اسأل في المحاضرة دي',
        'Ask about this lecture',
      );
  String get askHint => _('اكتب سؤالك...', 'Type your question...');
  String get askGrounded => _(
        'الإجابات من المحاضرة دي بس',
        'Answers come from this lecture only',
      );

  /// أسئلة تبدأ بيها — الشاشة الفاضية أصعب حاجة في محادثة.
  /// Openers to start from; an empty chat screen is the hardest part.
  List<String> get askOpeners => isAr
      ? const [
          'اشرحلي أهم فكرة في المحاضرة دي',
          'إيه اللي ممكن ييجي في الامتحان من هنا؟',
          'اديني مثال على اللي اتشرح',
          'إيه الفرق بين المفاهيم اللي اتذكرت؟',
        ]
      : const [
          'Explain the main idea of this lecture',
          'What could come up in an exam from this?',
          'Give me an example of what was explained',
          'What is the difference between the concepts mentioned?',
        ];

  // الامتحان / exam
  String get mockExam => _('امتحان تجريبي', 'Mock exam');
  String get makingExam => _('بيجهّز الأسئلة...', 'Writing the questions...');
  String get markExam => _('صحّح إجاباتي', 'Mark my answers');
  String get markingExam => _('بيصحح...', 'Marking...');
  String get newExam => _('امتحان تاني', 'New exam');
  String get yourAnswer => _('إجابتك', 'Your answer');
  String get modelAnswer => _('الإجابة النموذجية', 'Model answer');
  String get examResult => _('النتيجة', 'Result');
  String get multipleChoice => _('اختيار من متعدد', 'Multiple choice');
  String get written => _('مقالي', 'Written');
  String get weakSpots => _('محتاج مراجعة', 'Needs review');

  String markScore(double score) {
    final percent = (score * 100).round();
    return isAr ? 'الدرجة: $percent%' : 'Score: $percent%';
  }

  // الخطة / plan
  String get weekPlan => _('خطة الأسبوع', 'This week\'s plan');
  String get weekPlanHint => _(
        'خطة مبنية على جدولك ومهامك والكروت المستحقة.',
        'A plan built from your timetable, your tasks and the cards due.',
      );
  String get makingPlan => _('بيرتّب الأسبوع...', 'Laying out the week...');
  String get addToTasks => _('ضيفها للمهام', 'Add to tasks');
  String get addedToTasks => _('اتضافت للمهام', 'Added to your tasks');

  String planTotal(String time) =>
      isAr ? 'إجمالي الخطة: $time' : 'Plan total: $time';

  // -------------------------------------------------- الجدول / timetable
  String get schedule => _('الجدول', 'Timetable');
  String get scheduleHint => _(
        'محاضراتك الأسبوعية، ومعاها تنبيه قبل كل واحدة.',
        'Your week of lectures, each with a reminder before it.',
      );
  String get addLecture => _('إضافة محاضرة', 'Add lecture');
  String get editLecture => _('تعديل المحاضرة', 'Edit lecture');
  String get lectureName => _('اسم المحاضرة', 'Lecture');
  String get hall => _('القاعة', 'Room');
  String get lecturer => _('الدكتور', 'Lecturer');
  String get startTime => _('من', 'From');
  String get endTime => _('لـ', 'To');
  String get day => _('اليوم', 'Day');
  String get noScheduleYet => _('مفيش جدول لسه', 'No timetable yet');
  String get scheduleEmptyHint => _(
        'الزق جدول الكلية أو ارفع صورته أو PDF بتاعه، والباقي عليّا.',
        'Paste your college timetable or upload a photo or PDF of it; I will do the rest.',
      );
  String get noLecturesToday =>
      _('مفيش محاضرات النهاردة', 'No lectures today');

  // الاستيراد بالذكاء الاصطناعي / the AI import
  String get importSchedule => _('استورد جدولك', 'Import timetable');
  String get importScheduleHint => _(
        'الزق الجدول زي ما هو أو ارفع صورته أو PDF بتاعه (لو كذا صفحة، ارفعهم '
            'كلهم) — التطبيق هيرتّبه.',
        'Paste the timetable as it is or upload a photo or PDF of it (upload '
            'every page if it spans a few); the app will lay it out.',
      );
  String get pasteSchedule => _(
        'الزق الجدول هنا... (أي شكل: جدول الكلية، رسالة، صورة مكتوبة)',
        'Paste the timetable here — any shape it came in',
      );
  String get orUploadPhoto =>
      _('أو ارفع صورة الجدول أو ملف PDF بتاعه', 'or upload a photo or PDF of it');
  /// السؤال اللي بيتسأل لما الجدول يبقى فيه أكتر من قسم.
  /// The question asked when a timetable holds more than one section.
  String whichGroup(String label) {
    final what = label.trim().isEmpty ? (isAr ? 'قسم' : 'section') : label.trim();
    return isAr ? 'انت في أنهي $what؟' : 'Which $what are you in?';
  }

  String get whichGroupHint => _(
        'الجدول ده فيه أكتر من قسم مدمجين. اختار بتاعك عشان نسيب الباقي.',
        'This timetable merges more than one section. Pick yours and the rest is left out.',
      );
  String get allGroups => _('كلهم', 'All of them');

  /// السؤال اللي بيتسأل لما القسم المختار يبقى فيه مجموعات فرعية جواه.
  /// The question asked when the chosen section has subgroups inside it.
  String get whichSubgroup => _(
        'وانت جوّاه في أنهي مجموعة فرعية؟',
        'And which subgroup inside it are you in?',
      );

  String groupPicked(int kept, int total) => isAr
      ? 'هيتحفظ $kept من $total محاضرة'
      : '$kept of $total lectures will be saved';

  String get readSchedule => _('اقرا الجدول', 'Read it');
  String get readingSchedule => _('بيقرا الجدول...', 'Reading the timetable...');
  String get reviewBeforeSaving =>
      _('راجعه قبل الحفظ', 'Check it before saving');
  String get saveSchedule => _('احفظ الجدول', 'Save timetable');
  String get replaceSchedule => _('امسح القديم وحط ده', 'Replace what is there');
  String get addToSchedule => _('ضيفه للجدول', 'Add to the timetable');
  String get clearSchedule => _('امسح الجدول كله', 'Clear the timetable');
  String get scheduleCleared => _('الجدول اتمسح', 'Timetable cleared');

  String clearScheduleWarning(int n) => isAr
      ? 'هيتشال $n محاضرة، والتنبيهات بتاعتهم كمان.'
      : '$n lectures will go, and their reminders with them.';

  String get scheduleSaved => _('الجدول اتحفظ', 'Timetable saved');

  String lecturesRead(int n) {
    if (!isAr) return n == 1 ? '1 lecture read' : '$n lectures read';
    if (n == 1) return 'محاضرة واحدة';
    if (n == 2) return 'محاضرتين';
    if (n <= 10) return '$n محاضرات';
    return '$n محاضرة';
  }

  /// تنبيه لما أيام من الجدول فشلت تتقرا (حصة خلصت، تايم آوت) والجدول
  /// بالتالي ناقصها.
  /// A warning when some days of the timetable failed to read (quota,
  /// timeout) and the schedule is missing them as a result.
  String scheduleDaysFailed(List<String> days) {
    final list = days.join('، ');
    return _(
      'مش قدرنا نقرا ($list) — حصة الموديل خلصت أو الاتصال اتقطع وقتها. '
          'الجدول ده ناقصهم؛ جرب تاني بعد شوية عشان تكمّلهم.',
      "Couldn't read ($list) — the model's quota ran out or the connection "
          'dropped partway through. This schedule is missing them; try '
          'again shortly to fill them in.',
    );
  }

  // التنبيهات / reminders
  String get reminders => _('التنبيهات', 'Reminders');
  String get remindersHint => _(
        'تنبيه قبل كل محاضرة، وانت اللي بتحدد بكام.',
        'A reminder before each lecture, as early as you choose.',
      );
  String get reminderOff => _('من غير تنبيه', 'No reminder');
  String get enableReminders => _('فعّل التنبيهات', 'Turn reminders on');
  String get allowNotifications =>
      _('اسمح بالتنبيهات', 'Allow notifications');
  String get remindersBlocked => _(
        'المتصفح رافض التنبيهات للموقع ده.',
        'The browser is blocking notifications for this site.',
      );
  String get remindersBlockedHint => _(
        'افتح إعدادات الموقع في المتصفح واسمح بالتنبيهات.',
        "Open the site's settings in your browser and allow notifications.",
      );
  String get remindersNeedOpenTab => _(
        'التنبيه بيوصل حتى لو التطبيق مقفول خالص.',
        'Reminders arrive even with the app fully closed.',
      );

  String remindBefore(int minutes) => isAr
      ? 'قبلها بـ $minutes دقيقة'
      : '$minutes min before';

  // تخصيص التنبيه / notification customization
  String get notificationCustomize => _('تخصيص التنبيه', 'Customize notifications');
  String get notificationSound => _('الصوت', 'Sound');
  String get notificationVibrate => _('الاهتزاز', 'Vibration');
  String get notificationDefaultLead =>
      _('المدة الافتراضية لمحاضرة جديدة', 'Default lead time for a new lecture');
  String get notificationCustomTextLabel => _('نص التنبيه', 'Reminder text');
  String get notificationCustomTextHint => _(
        'سيب فاضي عشان الصيغة الافتراضية. تقدر تستخدم: {minutes} {location} {lecture} {lecturer}',
        'Leave empty for the default wording. You can use: {minutes} {location} {lecture} {lecturer}',
      );
  String get notificationCustomTextReset => _('رجّع الافتراضي', 'Reset to default');
  String get notificationSaved => _('اتحفظ.', 'Saved.');
  String get sendTestNotification => _('جرّب الإشعار الآن', 'Send a test notification');
  String testNotificationResult(int devicesReached) => devicesReached > 0
      ? _(
          'التنبيه المحلي طلع، ووصل Push لـ $devicesReached جهاز.',
          'The local reminder fired, and push reached $devicesReached device(s).',
        )
      : _(
          'التنبيه المحلي طلع، بس مفيش اشتراك Push شغال — جرّب تقفل وتفتح التنبيهات.',
          'The local reminder fired, but there is no active push subscription — try turning reminders off and back on.',
        );
  String get testLectureTitle => _('محاضرة تجريبية', 'Test lecture');
  String get testLectureLocation => _('قاعة تجريبية', 'Test hall');
  String get testLectureLecturer => _('د. تجريبي', 'Dr. Test');

  /// نص التنبيه نفسه — بيتقرا وهو طالع من المتصفح.
  /// The reminder's own text, read as it comes out of the browser.
  String reminderBody(int minutes) {
    if (minutes <= 0) return isAr ? 'بدأت دلوقتي' : 'Starting now';
    if (!isAr) return 'In $minutes min';
    if (minutes == 1) return 'بعد دقيقة';
    if (minutes == 2) return 'بعد دقيقتين';
    if (minutes <= 10) return 'بعد $minutes دقايق';
    return 'بعد $minutes دقيقة';
  }

  /// "بعد ساعتين" مش "بعد 2 ساعة" — العربي بيغيّر الصيغة مع العدد.
  /// "In two hours" rather than "in 2 hour": Arabic changes form with the
  /// count.
  String inHours(int n) {
    if (!isAr) return n == 1 ? 'In an hour' : 'In $n h';
    if (n == 1) return 'بعد ساعة';
    if (n == 2) return 'بعد ساعتين';
    if (n <= 10) return 'بعد $n ساعات';
    return 'بعد $n ساعة';
  }

  String inDays(int n) {
    if (!isAr) return n == 1 ? 'Tomorrow' : 'In $n days';
    if (n == 1) return 'بكرة';
    if (n == 2) return 'بعد يومين';
    if (n <= 10) return 'بعد $n أيام';
    return 'بعد $n يوم';
  }

  /// أسماء الأيام — 1 = الاتنين زي `DateTime.weekday`.
  /// Day names; 1 = Monday, as in `DateTime.weekday`.
  String weekdayName(int weekday) {
    const ar = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    const en = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final index = (weekday - 1).clamp(0, 6);
    return isAr ? ar[index] : en[index];
  }

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

  /// اسم مختصر للشريط السفلي — "Summarize" بتتقسم لسطرين في خانة ضيقة.
  /// A short name for the bottom bar; "Summarize" wraps in a narrow slot.
  String get summarizeNav => _('التلخيص', 'Summary');

  /// الفاصلة بتختلف بين اللغتين.
  /// The comma differs between the two languages.
  String get comma => _('، ', ', ');
  String get styleSamples => _('أمثلة أسلوبك', 'Your style');
  String get samplesEmptyHint => _(
        'ضيف تلخيص واحد بخطك، والباقي هيتبني عليه.',
        'Add one summary in your own words; the rest builds on it.',
      );
  String get samplesListHint => _(
        'كل ما تضيف أمثلة، التقليد بيبقى أقرب لأسلوبك.',
        'The more examples you add, the closer the imitation gets.',
      );
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

  // ------------------------------------------------------- الصوت / audio
  String get recordLecture => _('سجّل المحاضرة', 'Record lecture');
  String get uploadAudio => _('ارفع تسجيل', 'Upload audio');
  String get supportedAudio =>
      _('mp3 · m4a · wav · ogg · aac', 'mp3 · m4a · wav · ogg · aac');
  String get recording => _('بيسجّل', 'Recording');
  String get recordingNoun => _('تسجيل', 'Recording');
  String get recordingPaused => _('التسجيل متوقف', 'Paused');
  String get stopRecording => _('خلّصت', 'Finish');
  String get discardRecording => _('إلغاء التسجيل', 'Discard');
  String get recordingSaved => _('التسجيل اتحفظ', 'Recording added');
  String get recordingEmpty =>
      _('مفيش صوت اتسجّل', 'Nothing was recorded');
  String get recordingLimitHit => _(
        'وصلت لأقصى مدة للتسجيل الواحد.',
        'That is the longest a single recording goes.',
      );

  /// المصادر اللي هيتلخص منها — ملفات وتسجيلات مع بعض.
  /// The sources the summary is built from: files and recordings together.
  String get lectureSources => _('مصادر المحاضرة', 'Lecture sources');
  String get sourcesHint => _(
        'ضيف اللي عندك: تسجيل المحاضرة، السلايدات، أو الاتنين مع بعض.',
        'Add what you have: the recording, the slides, or both together.',
      );
  String get removeSource => _('شيل المصدر', 'Remove');

  String get viewTranscript => _('اعرض التفريغ', 'View transcript');
  String get transcribedLabel => _('اتفرّغ', 'Transcribed');
  String get transcriptEmpty => _(
        'التسجيل مفيهوش كلام واضح.',
        'No speech was found in the recording.',
      );

  /// "بيفرّغ المقطع 2 من 5" — الرقم بيطمّن إن في تقدّم في الانتظار الطويل.
  /// "Transcribing part 2 of 5" — the number shows progress through a wait
  /// that is otherwise silent.
  /// الرفع بيتعرض لوحده: على نت بطيء هو أطول من التفريغ نفسه بكتير.
  /// Uploading shows on its own: on a slow line it far outlasts the
  /// transcription itself.
  String uploadingPart(int part, int total) => isAr
      ? 'بيرفع المقطع $part من $total... (حسب سرعة النت)'
      : 'Uploading part $part of $total... (depends on your connection)';

  String transcribingPart(int part, int total) => isAr
      ? 'بيفرّغ المقطع $part من $total...'
      : 'Transcribing part $part of $total...';

  String audioParts(int n) {
    if (!isAr) return n == 1 ? '1 part' : '$n parts';
    if (n == 1) return 'مقطع واحد';
    if (n == 2) return 'مقطعين';
    if (n <= 10) return '$n مقاطع';
    return '$n مقطع';
  }

  String wordCount(int n) {
    if (!isAr) return n == 1 ? '1 word' : '$n words';
    if (n == 1) return 'كلمة واحدة';
    if (n == 2) return 'كلمتين';
    if (n <= 10) return '$n كلمات';
    return '$n كلمة';
  }

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
  String get modelSettingsHint => _(
        'اختار الموديل اللي بيلخّص، أو سيبه تلقائي.',
        'Pick the model that summarizes, or leave it automatic.',
      );
  String get appearance => _('المظهر', 'Appearance');
  String get appearanceHint => _(
        'اللغة والوضع وحجم الخط.',
        'Language, theme, and text size.',
      );
  String get studyTools => _('أدوات المذاكرة', 'Study tools');
  String get studyToolsHint => _(
        'إعدادات المؤقت والتلخيص.',
        'Timer and summarizing settings.',
      );
  String get styleSamplesHint => _(
        'التلخيصات اللي التطبيق بيتعلّم منها شكل كتابتك.',
        'The summaries the app learns your handwriting style from.',
      );
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
  /// تحذير تحت الاختيار اليدوي: القايمة من جوجل مش بتقول مفتاحك المجاني
  /// شغال على أنهي موديل منها بالظبط.
  /// A warning under manual picking: Google's list does not say which of
  /// them a free key actually works on.
  String get manualModelHint => _(
        'القايمة دي كل الموديلات اللي مفتاحك يقدر يشوفها — مش كلها بالضرورة '
            'شغالة على الخطة المجانية. لو موديل معين بيرجّع خطأ الحصة على '
            'طول، جرب غيره من هنا أو ارجع للاختيار التلقائي فوق.',
        "This list is every model your key can see — not all of them "
            "necessarily work on the free plan. If one keeps returning a "
            "quota error, try another from here or switch back to automatic "
            "above.",
      );
  String get autoLabel => _('تلقائي', 'Automatic');

  /// قسم مفتاح Gemini الشخصي في إعدادات التلخيص.
  /// The personal Gemini key section in the summarize settings.
  String get personalKeyTitle => _('مفتاحك الشخصي', 'Your personal key');
  String get personalKeyHint => _(
        'لو حطيت مفتاح Gemini بتاعك، هيتستخدم بدل المفتاح المشترك — '
            'واستهلاكك هيبقى من حصتك انت بس، مش متشارك مع باقي المستخدمين.',
        "If you set your own Gemini key, it is used instead of the shared "
            "one — your usage spends from your own quota, not shared with "
            "other users.",
      );
  String get personalKeySaved =>
      _('مفتاح شخصي محفوظ', 'A personal key is saved');
  String get personalKeyPlaceholder =>
      _('الصق مفتاح Gemini هنا', 'Paste your Gemini key here');
  String get savePersonalKey => _('احفظ المفتاح', 'Save key');
  String get verifyingPersonalKey =>
      _('بيتأكد إن المفتاح شغال...', 'Checking the key works...');
  String get personalKeyVerified =>
      _('اتحفظ واتأكد إنه شغال فعليًا', 'Saved and confirmed working');
  /// المفتاح اتمسح تاني لأن الاختبار فشل — عشان المستخدم ميعتمدش على مفتاح
  /// عاطل من غير ما يعرف.
  /// The key was deleted again because the test failed — so the user
  /// doesn't unknowingly rely on a broken key.
  String personalKeyTestFailed(String detail) => _(
        'المفتاح ده مش شغال، فمسحناه تاني: $detail',
        "This key doesn't work, so it was removed again: $detail",
      );
  String get deletePersonalKey => _('امسح المفتاح', 'Delete key');
  String get personalKeyDeleted =>
      _('اتمسح — هيرجع يستخدم المفتاح المشترك', 'Deleted — back to the shared key');
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
