import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات المستخدم المحلية: اللغة، المظهر، وإعدادات المؤقت.
/// Local user settings: language, theme, and Pomodoro lengths.
/// بتتحفظ في المتصفح عشان تفضل بعد ما تقفل الصفحة.
/// Persisted in the browser so they survive a reload.
@immutable
class AppSettings {
  const AppSettings({
    this.languageCode = 'ar',
    this.themeMode = ThemeMode.system,
    this.focusMinutes = 25,
    this.shortBreakMinutes = 5,
    this.longBreakMinutes = 15,
    this.roundsBeforeLongBreak = 4,
    this.autoStartNext = false,
    this.geminiModel = '',
    this.uiScale = 1.0,
  });

  final String languageCode;
  final ThemeMode themeMode;
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int roundsBeforeLongBreak;
  final bool autoStartNext;

  /// موديل Gemini المستخدم في التلخيص.
  /// The Gemini model used for summarizing.
  final String geminiModel;

  /// حجم النص في التطبيق كله. موجود لأن Flutter على الويب بيبتلع
  /// Ctrl+عجلة الماوس قبل ما توصل للمتصفح، فزوم المتصفح مش شغال جوه التطبيق.
  /// App-wide text size. It exists because Flutter web swallows Ctrl+wheel
  /// before the browser sees it, so browser zoom does nothing inside the app.
  final double uiScale;

  Locale get locale => Locale(languageCode);

  AppSettings copyWith({
    String? languageCode,
    ThemeMode? themeMode,
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? roundsBeforeLongBreak,
    bool? autoStartNext,
    String? geminiModel,
    double? uiScale,
  }) {
    return AppSettings(
      languageCode: languageCode ?? this.languageCode,
      themeMode: themeMode ?? this.themeMode,
      focusMinutes: focusMinutes ?? this.focusMinutes,
      shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      roundsBeforeLongBreak: roundsBeforeLongBreak ?? this.roundsBeforeLongBreak,
      autoStartNext: autoStartNext ?? this.autoStartNext,
      geminiModel: geminiModel ?? this.geminiModel,
      uiScale: uiScale ?? this.uiScale,
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    // القراءة من التخزين غير متزامنة، فبنبدأ بالافتراضي وبنحدّث لما توصل.
    // Loading is async, so we start from defaults and update when it lands.
    _load();
    return const AppSettings();
  }

  static const _kLang = 'lang';
  static const _kTheme = 'theme';
  static const _kFocus = 'focus_min';
  static const _kShort = 'short_min';
  static const _kLong = 'long_min';
  static const _kRounds = 'rounds';
  static const _kAuto = 'auto_start';
  static const _kGeminiModel = 'gemini_model';
  static const _kUiScale = 'ui_scale';

  SharedPreferences? _prefs;

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    state = AppSettings(
      languageCode: p.getString(_kLang) ?? 'ar',
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == p.getString(_kTheme),
        orElse: () => ThemeMode.system,
      ),
      focusMinutes: p.getInt(_kFocus) ?? 25,
      shortBreakMinutes: p.getInt(_kShort) ?? 5,
      longBreakMinutes: p.getInt(_kLong) ?? 15,
      roundsBeforeLongBreak: p.getInt(_kRounds) ?? 4,
      autoStartNext: p.getBool(_kAuto) ?? false,
      geminiModel: p.getString(_kGeminiModel) ?? '',
      uiScale: p.getDouble(_kUiScale) ?? 1.0,
    );
  }

  void setUiScale(double scale) {
    state = state.copyWith(uiScale: scale);
    _prefs?.setDouble(_kUiScale, scale);
  }

  void setGeminiModel(String model) {
    state = state.copyWith(geminiModel: model);
    _prefs?.setString(_kGeminiModel, model);
  }

  void setLanguage(String code) {
    state = state.copyWith(languageCode: code);
    _prefs?.setString(_kLang, code);
  }

  void toggleLanguage() => setLanguage(state.languageCode == 'ar' ? 'en' : 'ar');

  void setThemeMode(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _prefs?.setString(_kTheme, mode.name);
  }

  void setTimerConfig({
    int? focus,
    int? shortBreak,
    int? longBreak,
    int? rounds,
    bool? autoStart,
  }) {
    state = state.copyWith(
      focusMinutes: focus,
      shortBreakMinutes: shortBreak,
      longBreakMinutes: longBreak,
      roundsBeforeLongBreak: rounds,
      autoStartNext: autoStart,
    );
    final p = _prefs;
    if (p == null) return;
    p.setInt(_kFocus, state.focusMinutes);
    p.setInt(_kShort, state.shortBreakMinutes);
    p.setInt(_kLong, state.longBreakMinutes);
    p.setInt(_kRounds, state.roundsBeforeLongBreak);
    p.setBool(_kAuto, state.autoStartNext);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
