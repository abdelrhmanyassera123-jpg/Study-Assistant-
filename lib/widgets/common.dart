import 'package:flutter/material.dart';

import '../core/design.dart';
import '../core/l10n.dart';
import '../models/models.dart';

/// غلاف كل صفحة: بيمرر، بيحدد أقصى عرض، وبيضبط الحشو حسب حجم الشاشة.
/// Every page's wrapper: it scrolls, caps the width, and sets padding by size.
///
/// التمرير هنا مش في كل صفحة على حدة — من غيره أي محتوى أطول من الشاشة بيتقص
/// وما فيش طريقة توصله. دي كانت باج في كل الأقسام.
/// Scrolling lives here rather than in each page: without it any content taller
/// than the window is cut off with no way to reach it. That was a bug across
/// every section.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = 1080,
    this.controller,
  });

  final Widget child;
  final double maxWidth;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final side = Breakpoints.isCompact(context) ? Insets.lg : Insets.section;

    return SingleChildScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            // حشو سفلي واسع: الزرار العائم والشريط السفلي بيغطوا آخر الصفحة.
            // Generous bottom padding: the floating button and bottom bar sit
            // over the end of the page.
            padding: EdgeInsets.fromLTRB(side, Insets.sm, side, 120),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// بطاقة بحشو موحّد — بديل تكرار Card + Padding في كل مكان.
/// A card with standard padding, replacing Card + Padding everywhere.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = Insets.xl,
    this.onTap,
    this.color,
    this.border,
  });

  final Widget child;
  final double padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: Radii.all(Radii.lg),
      side: BorderSide(color: border ?? scheme.outlineVariant),
    );

    final content = Padding(padding: EdgeInsets.all(padding), child: child);

    return Card(
      color: color,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

/// عنوان قسم داخل الصفحة.
/// A section heading within a page.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.section, bottom: Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.xs),
                    child: Text(
                      subtitle!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// خطوة مرقّمة في تدفّق متعدد المراحل.
/// A numbered step in a multi-stage flow.
///
/// الترقيم مش زينة: صفحة التلخيص فيها إدخال واختيار أسلوب وتوليد، وبدون ترقيم
/// بتبان كلها اختيارات متساوية بدل ترتيب لازم يتمشى.
/// The numbers are not decoration: the summarize page has an input, a style
/// choice and a generation, and without them the three read as equal options
/// rather than an order to follow.
class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.done = false,
  });

  final int step;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  /// الخطوة المكتملة بتاخد علامة صح بدل رقمها.
  /// A finished step shows a tick instead of its number.
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: done ? scheme.primary : scheme.primaryContainer,
                  borderRadius: Radii.all(Radii.sm),
                ),
                child: done
                    ? Icon(Icons.check_rounded,
                        size: 17, color: scheme.onPrimary)
                    : Text(
                        '$step',
                        style: text.labelMedium
                            ?.copyWith(color: scheme.onPrimaryContainer),
                      ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: text.titleSmall),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: Insets.sm),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: Insets.xl),
          child,
        ],
      ),
    );
  }
}

/// شريحة تصفية — بديل ChoiceChip.
/// A filter pill, standing in for ChoiceChip.
///
/// شرائح مادة Material كانت بتقيس نفسها أضيق من نصّها فبتقصّه في اللغتين،
/// والشكل ده مبني على نفس مقاسات باقي التصميم فبيتصرف زي ما هو مكتوب.
/// Material's chips measured themselves narrower than their own label and
/// clipped it in both languages; this is built on the same scale as the rest of
/// the design and behaves the way it reads.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.dot,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// نقطة بلون المادة قبل الاسم.
  /// A dot in the subject's colour before its name.
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.all(Radii.sm),
        side: BorderSide(
          color: selected ? Colors.transparent : scheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: Insets.sm),
              ],
              Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شبكة بطاقات: عمود واحد على الموبايل، وأعمدة على الشاشة الواسعة.
/// A card grid: one column on phones, more on a wide screen.
///
/// الملاحظات والمواد بطاقات مستقلة، وعمود واحد بعرض الشاشة بيسيب فراغ كبير
/// على الديسكتوب وبيخلي التمرير أطول من اللازم.
/// Notes and subjects are independent cards, and a single full-width column
/// leaves a lot of empty space on desktop while making the page needlessly
/// long to scroll.
class CardGrid extends StatelessWidget {
  const CardGrid({
    super.key,
    required this.children,
    this.minTileWidth = 330,
    this.maxColumns = 2,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minTileWidth)
            .floor()
            .clamp(1, maxColumns);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: child,
                ),
            ],
          );
        }

        final width =
            (constraints.maxWidth - Insets.md * (columns - 1)) / columns;
        return Wrap(
          spacing: Insets.md,
          runSpacing: Insets.md,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// شريط اكتمال بوصف وبنسبة.
/// A progress bar with a label and a percentage.
///
/// [value] بـ null بيدّي شريط ماشي من غير نسبة — للحاجات اللي مالهاش طول
/// معروف زي البث. الرقم بيتعرض بس لما يكون حقيقي: نسبة مخترعة أسوأ من مفيش.
/// A null [value] gives a moving bar with no figure, for work whose length is
/// unknown, such as a stream. The number shows only when it is real: an
/// invented percentage is worse than none.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.label, this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final percent = value == null ? null : (value!.clamp(0, 1) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            if (percent != null) ...[
              const SizedBox(width: Insets.md),
              Text(
                '$percent%',
                style: text.labelMedium?.copyWith(color: scheme.primary),
              ),
            ],
          ],
        ),
        const SizedBox(height: Insets.sm),
        ClipRRect(
          borderRadius: Radii.all(Insets.sm),
          child: TweenAnimationBuilder<double>(
            // الشريط بيتحرك لمكانه بدل ما ينط: النطة بتخلي التقدّم يبان عشوائي.
            // The bar slides to its place rather than jumping; a jump makes
            // progress look arbitrary.
            duration: Motion.normal,
            curve: Motion.ease,
            tween: Tween(begin: 0, end: value ?? 0),
            builder: (context, animated, _) => LinearProgressIndicator(
              value: value == null ? null : animated,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
      ],
    );
  }
}

