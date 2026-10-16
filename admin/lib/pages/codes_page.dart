import 'package:flutter/material.dart';

import '../api.dart';
import '../common.dart';
import '../shell.dart';

enum _Filter { all, unused, active, ended, disabled }

/// كل الأكواد: بحث وفلترة، وعلى كل كود قفل/فتح، أيام، ملاحظة، نسخ، مسح.
/// Every code: search and filters, and on each one switch off/on, days, a
/// note, copy, delete.
class CodesPage extends StatefulWidget {
  const CodesPage({super.key, required this.data, required this.api, required this.act});

  final Dashboard data;
  final AdminApi api;
  final Future<void> Function(Future<void> Function() change, {String? done}) act;

  @override
  State<CodesPage> createState() => _CodesPageState();
}

class _CodesPageState extends State<CodesPage> {
  _Filter _filter = _Filter.all;
  String _query = '';

  bool _matches(CodeRow c) {
    final user = c.redeemedBy == null ? null : widget.data.userById[c.redeemedBy];
    final ok = switch (_filter) {
      _Filter.all => true,
      _Filter.unused => !c.used && !c.disabled && !c.lapsed,
      _Filter.active => c.used && !c.disabled && (user?.active ?? false),
      _Filter.ended => (c.used && !(user?.active ?? false)) || c.lapsed,
      _Filter.disabled => c.disabled,
    };
    if (!ok) return false;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return c.code.toLowerCase().contains(q) ||
        c.note.toLowerCase().contains(q) ||
        (user?.email.toLowerCase().contains(q) ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.data.codes.where(_matches).toList();

    return PageFrame(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (f, label) in [
              (_Filter.all, 'الكل'),
              (_Filter.unused, 'لسه ما اتستخدمش'),
              (_Filter.active, 'شغال'),
              (_Filter.ended, 'خلص'),
              (_Filter.disabled, 'مقفول'),
            ])
              ChoiceChip(label: Text(label), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'دوّر بالكود أو الإيميل أو الملاحظة',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'تنزيل Excel',
              onPressed: rows.isEmpty
                  ? null
                  : () => downloadCsv('codes.csv', [
                        ['الكود', 'النوع', 'الأيام', 'الحالة', 'فعّله', 'اتفعّل', 'ملاحظة', 'اتعمل'],
                        for (final c in rows)
                          [
                            c.code,
                            kindLabel(c.kind),
                            '${c.days}',
                            codeState(c, widget.data.userById[c.redeemedBy]).label,
                            widget.data.userById[c.redeemedBy]?.email ?? '',
                            day(c.redeemedAt),
                            c.note,
                            day(c.createdAt),
                          ],
                      ]),
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('${rows.length} كود', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          const EmptyNote('مفيش أكواد هنا — اعمل أكواد من الزرار تحت.')
        else
          for (final c in rows) ...[
            _CodeCard(code: c, redeemer: widget.data.userById[c.redeemedBy], api: widget.api, act: widget.act),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.redeemer, required this.api, required this.act});

  final CodeRow code;
  final UserRow? redeemer;
  final AdminApi api;
  final Future<void> Function(Future<void> Function() change, {String? done}) act;

  @override
  Widget build(BuildContext context) {
    final state = codeState(code, redeemer);
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SelectableText(
                        code.code,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      StateChip(state.label, state.color),
                      StateChip('${kindLabel(code.kind)} · ${code.days} يوم', Colors.blueGrey.shade600),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (redeemer != null) 'فعّله ${redeemer!.email} يوم ${day(code.redeemedAt)}',
                      if (redeemer != null && redeemer!.endsAt != null) 'ينتهي ${day(redeemer!.endsAt)}',
                      if (!code.used && code.validUntil != null) 'آخر ميعاد للتفعيل ${day(code.validUntil)}',
                      if (code.note.isNotEmpty) code.note,
                      'اتعمل ${day(code.createdAt)}',
                    ].join(' · '),
                    style: muted,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'نسخ',
              onPressed: () => copy(context, code.code),
              icon: const Icon(Icons.copy_rounded, size: 20),
            ),
            PopupMenuButton<String>(
              tooltip: 'تعديل',
              onSelected: (choice) => _on(context, choice),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(code.disabled ? 'افتح الكود' : (code.used ? 'اقفل (يقفل التطبيق عنده)' : 'اقفل الكود')),
                ),
                const PopupMenuItem(value: 'days', child: Text('غيّر عدد الأيام')),
                const PopupMenuItem(value: 'note', child: Text('الملاحظة')),
                if (!code.used) const PopupMenuItem(value: 'delete', child: Text('امسح')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _on(BuildContext context, String choice) async {
    switch (choice) {
      case 'toggle':
        if (!code.disabled && code.used) {
          final ok = await confirm(
            context,
            'تقفل الكود؟',
            'التطبيق هيتقفل عند ${redeemer?.email ?? 'اللي فعّله'} في نفس اللحظة. تقدر تفتحه تاني بعدين.',
            action: 'اقفل',
          );
          if (!ok) return;
        }
        await act(
          () => api.updateCode(code.id, disabled: !code.disabled),
          done: code.disabled ? 'الكود اتفتح' : 'الكود اتقفل',
        );
      case 'days':
        if (!context.mounted) return;
        final days = await askNumber(
          context,
          'عدد أيام الكود',
          initial: code.days,
          hint: code.used ? 'الفرق بيتزوّد أو يتنقص من نهاية اشتراكه' : '',
        );
        if (days == null || days < 1) return;
        await act(() => api.updateCode(code.id, days: days), done: 'الأيام اتعدّلت');
      case 'note':
        if (!context.mounted) return;
        final note = await askText(context, 'الملاحظة', initial: code.note);
        if (note == null) return;
        await act(() => api.updateCode(code.id, note: note.trim()), done: 'اتحفظت');
      case 'delete':
        if (!context.mounted) return;
        if (!await confirm(context, 'تمسح الكود؟', code.code, action: 'امسح')) return;
        await act(() => api.deleteCode(code.id), done: 'اتمسح');
    }
  }
}
