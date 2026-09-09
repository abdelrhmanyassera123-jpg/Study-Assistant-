import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../dashboard/dashboard_page.dart';
import '../flashcards/flashcards_page.dart';
import '../notes/notes_page.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import '../subjects/subjects_page.dart';
import '../summarize/summarize_page.dart';
import '../tasks/tasks_page.dart';
import '../timer/pomodoro_page.dart';

/// أقسام التطبيق. أول 4 بيظهروا في الشريط السفلي، والباقي جوه "المزيد".
/// The app's sections. The first four sit in the bottom bar; the rest live
/// behind a "more" sheet on narrow screens; the rail shows them all.
enum AppSection {
  dashboard(Icons.home_rounded, Icons.home_outlined),
  timer(Icons.timer_rounded, Icons.timer_outlined),
  tasks(Icons.checklist_rounded, Icons.checklist_outlined),
  flashcards(Icons.style_rounded, Icons.style_outlined),
  summarize(Icons.auto_awesome_rounded, Icons.auto_awesome_outlined),
  notes(Icons.description_rounded, Icons.description_outlined),
  stats(Icons.insights_rounded, Icons.insights_outlined),
  subjects(Icons.folder_rounded, Icons.folder_outlined);

  const AppSection(this.selectedIcon, this.icon);

  final IconData selectedIcon;
  final IconData icon;

  String label(AppL10n l) => switch (this) {
        AppSection.dashboard => l.dashboard,
        AppSection.timer => l.timer,
        AppSection.tasks => l.tasks,
        AppSection.flashcards => l.flashcards,
        AppSection.summarize => l.summarize,
        AppSection.notes => l.notes,
        AppSection.stats => l.stats,
        AppSection.subjects => l.subjects,
      };

  Widget get page => switch (this) {
        AppSection.dashboard => const DashboardPage(),
        AppSection.timer => const PomodoroPage(),
        AppSection.tasks => const TasksPage(),
        AppSection.flashcards => const FlashcardsPage(),
        AppSection.summarize => const SummarizePage(),
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

/// عدد الأقسام اللي بتظهر في الشريط السفلي قبل زرار "المزيد".
const _barCount = 4;

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sectionProvider);
    final l = context.l;
    final isWide = MediaQuery.sizeOf(context).width >= 840;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(section.label(l)),
        actions: [
          IconButton(
            tooltip: l.language,
            onPressed: ref.read(settingsProvider.notifier).toggleLanguage,
            icon: const Icon(Icons.translate_rounded),
          ),
          IconButton(
            tooltip: l.settings,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: section.page,
      bottomNavigationBar: isWide ? null : _BottomBar(section: section),
    );

    if (!isWide) return scaffold;

    return Row(
      children: [
        NavigationRail(
          selectedIndex: section.index,
          onDestinationSelected: (i) =>
              ref.read(sectionProvider.notifier).go(AppSection.values[i]),
          labelType: NavigationRailLabelType.all,
          groupAlignment: -0.6,
          destinations: [
            for (final s in AppSection.values)
              NavigationRailDestination(
                icon: Icon(s.icon),
                selectedIcon: Icon(s.selectedIcon),
                label: Text(s.label(l)),
              ),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: scaffold),
      ],
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final inBar = section.index < _barCount;

    return NavigationBar(
      selectedIndex: inBar ? section.index : _barCount,
      onDestinationSelected: (i) {
        if (i < _barCount) {
          ref.read(sectionProvider.notifier).go(AppSection.values[i]);
        } else {
          _showMoreSheet(context, ref);
        }
      },
      destinations: [
        for (final s in AppSection.values.take(_barCount))
          NavigationDestination(
            icon: Icon(s.icon),
            selectedIcon: Icon(s.selectedIcon),
            label: s.label(l),
          ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz_rounded),
          label: inBar ? (l.isAr ? 'المزيد' : 'More') : section.label(l),
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in AppSection.values.skip(_barCount))
              ListTile(
                leading: Icon(s == section ? s.selectedIcon : s.icon),
                title: Text(s.label(ctx.l)),
                selected: s == section,
                onTap: () {
                  ref.read(sectionProvider.notifier).go(s);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}
