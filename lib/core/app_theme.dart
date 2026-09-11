import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'design.dart';

/// نظام تصميم التطبيق: ألوان حبر أخضر على خلفيات ورقية، بوضع داكن متناسق.
/// The app's design system: ink green on paper grounds, with a matching dark.
///
/// كل مكوّن بياخد شكله من هنا مش من الشاشات. الشاشة اللي بتكتب لون أو نصف قطر
/// بنفسها بتخرج عن السرب أول ما الثيم يتغير.
/// Every component takes its look from here rather than from the screens. A
/// screen that writes its own colour or radius falls out of step the moment the
/// theme changes.
class AppTheme {
  const AppTheme._();

  /// أخضر حبر — لون الهوية.
  /// Ink green: the identity colour.
  static const Color seed = Color(0xFF176B58);

  /// ألوان جاهزة للمواد. مختارة عشان تفضل مقروءة على الورق وفي الوضع الداكن،
  /// ومتميزة عن بعضها لمن يصعب عليه تمييز الألوان.
  /// Subject colours, chosen to stay legible on paper and in dark mode, and to
  /// stay distinguishable for colour-blind readers.
  static const List<Color> subjectPalette = [
    Color(0xFF176B58), // ink green
    Color(0xFF1D6FA5), // deep sky
    Color(0xFFB4762A), // amber clay
    Color(0xFFA33B4E), // wine
    Color(0xFF6A4C9C), // violet
    Color(0xFF2F7D57), // moss
    Color(0xFFB05A2A), // rust
    Color(0xFF4A6274), // slate
    Color(0xFF8A5A83), // plum
  ];

  static ThemeData light(bool isAr) => _build(Brightness.light, isAr);
  static ThemeData dark(bool isAr) => _build(Brightness.dark, isAr);

