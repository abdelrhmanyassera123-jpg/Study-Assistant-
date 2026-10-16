import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../shell.dart';

enum _Filter { all, active, legacy, ended, none }

/// كل الحسابات — القديمة والجديدة — واشتراكاتهم، والتحكم في كل واحد مباشرة.
/// Every account, old and new, with its subscription and direct control
/// over each.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key, required this.data, required this.api, required this.act});

  final Dashboard data;
  final AdminApi api;
  final Future<void> Function(Future<void> Function() change, {String? done}) act;

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  _Filter _filter = _Filter.all;
  String _query = '';

  bool _matches(UserRow u) {
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.active => u.active,
      _Filter.legacy => u.source == 'legacy',
      _Filter.ended => u.source != null && !u.active,
      _Filter.none => u.source == null,
    };
    final q = _query.trim().toLowerCase();
    return ok && (q.isEmpty || u.email.toLowerCase().contains(q) || (u.code?.toLowerCase().contains(q) ?? false));
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.data.users.where(_matches).toList();

    return PageFrame(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (f, label) in [
              (_Filter.all, 'الكل'),
              (_Filter.active, 'شغال'),
              (_Filter.legacy, 'قديم مجاني'),
              (_Filter.ended, 'خلص أو مقفول'),
              (_Filter.none, 'مالوش اشتراك'),
            ])
              ChoiceChip(label: Text(label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'دوّر بالإيميل أو الكود',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Text('${rows.length} حساب', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const EmptyNote('مفيش حسابات هنا.')
        else
          for (final u in rows) ...[
            _UserCard(user: u, api: widget.api, act: widget.act),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.api, required this.act});

  final UserRow user;
  final AdminApi api;
  final Future<void> Function(Future<void> Function() change, {String? done}) act;

  ({String label, Color color}) get _state {
    if (user.source == null) return (label: 'مالوش اشتراك', color: Colors.orange.shade800);
    if (user.disabled) return (label: 'مقفول', color: Colors.red.shade700);
    if (!user.active) return (label: 'خلص ${day(user.endsAt)}', color: Colors.grey.shade700);
    if (user.endsAt == null) return (label: 'شغال من غير نهاية', color: Colors.green.shade700);
    return (label: 'شغال — فاضل ${user.daysLeft} يوم', color: Colors.green.shade700);
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: state.color.withValues(alpha: 0.12),
              child: Text(
                user.email.isEmpty ? '?' : user.email[0].toUpperCase(),
                style: TextStyle(color: state.color, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(user.email, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                      StateChip(state.label, state.color),
                      StateChip(sourceLabel(user.source), Colors.blueGrey.shade600),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (user.code != null) 'الكود ${user.code}',
                      if (user.endsAt != null) 'ينتهي ${day(user.endsAt)}',
                      'آخر دخول ${day(user.lastSignIn)}',
                      'ذكاء اصطناعي النهاردة: ${user.usedToday}',
                      'اتسجّل ${day(user.createdAt)}',
                    ].join(' · '),
                    style: muted,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'تعديل',
              onSelected: (choice) => _on(context, choice),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'add', child: Text('زوّد أيام')),
                const PopupMenuItem(value: 'end', child: Text('حدّد يوم النهاية')),
                const PopupMenuItem(value: 'forever', child: Text('من غير نهاية')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(user.disabled ? 'افتح الحساب' : 'اقفل الحساب'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _on(BuildContext context, String choice) async {
    switch (choice) {
      case 'add':
        final days = await askNumber(context, 'زوّد كام يوم؟', hint: 'رقم سالب بينقّص');
        if (days == null || days == 0) return;
        await act(() => api.updateUser(user.id, addDays: days), done: 'اتعدّل');
      case 'end':
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          initialDate: user.endsAt != null && user.endsAt!.isAfter(DateTime.now())
              ? user.endsAt!
              : DateTime.now().add(const Duration(days: 30)),
        );
        if (picked == null) return;
        final end = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        await act(() => api.updateUser(user.id, endsAt: end), done: 'هيخلص ${day(end)}');
      case 'forever':
        if (!context.mounted) return;
        if (!await confirm(context, 'من غير نهاية؟', '${user.email} هيفضل مفتوح لحد ما تقفله بإيدك.')) return;
        await act(() => api.updateUser(user.id, forever: true), done: 'بقى من غير نهاية');
      case 'toggle':
        if (!user.disabled) {
          if (!context.mounted) return;
          final ok = await confirm(
            context,
            'تقفل الحساب؟',
            'التطبيق هيتقفل عند ${user.email} في نفس اللحظة. داتاه مش هتتمسح، وتقدر تفتحه تاني.',
            action: 'اقفل',
          );
          if (!ok) return;
        }
        await act(
          () => api.updateUser(user.id, disabled: !user.disabled),
          done: user.disabled ? 'الحساب اتفتح' : 'الحساب اتقفل',
        );
    }
  }
}
