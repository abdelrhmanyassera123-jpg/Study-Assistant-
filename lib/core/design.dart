import 'package:flutter/material.dart';

/// وحدات التصميم: مسافات، أنصاف أقطار، ومدد الحركة.
/// Design tokens: spacing, radii, and motion durations.
///
/// الأرقام هنا مش تفضيل شخصي — هي السلّم اللي كل الشاشات بتقيس عليه. لما كل
/// صفحة تخترع مسافاتها، الإيقاع البصري بيضيع والفروق الصغيرة بتبان كإهمال.
/// These are not preferences but the scale every screen measures against. When
/// each page invents its own spacing the visual rhythm falls apart, and the
/// small mismatches read as carelessness.
class Insets {
  const Insets._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double section = 32;
  static const double page = 40;
}

class Radii {
  const Radii._();

  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 26;
  static const double hero = 32;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

class Motion {
  const Motion._();

  /// حركة سريعة للتغذية الراجعة الفورية (ضغط، تحويم).
  /// Quick feedback: presses and hovers.
  static const Duration fast = Duration(milliseconds: 140);

  /// ظهور واختفاء المحتوى.
  /// Content appearing and leaving.
  static const Duration normal = Duration(milliseconds: 260);

  static const Curve ease = Curves.easeOutCubic;
}

/// ألوان مش موجودة في ColorScheme لكن التطبيق محتاجها بمعنى ثابت.
/// Colours the app needs by name that ColorScheme has no slot for.
///
/// اللمسات الدافية والنجاح والتحذير بتتكرر في كذا شاشة؛ لو كل شاشة كتبت الهيكس
/// بتاعها، الوضع الداكن بيتكسر في مكان وينفع في مكان.
/// The warm accents, success and warning colours recur across screens. If each
/// screen hard-codes its own hex, dark mode breaks in one place and holds in
/// another.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.warm,
    required this.onWarm,
    required this.warmSurface,
    required this.success,
    required this.heroStart,
    required this.heroEnd,
    required this.onHero,
    required this.shadow,
  });

  /// اللمسة الدافية — للـ streak والتمييز والأرقام اللي المفروض تلفت النظر.
  /// The warm accent: streaks, highlights, and numbers meant to catch the eye.
  final Color warm;
  final Color onWarm;
  final Color warmSurface;

  final Color success;

  /// تدرّج بطاقة الترحيب.
  /// The welcome card's gradient.
  final Color heroStart;
  final Color heroEnd;
  final Color onHero;

  /// ظل خفيف جدًا — الارتفاع في التصميم ده بييجي من الحدود مش من الظلال.
  /// A very soft shadow; elevation here comes from borders, not drop shadows.
  final Color shadow;

  static const _light = AppPalette(
    warm: Color(0xFFB4762A),
    onWarm: Colors.white,
    warmSurface: Color(0xFFFBF1E2),
    success: Color(0xFF2F7D57),
    heroStart: Color(0xFF176B58),
    heroEnd: Color(0xFF2E8B6F),
    onHero: Color(0xFFF2FAF6),
    shadow: Color(0x14203B32),
  );

  static const _dark = AppPalette(
    warm: Color(0xFFE0A75C),
    onWarm: Color(0xFF3A2708),
    warmSurface: Color(0xFF2C2519),
    success: Color(0xFF6DC79B),
    heroStart: Color(0xFF14574A),
    heroEnd: Color(0xFF1E7460),
    onHero: Color(0xFFE8F5EF),
    shadow: Color(0x33000000),
  );

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? _light;

  static AppPalette forBrightness(Brightness b) =>
      b == Brightness.dark ? _dark : _light;

  @override
  AppPalette copyWith({
    Color? warm,
    Color? onWarm,
    Color? warmSurface,
    Color? success,
    Color? heroStart,
    Color? heroEnd,
    Color? onHero,
    Color? shadow,
  }) {
    return AppPalette(
      warm: warm ?? this.warm,
      onWarm: onWarm ?? this.onWarm,
      warmSurface: warmSurface ?? this.warmSurface,
      success: success ?? this.success,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
      onHero: onHero ?? this.onHero,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      warm: Color.lerp(warm, other.warm, t)!,
      onWarm: Color.lerp(onWarm, other.onWarm, t)!,
      warmSurface: Color.lerp(warmSurface, other.warmSurface, t)!,
      success: Color.lerp(success, other.success, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
    );
  }
}

/// نقطة قطع واحدة بين تخطيط الموبايل والديسكتوب.
/// One breakpoint between the phone and desktop layouts.
class Breakpoints {
  const Breakpoints._();

  /// فوقها بيظهر الشريط الجانبي، وتحتها الشريط السفلي.
  /// Above this the side rail shows; below it, the bottom bar.
  static const double rail = 900;

  /// تحتها بنضيّق الحشو ونقلل الأعمدة.
  /// Below this the padding tightens and columns collapse.
  static const double compact = 600;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compact;

  static bool hasRail(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= rail;
}
