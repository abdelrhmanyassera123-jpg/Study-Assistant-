import 'package:flutter/material.dart';

import '../common.dart';
import '../shell.dart';

/// نظرة سريعة: كام واحد شغال، والأكواد اللي فاضلة، واللي بيخلص قريب،
/// والتفعيلات واستخدام الذكاء الاصطناعي آخر أسبوعين.
/// A quick look: how many are live, the codes left, who ends soon, and the
/// redemptions and AI use over the last two weeks.
class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key, required this.data, required this.onOpenCodes});

  final Dashboard data;
  final VoidCallback onOpenCodes;

  @override
  Widget build(BuildContext context) {
    final users = data.users;
    final now = DateTime.now();
    final paying = users.where((u) => u.active && u.source == 'code').length;
    final legacy = users.where((u) => u.active && u.source == 'legacy').length;
    final unused = data.codes.where((c) => !c.used && !c.disabled && !c.lapsed).length;
    final soon = users
        .where((u) => u.active && u.endsAt != null && u.endsAt!.difference(now).inDays < 3)
        .toList()
      ..sort((a, b) => a.endsAt!.compareTo(b.endsAt!));
    final noSub = users.where((u) => u.source == null).toList();

    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 13; i >= 0; i--) today.subtract(Duration(days: i))];
    final redemptions = {
      for (final d in days)
        d: data.codes.where((c) {
          final r = c.redeemedAt;
          return r != null && r.year == d.year && r.month == d.month && r.day == d.day;
        }).length,
    };
    final usage = {for (final d in days) d: data.usage[d] ?? 0};

    return PageFrame(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final perRow = c.maxWidth >= 720 ? 4 : 2;
            final w = (c.maxWidth - (perRow - 1) * 12) / perRow;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (label, value, icon) in [
                  ('مشتركين بكود', paying, Icons.workspace_premium_outlined),
                  ('قديم مجاني', legacy, Icons.verified_outlined),
                  ('أكواد لسه ما اتستخدمتش', unused, Icons.key_outlined),
                  ('بيخلصوا خلال 3 أيام', soon.length, Icons.timer_outlined),
                ])
                  SizedBox(width: w, child: _Stat(label: label, value: value, icon: icon)),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (noSub.isNotEmpty) ...[
          Card(
            color: Colors.orange.shade50,
            child: ListTile(
              leading: Icon(Icons.person_add_alt_rounded, color: Colors.orange.shade800),
              title: Text('${noSub.length} حساب جديد مستني كود'),
              subtitle: Text(noSub.take(3).map((u) => u.email).join('، ')),
              trailing: TextButton(onPressed: onOpenCodes, child: const Text('الأكواد')),
            ),
          ),
          const SizedBox(height: 16),
        ],
        _Bars(title: 'التفعيلات آخر 14 يوم', values: redemptions, color: brand),
        const SizedBox(height: 16),
        _Bars(title: 'استخدام الذكاء الاصطناعي آخر 14 يوم', values: usage, color: Colors.indigo.shade400),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('بيخلصوا قريب', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (soon.isEmpty)
                  const Text('محدش بيخلص خلال 3 أيام.')
                else
                  for (final u in soon)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(u.email, textDirection: TextDirection.ltr, textAlign: TextAlign.start),
                      trailing: StateChip(
                        u.daysLeft == 0 ? 'النهاردة' : 'فاضل ${u.daysLeft} يوم',
                        Colors.orange.shade800,
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.icon});

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: brand),
              const SizedBox(height: 10),
              Text('$value', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}

/// أعمدة بسيطة يوم بيوم، والرقم فوق كل عمود.
/// Simple day-by-day bars, each with its number on top.
class _Bars extends StatelessWidget {
  const _Bars({required this.title, required this.values, required this.color});

  final String title;
  final Map<DateTime, int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = values.values.fold<int>(0, (a, b) => a > b ? a : b);
    final small = Theme.of(context).textTheme.labelSmall;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 140,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final e in values.entries)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (e.value > 0) Text('${e.value}', style: small),
                            const SizedBox(height: 2),
                            Container(
                              height: top == 0 ? 2 : 2 + 96 * e.value / top,
                              decoration: BoxDecoration(
                                color: e.value == 0 ? color.withValues(alpha: 0.15) : color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${e.key.day}', style: small),
                          ],
                        ),
                      ),
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