  // ---------------------------------------------------------------- colour
  static ColorScheme _scheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
      // الأسطح مكتوبة بالإيد: المولّد بيدي أخضر مائل للرمادي، والمطلوب ورق دافي
      // في الفاتح وحبر عميق في الداكن.
      // Surfaces are hand-set: the generator leans grey-green, and what this
      // wants is warm paper in light and deep ink in dark.
      surface: dark ? const Color(0xFF141E1B) : const Color(0xFFFCFBF7),
      surfaceContainerLowest: dark ? const Color(0xFF1A2724) : Colors.white,
      surfaceContainerLow: dark ? const Color(0xFF1E2D29) : const Color(0xFFF7F6F1),
      surfaceContainerHighest:
          dark ? const Color(0xFF25352F) : const Color(0xFFEFEEE7),
      onSurface: dark ? const Color(0xFFE7EEE9) : const Color(0xFF1C302A),
      onSurfaceVariant: dark ? const Color(0xFFA9BCB3) : const Color(0xFF5C6F67),
      outlineVariant: dark ? const Color(0xFF31433D) : const Color(0xFFE2E0D6),
      primary: dark ? const Color(0xFF6FCFAF) : seed,
      onPrimary: dark ? const Color(0xFF00382C) : Colors.white,
      primaryContainer: dark ? const Color(0xFF1F5449) : const Color(0xFFD6EDE3),
      onPrimaryContainer:
          dark ? const Color(0xFFB9EBD8) : const Color(0xFF0A3E33),
      error: dark ? const Color(0xFFF2B3AE) : const Color(0xFF9E3B33),
      errorContainer: dark ? const Color(0xFF5B241F) : const Color(0xFFFBE2DE),
      onErrorContainer:
          dark ? const Color(0xFFFBE2DE) : const Color(0xFF6B221C),
    );
  }

  // ------------------------------------------------------------ typography
  /// سلّم واضح: عناوين ثقيلة ومضغوطة، ونص جسم مريح للقراءة الطويلة.
  /// A clear scale: headings tight and heavy, body loose enough to read for
  /// long stretches.
  static TextTheme _textTheme(TextTheme base, bool isAr, ColorScheme scheme) {
    // Cairo يقرأ كويس بالعربي، و Inter للإنجليزي.
    // Cairo reads well in Arabic; Inter for English.
    final family =
        isAr ? GoogleFonts.cairoTextTheme(base) : GoogleFonts.interTextTheme(base);

    // العربي بيحتاج ارتفاع سطر أكبر: الحروف فيها نقط وتشكيل فوق وتحت السطر.
    // Arabic needs more line height: its marks sit above and below the line.
    final bodyHeight = isAr ? 1.85 : 1.65;
    final headingHeight = isAr ? 1.45 : 1.25;

    return family
        .copyWith(
          displaySmall: family.displaySmall
              ?.copyWith(fontWeight: FontWeight.w800, height: headingHeight),
          headlineLarge: family.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w800, height: headingHeight),
          headlineMedium: family.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800, height: headingHeight),
          headlineSmall: family.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700, height: headingHeight),
          titleLarge: family.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700, height: headingHeight),
          titleMedium: family.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
          titleSmall: family.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.4),
          bodyLarge: family.bodyLarge?.copyWith(height: bodyHeight),
          bodyMedium: family.bodyMedium?.copyWith(height: bodyHeight),
          bodySmall: family.bodySmall?.copyWith(height: bodyHeight),
          labelLarge: family.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          labelMedium: family.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          labelSmall: family.labelSmall
              ?.copyWith(fontWeight: FontWeight.w600, height: 1.5),
        )
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  }

  // ----------------------------------------------------------------- build
  static ThemeData _build(Brightness brightness, bool isAr) {
    final scheme = _scheme(brightness);
    final palette = AppPalette.forBrightness(brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final text = _textTheme(base.textTheme, isAr, scheme);
    final hairline = scheme.outlineVariant;

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: Radii.all(Radii.md),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      extensions: [palette],
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleSpacing: Insets.xl,
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        titleTextStyle: text.titleLarge,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.all(Radii.lg),
          side: BorderSide(color: hairline),
        ),
      ),

      // الحقل بيتملي بلون أهدى من البطاقة عشان يبان إنه مكان كتابة مش عرض.
      // Fields sit on a quieter fill than cards, so they read as somewhere to
      // write rather than something to read.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: border(hairline),
        enabledBorder: border(hairline),
        focusedBorder: border(scheme.primary, 1.6),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 1.6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.lg,
        ),
        labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xxl),
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          side: BorderSide(color: hairline),
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.sm)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.sm)),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 1,
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape:
            RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
        elevation: 0,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: scheme.primaryContainer,
        indicatorShape:
            RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
        selectedLabelTextStyle:
            text.labelSmall?.copyWith(color: scheme.onPrimaryContainer),
        unselectedLabelTextStyle:
            text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        selectedIconTheme:
            IconThemeData(size: 23, color: scheme.onPrimaryContainer),
        unselectedIconTheme:
            IconThemeData(size: 23, color: scheme.onSurfaceVariant),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide(color: hairline),
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: Insets.md,
          ),
          // ارتفاع سطر أوسع: الحروف العربية بتعلا وتنزل بره السطر القياسي،
          // وصندوق الشريحة كان بيقصّها لما القارئ يكبّر الخط.
          // A taller line box: Arabic glyphs reach above and below the standard
          // line, and the segment was clipping them at larger text sizes.
          textStyle: text.labelMedium?.copyWith(height: 1.6),
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
        ),
      ),

      chipTheme: base.chipTheme.copyWith(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: hairline),
        labelStyle: text.labelMedium,
        // من غير علامة صح: الاختيار باين من لون الشريحة، والعلامة كانت بتزقّ
        // النص لبره الشريحة في الأسماء الطويلة وفي العربي.
        // No tick: selection already shows in the chip's fill, and the tick was
        // pushing the label out of the chip for long and Arabic names.
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.sm)),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.xl,
          vertical: Insets.xs,
        ),
        titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle:
            text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
      ),

      dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.hero)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.xl)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.onSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.surface),
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
        insetPadding: const EdgeInsets.all(Insets.lg),
      ),

      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 5,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: Radii.all(6)),
        side: BorderSide(color: scheme.outlineVariant, width: 1.6),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.onSurface,
          borderRadius: Radii.all(Radii.sm),
        ),
        textStyle: text.labelSmall?.copyWith(color: scheme.surface),
      ),
    );
  }
}
