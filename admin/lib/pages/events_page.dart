import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../shell.dart';

/// كل اللي حصل، الأحدث فوق: أكواد اتعملت واتفعّلت واتعدّلت، وحسابات اتعدّلت.
/// Everything that happened, newest first: codes made, redeemed and edited,
/// and accounts edited.
class EventsPage extends StatelessWidget {
  const EventsPage({super.key, required this.data});

  final Dashboard data;

  String _describe(EventRow e) {
    final code = data.codeById[e.codeId]?.code;
    final user = data.userById[e.userId]?.email;
    final d = e.detail;
    return switch (e.action) {
      'created' => 'اتعمل كود ${code ?? ''} (${d['days']} يوم، ${kindLabel('${d['kind']}')})',
      'redeemed' => '${user ?? 'حساب'} فعّل ${code ?? 'كود'} — لحد ${day(DateTime.tryParse('${d['ends_at']}')?.toLocal())}',
      'updated' => 'الكود ${code ?? ''}: ${_changes(d)}',
      'user_updated' => '${user ?? 'حساب'}: ${_changes(d)}',
      _ => e.action,
    };
  }

  String _changes(Map<String, dynamic> d) => [
        if (d['disabled'] == true) 'اتقفل',
        if (d['disabled'] == false) 'اتفتح',
        if (d['days'] != null) 'بقى ${d['days']} يوم',
        if (d['add_days'] != null) 'اتزوّد ${d['add_days']} يوم',
        if (d['ends_at'] != null) 'النهاية ${day(DateTime.tryParse('${d['ends_at']}')?.toLocal())}',
        if (d['forever'] == true) 'من غير نهاية',
        if (d['note'] != null) 'ملاحظة: ${d['note']}',
      ].join('، ');

  IconData _icon(String action) => switch (action) {
        'created' => Icons.add_circle_outline_rounded,
        'redeemed' => Icons.key_rounded,
        'user_updated' => Icons.manage_accounts_outlined,
        _ => Icons.edit_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return PageFrame(
      children: [
        if (data.events.isEmpty)
          const EmptyNote('لسه محصلش حاجة.')
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < data.events.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(_icon(data.events[i].action), color: brand),
                    title: Text(_describe(data.events[i])),
                    subtitle: Text(dayTime(data.events[i].at), style: muted),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