/// حالة "مفيش حاجة هنا" برسالة وزرار اختياري.
/// The empty state, with a message and an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.title,
    this.action,
  });

  final IconData icon;
  final String message;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.xxl,
            vertical: Insets.page,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(Insets.xl),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: Radii.all(Radii.xl),
                ),
                child: Icon(icon, size: 30, color: scheme.primary),
              ),
              const SizedBox(height: Insets.xl),
              if (title != null) ...[
                Text(title!, textAlign: TextAlign.center, style: text.titleMedium),
                const SizedBox(height: Insets.sm),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (action != null) ...[
                const SizedBox(height: Insets.xxl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// مؤشر تحميل موحّد.
/// One loading indicator for the whole app.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          if (label != null) ...[
            const SizedBox(height: Insets.lg),
            Text(
              label!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

/// عرض موحّد لأي خطأ جاي من الشبكة أو الداتابيز.
/// One place to render any network or database error.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(Insets.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(Insets.lg),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: Radii.all(Radii.lg),
                ),
                child: Icon(Icons.cloud_off_rounded,
                    size: 26, color: scheme.onErrorContainer),
              ),
              const SizedBox(height: Insets.lg),
              Text(context.l.somethingWrong,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: Insets.sm),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: Insets.xl),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(context.l.retry),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// لوحة ملاحظة أو تحذير داخل الصفحة.
/// An inline note or warning panel.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.lightbulb_outline_rounded,
    this.tone = BannerTone.info,
    this.action,
  });

  final String message;
  final IconData icon;
  final BannerTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);

    final (fg, bg) = switch (tone) {
      BannerTone.info => (scheme.onPrimaryContainer, scheme.primaryContainer),
      BannerTone.warn => (palette.warm, palette.warmSurface),
      BannerTone.error => (scheme.onErrorContainer, scheme.errorContainer),
    };

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          Insets.lg, Insets.md, Insets.sm, Insets.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.all(Radii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: fg),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w500),
            ),
          ),
          if (action != null) ...[const SizedBox(width: Insets.sm), action!],
        ],
      ),
    );
  }
}

enum BannerTone { info, warn, error }

/// بطاقة رقم واحد كبير — للوحة الرئيسية والإحصائيات.
/// A single big-number tile, used on the home and stats pages.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;

    return AppCard(
      padding: Insets.lg,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(Insets.sm),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: Radii.all(Radii.sm),
            ),
            child: Icon(icon, color: c, size: 19),
          ),
          const SizedBox(height: Insets.lg),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(height: 1.1),
            ),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// شبكة بطاقات بتتكيف مع العرض بدل Row ثابت.
/// A card grid that adapts to width instead of a fixed Row.
///
/// الـ Row الثابت بيكسر التخطيط مع تكبير الخط أو الشاشات الضيقة.
/// A fixed Row breaks the layout under larger text or narrow screens.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.minTileWidth = 168});

  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = (constraints.maxWidth / minTileWidth).floor().clamp(1, 4);

        // بنتجنب صف أخير فيه بطاقة واحدة يتيمة: أربع بطاقات في ثلاثة أعمدة
        // بتطلع 3+1، والتقسيم 2×2 أهدى للعين.
        // Avoid a trailing row holding a single orphan: four tiles across three
        // columns give 3+1, where an even 2×2 reads far calmer.
        if (columns > 2 && children.length % columns == 1) columns -= 1;

        const spacing = Insets.md;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// شارة صغيرة باسم المادة ولونها.
/// A small pill showing a subject's name in its colour.
class SubjectChip extends StatelessWidget {
  const SubjectChip({super.key, required this.subject, this.dense = false});

  final Subject? subject;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = subject;
    final scheme = Theme.of(context).colorScheme;
    final color = s?.color ?? scheme.outline;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Insets.sm : Insets.md,
        vertical: dense ? 3 : Insets.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: Radii.all(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Insets.sm),
          Flexible(
            child: Text(
              s?.name ?? context.l.noSubject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// حوار تأكيد الحذف — بيرجع true لو المستخدم أكد.
/// Delete confirmation dialog; returns true when confirmed.
Future<bool> confirmDelete(BuildContext context, {String? extra}) async {
  final l = context.l;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.delete_outline_rounded,
          color: Theme.of(ctx).colorScheme.error),
      title: Text(l.deleteConfirm),
      content: extra == null ? null : Text(extra),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l.delete),
        ),
      ],
    ),
  );
  return ok ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// قايمة اختيار المادة — بتستعمل في كل الفورمات.
/// The subject picker, reused by every form.
class SubjectDropdown extends StatelessWidget {
  const SubjectDropdown({
    super.key,
    required this.subjects,
    required this.value,
    required this.onChanged,
  });

  final List<Subject> subjects;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final safeValue = subjects.any((s) => s.id == value) ? value : null;

    return DropdownButtonFormField<String?>(
      initialValue: safeValue,
      isExpanded: true,
      decoration: InputDecoration(labelText: context.l.selectSubject),
      borderRadius: Radii.all(Radii.md),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(context.l.noSubject)),
        for (final s in subjects)
          DropdownMenuItem<String?>(
            value: s.id,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: s.color, shape: BoxShape.circle),
                ),
                const SizedBox(width: Insets.md),
                Flexible(
                  child: Text(s.name, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
