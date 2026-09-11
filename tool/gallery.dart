// أداة تطوير مش جزء من التطبيق: بتفتح أي شاشة ببيانات وهمية عشان نراجع
// الشكل في اللغتين والوضعين من غير ما نسجّل دخول أو نعتمد على السيرفر.
// A development tool, not part of the app: it opens any screen with stub data
// so the design can be reviewed in both languages and themes without signing
// in or depending on the server.
//
// flutter build web -t tool/gallery.dart
// ثم: ?screen=tasks&lang=en&theme=dark&scale=1.3
// then: ?screen=tasks&lang=en&theme=dark&scale=1.3
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:study_assistant/core/app_theme.dart';
import 'package:study_assistant/core/l10n.dart';
import 'package:study_assistant/data/providers.dart';
import 'package:study_assistant/features/auth/login_page.dart';
import 'package:study_assistant/features/flashcards/review_page.dart';
import 'package:study_assistant/features/home/home_shell.dart';
import 'package:study_assistant/features/settings/settings_page.dart';
import 'package:study_assistant/features/summarize/style_samples_page.dart';
import 'package:study_assistant/models/models.dart';

// النهارده الحقيقي عشان "متأخر" و"النهارده" يطلعوا صح في المعاينة.
// The real today, so "overdue" and "today" land correctly in the preview.
final _now = DateTime.now();

final _subjects = [
  Subject(
      id: 's1',
      name: 'الفيزياء',
      color: const Color(0xFF2F6F8F),
      createdAt: _now),
  Subject(
      id: 's2',
      name: 'الكيمياء العضوية',
      color: const Color(0xFFA4573B),
      createdAt: _now),
  Subject(
      id: 's3', name: 'الأحياء', color: const Color(0xFF3F7A4E), createdAt: _now),
];

final _tasks = [
  Task(
    id: 't1',
    title: 'حل مسائل الفصل الرابع',
    subjectId: 's1',
    dueDate: _now.subtract(const Duration(days: 2)),
    priority: TaskPriority.high,
    isDone: false,
    createdAt: _now,
  ),
  Task(
    id: 't2',
    title: 'مراجعة تفاعلات الألدهيدات والكيتونات قبل السكشن',
    subjectId: 's2',
    dueDate: _now,
    priority: TaskPriority.medium,
    isDone: false,
    createdAt: _now,
  ),
  Task(
    id: 't3',
    title: 'تلخيص محاضرة الانقسام الميوزي',
    subjectId: 's3',
    dueDate: _now.add(const Duration(days: 3)),
    priority: TaskPriority.low,
    isDone: false,
    createdAt: _now,
  ),
  Task(
    id: 't4',
    title: 'تسليم تقرير المعمل',
    priority: TaskPriority.medium,
    isDone: true,
    completedAt: _now,
    createdAt: _now,
  ),
];

final _cards = [
  Flashcard(
    id: 'c1',
    front: 'إيه الفرق بين السرعة والسرعة المتجهة؟',
    back: 'السرعة كمية قياسية، والسرعة المتجهة ليها اتجاه.',
    subjectId: 's1',
    dueAt: _now.subtract(const Duration(hours: 3)),
    createdAt: _now,
  ),
  Flashcard(
    id: 'c2',
    front: 'ما هي مجموعة الكربونيل؟',
    back: 'ذرة كربون مرتبطة برابطة مزدوجة مع أكسجين.',
    subjectId: 's2',
    dueAt: _now.add(const Duration(days: 2)),
    createdAt: _now,
  ),
  Flashcard(
    id: 'c3',
    front: 'مراحل الانقسام الميتوزي بالترتيب',
    back: 'تمهيدي، استوائي، انفصالي، نهائي.',
    subjectId: 's3',
    dueAt: _now.subtract(const Duration(days: 1)),
    createdAt: _now,
  ),
];

final _notes = [
  Note(
    id: 'n1',
    title: 'قوانين نيوتن',
    body: 'الجسم الساكن يفضل ساكن والمتحرك يفضل متحرك بسرعة ثابتة ما لم تؤثر '
        'عليه قوة خارجية. القوة تساوي الكتلة في العجلة، ولكل فعل رد فعل مساوٍ '
        'له في المقدار ومضاد في الاتجاه.',
    subjectId: 's1',
    createdAt: _now,
    updatedAt: _now,
  ),
  Note(
    id: 'n2',
    title: 'ملخص المحاضرة الثالثة',
    body: 'الأحماض الكربوكسيلية وتفاعلات الأسترة، مع أمثلة على التسمية.',
    subjectId: 's2',
    createdAt: _now,
    updatedAt: _now.subtract(const Duration(days: 4)),
  ),
  Note(
    id: 'n3',
    title: '',
    body: 'فكرة سريعة: أذاكر الأحياء بالرسم بدل الحفظ.',
    createdAt: _now,
    updatedAt: _now.subtract(const Duration(days: 9)),
  ),
];

