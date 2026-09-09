import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/summarize/summarizer.dart';

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
    this.ollamaBaseUrl = 'http://localhost:11434',
    this.ollamaModel = '',
    this.ollamaNumCtx = 16384,
    this.summarizer = SummarizerProvider.ollama,
    this.geminiModel = '',
  });

  final String languageCode;
  final ThemeMode themeMode;
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;
  final int roundsBeforeLongBreak;
  final bool autoStartNext;

  /// إعدادات موديل التلخيص المحلي.
  /// Local summarization model settings.
  final String ollamaBaseUrl;
  final String ollamaModel;
  final int ollamaNumCtx;

  /// مين بيلخص، وأي موديل من Gemini.
  /// Which provider summarizes, and which Gemini model it uses.
  final SummarizerProvider summarizer;
  final String geminiModel;

  Locale get locale => Locale(languageCode);

  AppSettings copyWith({
    String? languageCode,
    ThemeMode? themeMode,
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
    int? roundsBeforeLongBreak,
    bool? autoStartNext,
    String? ollamaBaseUrl,
    String? ollamaModel,
    int? ollamaNumCtx,
    SummarizerProvider? summarizer,
    String? geminiModel,
  }) {
    return AppSettings(
      languageCode: languageCode ?? this.languageCode,
      themeMode: themeMode ?? this.themeMode,
      focusMinutes: focusMinutes ?? this.focusMinutes,
      shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
      longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      roundsBeforeLongBreak: roundsBeforeLongBreak ?? this.roundsBeforeLongBreak,
      autoStartNext: autoStartNext ?? this.autoStartNext,
      ollamaBaseUrl: ollamaBaseUrl ?? this.ollamaBaseUrl,
      ollamaModel: ollamaModel ?? this.ollamaModel,
      ollamaNumCtx: ollamaNumCtx ?? this.ollamaNumCtx,
      summarizer: summarizer ?? this.summarizer,
      geminiModel: geminiModel ?? this.geminiModel,
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
  static const _kOllamaUrl = 'ollama_url';
  static const _kOllamaModel = 'ollama_model';
  static const _kOllamaCtx = 'ollama_ctx';
  static const _kProvider = 'summarizer_provider';
  static const _kGeminiModel = 'gemini_model';

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
      ollamaBaseUrl: p.getString(_kOllamaUrl) ?? 'http://localhost:11434',
      ollamaModel: p.getString(_kOllamaModel) ?? '',
      ollamaNumCtx: p.getInt(_kOllamaCtx) ?? 16384,
      summarizer: SummarizerProvider.values.firstWhere(
        (v) => v.name == p.getString(_kProvider),
        orElse: () => SummarizerProvider.ollama,
      ),
      geminiModel: p.getString(_kGeminiModel) ?? '',
    );
  }

  void setSummarizerProvider(SummarizerProvider provider) {
    state = state.copyWith(summarizer: provider);
    _prefs?.setString(_kProvider, provider.name);
  }

  void setGeminiModel(String model) {
    state = state.copyWith(geminiModel: model);
    _prefs?.setString(_kGeminiModel, model);
  }

  void setOllamaConfig({String? baseUrl, String? model, int? numCtx}) {
    state = state.copyWith(
      ollamaBaseUrl: baseUrl,
      ollamaModel: model,
      ollamaNumCtx: numCtx,
    );
    final p = _prefs;
    if (p == null) return;
    p.setString(_kOllamaUrl, state.ollamaBaseUrl);
    p.setString(_kOllamaModel, state.ollamaModel);
    p.setInt(_kOllamaCtx, state.ollamaNumCtx);
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
