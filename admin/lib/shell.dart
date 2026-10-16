import 'package:flutter/material.dart';

import 'api.dart';
import 'common.dart';
import 'pages/codes_page.dart';
import 'pages/create_codes.dart';
import 'pages/events_page.dart';
import 'pages/overview_page.dart';
import 'pages/users_page.dart';

/// الداتا كلها بتتجاب مرة، وبتتجاب تاني بعد أي تعديل — الأرقام صغيرة (مئات
/// مش آلاف)، فده أبسط من إن كل صفحة تجيب لوحدها.
/// All the data is fetched at once, and again after any change. The numbers
/// are small (hundreds, not thousands), so this is simpler than each page
/// fetching its own.
class Dashboard {
  Dashboard(this.codes, this.users, this.events, this.usage)
      : userById = {for (final u in users) u.id: u},
        codeById = {for (final c in codes) c.id: c};

  final List<CodeRow> codes;
  final List<UserRow> users;
  final List<EventRow> events;
  final Map<DateTime, int> usage;
  final Map<String, UserRow> userById;
  final Map<String, CodeRow> codeById;
}

class AdminShell extends StatefulWidget {
  const AdminShell({super.key, required this.api, this.onSignOut});

  final AdminApi api;
  final Future<void> Function()? onSignOut;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  // ?page=1 بيفتح على الأكواد على طول — ينفع تحفظه في المفضلة.
  // ?page=1 opens straight on the codes, worth bookmarking.
  int _page = (int.tryParse(Uri.base.queryParameters['page'] ?? '') ?? 0).clamp(0, 3);
  late Future<Dashboard> _data = _load();

  Future<Dashboard> _load() async {
    final api = widget.api;
    final results = await Future.wait([api.codes(), api.users(), api.events(), api.usage()]);
    return Dashboard(
      results[0] as List<CodeRow>,
      results[1] as List<UserRow>,
      results[2] as List<EventRow>,
      results[3] as Map<DateTime, int>,
    );
  }

  Future<void> reload() async {
    final next = _load();
    setState(() => _data = next);
    await next;
  }

  /// بينفّذ تعديل، ويعرض الخطأ لو فشل، وبعدين يجيب الداتا من الأول.
  /// Runs a change, shows the failure if it fails, then fetches afresh.
  Future<void> act(Future<void> Function() change, {String? done}) async {
    try {
      await change();
      if (mounted && done != null) snack(context, done);
    } catch (e) {
      if (mounted) snack(context, errorText(e));
    }
    await reload();
  }

  Future<void> _create() async {
    final made = await showDialog<List<CodeRow>>(
      context: context,
      builder: (_) => CreateCodesDialog(api: widget.api),
    );
    if (made == null || !mounted) return;
    await reload();
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => MadeCodesDialog(codes: made));
  }

  static const _pages = [
    (icon: Icons.space_dashboard_outlined, selected: Icons.space_dashboard_rounded, label: 'الرئيسية'),
    (icon: Icons.key_outlined, selected: Icons.key_rounded, label: 'الأكواد'),
    (icon: Icons.people_outline_rounded, selected: Icons.people_rounded, label: 'المستخدمين'),
    (icon: Icons.history_rounded, selected: Icons.history_rounded, label: 'السجل'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;

    final body = FutureBuilder<Dashboard>(
      future: _data,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(errorText(snap.error!)),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: reload, child: const Text('جرّب تاني')),
              ],
            ),
          );
        }
        final data = snap.data;
        if (data == null) return const Center(child: CircularProgressIndicator());
        return switch (_page) {
          0 => OverviewPage(data: data, onOpenCodes: () => setState(() => _page = 1)),
          1 => CodesPage(data: data, api: widget.api, act: act),
          2 => UsersPage(data: data, api: widget.api, act: act),
          _ => EventsPage(data: data),
        };
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(tooltip: 'تحديث', onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
          if (widget.onSignOut != null)
            IconButton(tooltip: 'تسجيل خروج', onPressed: widget.onSignOut, icon: const Icon(Icons.logout_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _page <= 1
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('عمل أكواد'),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _page,
              onDestinationSelected: (i) => setState(() => _page = i),
              destinations: [
                for (final p in _pages)
                  NavigationDestination(icon: Icon(p.icon), selectedIcon: Icon(p.selected), label: p.label),
              ],
            ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _page,
                  onDestinationSelected: (i) => setState(() => _page = i),
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: Colors.transparent,
                  destinations: [
                    for (final p in _pages)
                      NavigationRailDestination(
                        icon: Icon(p.icon),
                        selectedIcon: Icon(p.selected),
                        label: Text(p.label),
                      ),
                  ],
                ),
                Expanded(child: body),
              ],
            )
          : body,
    );
  }
}

/// غلاف الصفحة: عرض أقصى ومسافات ثابتة.
/// A page's frame: a maximum width and steady spacing.
class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      );
}
