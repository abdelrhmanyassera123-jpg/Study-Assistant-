import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../common.dart';

/// عمل كود واحد أو مجموعة: المدة، والنوع، وآخر ميعاد للتفعيل، وملاحظة.
/// Makes one code or a batch: the length, the kind, the last day to redeem,
/// and a note.
class CreateCodesDialog extends StatefulWidget {
  const CreateCodesDialog({super.key, required this.api});

  final AdminApi api;

  @override
  State<CreateCodesDialog> createState() => _CreateCodesDialogState();
}

class _CreateCodesDialogState extends State<CreateCodesDialog> {
  final _count = TextEditingController(text: '1');
  final _custom = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'trial';
  int? _days = 7;
  DateTime? _validUntil;
  bool _busy = false;
  String? _error;

  static const _presets = [7, 30, 90, 120];

  @override
  void dispose() {
    _count.dispose();
    _custom.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _chosenDays => _days ?? int.tryParse(_custom.text);

  Future<void> _make() async {
    final count = int.tryParse(_count.text) ?? 0;
    final days = _chosenDays ?? 0;
    if (count < 1 || count > 500) return setState(() => _error = 'العدد من 1 لـ 500.');
    if (days < 1 || days > 3650) return setState(() => _error = 'الأيام من 1 لـ 3650.');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final made = await widget.api.createCodes(
        count: count,
        days: days,
        kind: _kind,
        validUntil: _validUntil == null
            ? null
            : DateTime(_validUntil!.year, _validUntil!.month, _validUntil!.day, 23, 59, 59),
        note: _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, made);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelLarge;
    return AlertDialog(
      title: const Text('عمل أكواد'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('النوع', style: label),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'trial', label: Text('تجريبي'), icon: Icon(Icons.hourglass_top_rounded)),
                  ButtonSegment(value: 'paid', label: Text('مدفوع'), icon: Icon(Icons.payments_outlined)),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() {
                  _kind = s.first;
                  if (_kind == 'trial' && _days == null && _custom.text.isEmpty) _days = 7;
                  if (_kind == 'paid' && _days == 7) _days = 30;
                }),
              ),
              const SizedBox(height: 6),
              Text(
                _kind == 'trial'
                    ? 'التجريبي مرة واحدة بس لكل حساب.'
                    : 'المدفوع بيتزوّد على الأيام اللي فاضلة لو الاشتراك لسه شغال.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Text('المدة', style: label),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in _presets)
                    ChoiceChip(
                      label: Text('$d يوم'),
                      selected: _days == d,
                      onSelected: (_) => setState(() {
                        _days = d;
                        _custom.clear();
                      }),
                    ),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _custom,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(hintText: 'عدد تاني', isDense: true, border: OutlineInputBorder()),
                      onChanged: (v) => setState(() => _days = v.isEmpty ? 7 : null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'عدد الأكواد', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                          initialDate: _validUntil ?? DateTime.now().add(const Duration(days: 30)),
                        );
                        setState(() => _validUntil = picked);
                      },
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(_validUntil == null ? 'يتفعّل في أي وقت' : 'آخر ميعاد ${day(_validUntil)}'),
                    ),
                  ),
                ],
              ),
              if (_validUntil != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => setState(() => _validUntil = null),
                    child: const Text('شيل آخر ميعاد'),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'ملاحظة (اختياري)',
                  hintText: 'مثلًا: أحمد — دفع فودافون كاش',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _make, child: Text(_busy ? '...' : 'اعمل')),
      ],
    );
  }
}

/// الأكواد اللي لسه اتعملت: تتنسخ كلها مرة واحدة أو تتنزّل Excel.
/// The codes just made: copy them all at once or download them for Excel.
class MadeCodesDialog extends StatelessWidget {
  const MadeCodesDialog({super.key, required this.codes});

  final List<CodeRow> codes;

  @override
  Widget build(BuildContext context) {
    final all = codes.map((c) => c.code).join('\n');
    return AlertDialog(
      title: Text(codes.length == 1 ? 'الكود جاهز' : '${codes.length} كود جاهزين'),
      content: SizedBox(
        width: 380,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in codes)
                ListTile(
                  dense: true,
                  title: SelectableText(
                    c.code,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('${kindLabel(c.kind)} · ${c.days} يوم'),
                  trailing: IconButton(
                    tooltip: 'نسخ',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => copy(context, c.code),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (codes.length > 1)
          TextButton.icon(
            onPressed: () => downloadCsv('codes.csv', [
              ['الكود', 'النوع', 'الأيام', 'آخر ميعاد للتفعيل', 'ملاحظة'],
              for (final c in codes) [c.code, kindLabel(c.kind), '${c.days}', day(c.validUntil), c.note],
            ]),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Excel'),
          ),
        TextButton.icon(
          onPressed: () => copy(context, all, message: codes.length == 1 ? 'اتنسخ' : 'اتنسخوا كلهم'),
          icon: const Icon(Icons.copy_all_rounded, size: 18),
          label: Text(codes.length == 1 ? 'نسخ' : 'نسخ الكل'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تمام')),
      ],
    );
  }
}
