import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../dashboard/dashboard_page.dart';
import '../flashcards/flashcards_page.dart';
import '../notes/notes_page.dart';
import '../schedule/reminder_service.dart';
import '../schedule/schedule_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import '../subjects/subjects_page.dart';
import '../summarize/summarize_page.dart';
import '../tasks/tasks_page.dart';
import '../timer/pomodoro_page.dart';

/// أقسام التطبيق.
/// The app's sections.
///
/// الترتيب هنا هو ترتيب الشريط الجانبي على الشاشة العريضة. الشريط السفلي على
/// الموبايل له قايمته الخاصة في [_barSections].
/// This order is the rail's order on a wide screen. The phone's bottom bar has
/// its own list in [_barSections].
enum AppSection {
  dashboard(Icons.cottage_rounded, Icons.cottage_outlined),
  schedule(Icons.calendar_month_rounded, Icons.calendar_month_outlined),
  timer(Icons.timelapse_rounded, Icons.timelapse_outlined),
  tasks(Icons.task_alt_rounded, Icons.radio_button_unchecked_rounded),
  summarize(Icons.auto_awesome_rounded, Icons.auto_awesome_outlined),
  flashcards(Icons.style_rounded, Icons.style_outlined),
  notes(Icons.article_rounded, Icons.article_outlined),
  stats(Icons.insights_rounded, Icons.insights_outlined),
  subjects(Icons.folder_rounded, Icons.folder_outlined);

  const AppSection(this.selectedIcon, this.icon);

  final IconData selectedIcon;
  final IconData icon;

  /// الاسم في الشريط السفلي — أقصر عشان ما يتقسمش على شاشة ضيقة.
  /// The bottom-bar name, kept short so it does not wrap on a narrow screen.
  String navLabel(AppL10n l) =>
      this == AppSection.summarize ? l.summarizeNav : label(l);

  String label(AppL10n l) => switch (this) {
        AppSection.dashboard => l.dashboard,
        AppSection.schedule => l.schedule,
        AppSection.timer => l.timer,
        AppSection.tasks => l.tasks,
        AppSection.summarize => l.summarize,
        AppSection.flashcards => l.flashcards,
        AppSection.notes => l.notes,
        AppSection.stats => l.stats,
        AppSection.subjects => l.subjects,
      };

  Widget get page => switch (this) {
        AppSection.dashboard => const DashboardPage(),
        AppSection.schedule => const SchedulePage(),
        AppSection.timer => const PomodoroPage(),
        AppSection.tasks => const TasksPage(),
        AppSection.summarize => const SummarizePage(),
        AppSection.flashcards => const FlashcardsPage(),
        AppSection.notes => const NotesPage(),
        AppSection.stats => const StatsPage(),
        AppSection.subjects => const SubjectsPage(),
      };
}

/// القسم المعروض دلوقتي — الصفحات بتغيره عشان تودّي بعضها.
/// The visible section; pages set it to navigate to each other.
class SectionNotifier extends Notifier<AppSection> {
  @override
  AppSection build() => AppSection.dashboard;

  void go(AppSection section) => state = section;
}

final sectionProvider =
    NotifierProvider<SectionNotifier, AppSection>(SectionNotifier.new);

/// أقسام الشريط السفلي على الموبايل، قبل زرار "المزيد".
/// The sections in the phone's bottom bar, before the "more" button.
///
/// قايمة لوحدها مش أول أربعة في الترتيب: الشريط الجانبي بيترتب بالمنطق (يوميّ
/// الأول)، والشريط السفلي بيترتب بالاستخدام. لما الجدول اتضاف، أول أربعة كانوا
/// هيزقّوا التلخيص لجوّه "المزيد" — وهو من أكتر حاجة بتتفتح.
/// Its own list rather than the first four of the order: the rail is ordered by
/// what makes sense, the bottom bar by what gets used. When the timetable was
/// added, taking the first four would have pushed summarizing into "more" —
/// and that is among the most opened screens.
const _barSections = [
  AppSection.dashboard,
  AppSection.schedule,
  AppSection.summarize,
  AppSection.tasks,
];

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    final hasRail = Breakpoints.hasRail(context);

    // متابعة التنبيهات من هنا: من غير حد ماسكها، المؤقت بتاعها ما بيشتغلش
    // أصلاً وما فيش تنبيه بيطلع.
    // The reminders are watched here: with nobody holding the service its timer
    // never runs and no reminder ever fires.
    ref.watch(reminderServiceProvider);

    final content = Scaffold(
      appBar: _SectionBar(section: section, showQuickActions: !hasRail),
      // الانتقال بين الأقسام بتلاشٍ خفيف: كفاية إنه يوضّح إن الصفحة اتغيرت،
      // من غير ما يتحوّل لانتظار.
      // A light cross-fade between sections: enough to show the page changed,
      // without turning navigation into waiting.
      body: AnimatedSwitcher(
        duration: Motion.normal,
        switchInCurve: Motion.ease,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.012),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(section), child: section.page),
      ),
      bottomNavigationBar: hasRail ? null : _BottomBar(section: section),
    );

    if (!hasRail) return content;

    return Row(
      children: [
        _SideRail(section: section),
        Expanded(child: content),
      ],
    );
  }
}