final _sessions = [
  for (var i = 0; i < 7; i++)
    StudySession(
      id: 'ss$i',
      subjectId: _subjects[i % 3].id,
      startedAt: _now.subtract(Duration(days: i)),
      durationSeconds: (25 + i * 7) * 60,
    ),
];

final _schedule = [
  ScheduleEntry(
    id: 'l1',
    title: 'فيزياء 2 — محاضرة',
    weekday: 6,
    startMinutes: 9 * 60,
    endMinutes: 11 * 60,
    location: 'مدرج 3',
    lecturer: 'د. سمير',
    subjectId: 's1',
    remindMinutes: 15,
    createdAt: _now,
  ),
  ScheduleEntry(
    id: 'l2',
    title: 'كيمياء عضوية — سكشن',
    weekday: 6,
    startMinutes: 11 * 60 + 30,
    endMinutes: 13 * 60,
    location: 'معمل 2',
    subjectId: 's2',
    createdAt: _now,
  ),
  ScheduleEntry(
    id: 'l3',
    title: 'أحياء',
    weekday: 1,
    startMinutes: 10 * 60,
    endMinutes: 12 * 60,
    location: 'قاعة 7',
    lecturer: 'د. منى',
    subjectId: 's3',
    remindMinutes: 30,
    createdAt: _now,
  ),
  ScheduleEntry(
    id: 'l4',
    title: 'إحصاء',
    weekday: 3,
    startMinutes: 13 * 60,
    location: 'مدرج 1',
    createdAt: _now,
  ),
];

final _samples = [
  StyleSample(
    id: 'y1',
    title: 'تلخيص الفصل الأول',
    body: 'العنوان بيتكتب في النص وتحته خط. كل فكرة في نقطة، والمصطلح المهم '
        'بيتحاط في إطار. الرسم البياني بيتحط على اليمين.',
    subjectId: 's1',
    createdAt: _now,
  ),
  StyleSample(
    id: 'y2',
    title: 'ملخص الروابط',
    body: 'ثلاث خانات: التعريف، المثال، والملاحظة. الألوان: أزرق للعناوين '
        'وأحمر للتحذيرات.',
    createdAt: _now,
  ),
];

/// قسم مبدئي ثابت عشان نفتح أي صفحة مباشرة من الرابط.
/// A fixed starting section so any page can be opened straight from the URL.
class _FixedSection extends SectionNotifier {
  _FixedSection(this.initial);

  final AppSection initial;

  @override
  AppSection build() => initial;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final q = Uri.base.queryParameters;
  final screen = q['screen'] ?? 'dashboard';
  final lang = q['lang'] ?? 'ar';
  final theme = q['theme'] ?? 'light';
  final scale = double.tryParse(q['scale'] ?? '1') ?? 1.0;

  // الإعدادات بتتقرا من نفس المخزن اللي التطبيق بيستخدمه، فبنكتب فيه الأول.
  // Settings come from the same store the app uses, so we write them first.
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('lang', lang);
  await prefs.setString('theme', theme);
  await prefs.setDouble('ui_scale', scale);

  final section = AppSection.values.firstWhere(
    (s) => s.name == screen,
    orElse: () => AppSection.dashboard,
  );

  runApp(
    ProviderScope(
      overrides: [
        subjectsProvider.overrideWith((ref) async => _subjects),
        tasksProvider.overrideWith((ref) async => _tasks),
        notesProvider.overrideWith((ref) async => _notes),
        cardsProvider.overrideWith((ref) async => _cards),
        sessionsProvider.overrideWith((ref) async => _sessions),
        weeklyReviewsProvider.overrideWith((ref) async => 24),
        styleSamplesProvider.overrideWith((ref) async => _samples),
        styleProfilesProvider.overrideWith((ref) async => const {}),
        scheduleProvider.overrideWith((ref) async => _schedule),
        currentUserProvider.overrideWith((ref) => const User(
              id: 'demo',
              appMetadata: {},
              userMetadata: {'display_name': 'عبدالرحمن'},
              aud: 'authenticated',
              email: 'me@example.com',
              createdAt: '2026-01-01T00:00:00Z',
            )),
        sectionProvider.overrideWith(() => _FixedSection(section)),
      ],
      child: _GalleryApp(screen: screen, lang: lang, theme: theme, scale: scale),
    ),
  );
}

class _GalleryApp extends StatelessWidget {
  const _GalleryApp({
    required this.screen,
    required this.lang,
    required this.theme,
    required this.scale,
  });

  final String screen;
  final String lang;
  final String theme;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final isAr = lang == 'ar';

    return MaterialApp(
      title: 'Gallery',
      debugShowCheckedModeBanner: false,
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppL10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: theme == 'dark' ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(isAr),
      darkTheme: AppTheme.dark(isAr),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: switch (screen) {
        'login' => const LoginPage(),
        'settings' => const SettingsPage(),
        'samples' => const StyleSamplesPage(),
        'review' => ReviewPage(queue: _cards),
        _ => const HomeShell(),
      },
    );
  }
}