/// شريط علوي بسيط: اسم القسم، وإجراءات سريعة على الموبايل بس.
/// A plain top bar: the section's name, with quick actions on phones only.
class _SectionBar extends ConsumerWidget implements PreferredSizeWidget {
  const _SectionBar({required this.section, required this.showQuickActions});

  final AppSection section;
  final bool showQuickActions;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;

    return AppBar(
      title: Text(section.label(l)),
      actions: showQuickActions
          ? [
              IconButton(
                tooltip: l.language,
                onPressed: ref.read(settingsProvider.notifier).toggleLanguage,
                icon: const Icon(Icons.translate_rounded),
              ),
              IconButton(
                tooltip: l.settings,
                onPressed: () => _openSettings(context),
                icon: const Icon(Icons.tune_rounded),
              ),
              const SizedBox(width: Insets.sm),
            ]
          : null,
    );
  }
}

void _openSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
  );
}

/// الشريط الجانبي للشاشات العريضة: هوية، أقسام، وإعدادات في الأسفل.
/// The wide-screen rail: identity, sections, and settings at the foot.
class _SideRail extends ConsumerWidget {
  const _SideRail({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: BorderDirectional(
          end: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const _RailBrand(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.md,
                  vertical: Insets.sm,
                ),
                children: [
                  for (final s in AppSection.values)
                    _RailItem(
                      section: s,
                      selected: s == section,
                      onTap: () =>
                          ref.read(sectionProvider.notifier).go(s),
                    ),
                ],
              ),
            ),
            Divider(color: scheme.outlineVariant, height: 1),
            Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () => _openSettings(context),
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: Text(l.settings),
                      style: TextButton.styleFrom(
                        alignment: AlignmentDirectional.centerStart,
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.language,
                    onPressed:
                        ref.read(settingsProvider.notifier).toggleLanguage,
                    icon: const Icon(Icons.translate_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final l = context.l;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Insets.xl, Insets.xxl, Insets.xl, Insets.lg),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [palette.heroStart, palette.heroEnd],
              ),
              borderRadius: Radii.all(Radii.md),
            ),
            child: Icon(Icons.auto_stories_rounded,
                color: palette.onHero, size: 20),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(height: 1.2),
                ),
                Text(
                  l.workspace,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final AppSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xs),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: Radii.all(Radii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.all(Radii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.md,
              vertical: Insets.md,
            ),
            child: Row(
              children: [
                Icon(selected ? section.selectedIcon : section.icon,
                    size: 21, color: fg),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Text(
                    section.label(context.l),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: fg,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final inBar = _barSections.contains(section);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: BorderDirectional(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: NavigationBar(
        selectedIndex:
            inBar ? _barSections.indexOf(section) : _barSections.length,
        onDestinationSelected: (i) {
          if (i < _barSections.length) {
            ref.read(sectionProvider.notifier).go(_barSections[i]);
          } else {
            _showMoreSheet(context, ref);
          }
        },
        destinations: [
          for (final s in _barSections)
            NavigationDestination(
              icon: Icon(s.icon),
              selectedIcon: Icon(s.selectedIcon),
              label: s.navLabel(l),
            ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: inBar ? l.more : section.navLabel(l),
          ),
        ],
      ),
    );
  }

  void _showMoreSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              Insets.lg, 0, Insets.lg, Insets.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    bottom: Insets.md, right: Insets.sm, left: Insets.sm),
                child: Text(ctx.l.more,
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final s
                  in AppSection.values.where((s) => !_barSections.contains(s)))
                ListTile(
                  leading: Icon(s == section ? s.selectedIcon : s.icon),
                  title: Text(s.label(ctx.l)),
                  selected: s == section,
                  selectedTileColor:
                      Theme.of(ctx).colorScheme.primaryContainer,
                  onTap: () {
                    ref.read(sectionProvider.notifier).go(s);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
