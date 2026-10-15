import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'config.dart';
import 'notifier.dart';
import 'timetable.dart';
import 'updater.dart';

/// تطبيق أندرويد = الموقع نفسه جوه WebView، وجنبه الإشعارات الأصلية.
/// The Android app is the site itself inside a WebView, with native
/// notifications beside it.
///
/// الموقع بيتحدّث لوحده (أي push على main بيوصل هنا فورًا)؛ الكود ده بيتغيّر
/// بس لو الإشعارات أو الصلاحيات اتغيّرت.
/// The site updates by itself (any push to main reaches here at once); this
/// code changes only when the notifications or permissions do.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init();

  // الجدول المحفوظ بيتجدول على طول — حتى من غير نت، والإشعارات تفضل ماشية.
  // The saved timetable is scheduled straight away, even offline, so the
  // notifications keep going.
  final saved = await Timetable.saved();
  if (saved != null) unawaited(Notifier.schedule(saved));

  runApp(const StudyApp());
}

class StudyApp extends StatelessWidget {
  const StudyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'مساعد المذاكرة',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1B6E55), useMaterial3: true),
        home: const ShellPage(),
      );
}

class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> with WidgetsBindingObserver {
  late final WebViewController _web;
  int _progress = 0;
  bool _failed = false;
  bool _askedPermissions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _web = WebViewController(onPermissionRequest: _onPermission)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF7F6F1))
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) => setState(() => _progress = p),
        onPageStarted: (_) => setState(() => _failed = false),
        onPageFinished: (_) => _afterLoad(),
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) setState(() => _failed = true);
        },
        onNavigationRequest: _onNavigation,
      ));

    final android = _web.platform;
    if (android is AndroidWebViewController) {
      // التسجيل والصوت يشتغلوا من غير لمسة زيادة جوه الصفحة.
      // Recording and audio run without an extra tap inside the page.
      android.setMediaPlaybackRequiresUserGesture(false);
      android.setOnShowFileSelector(_pickFiles);
    }

    _web.loadRequest(_pageFor(Notifier.openPage.value));
    Notifier.openPage.value = null;
    Notifier.openPage.addListener(_openFromNotification);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Notifier.openPage.removeListener(_openFromNotification);
    super.dispose();
  }

  /// رجوع للتطبيق بعد غياب: الجدول ممكن يكون اتعدّل من الكمبيوتر.
  /// Back in the app after a while: the timetable may have changed from the
  /// computer.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_syncTimetable());
  }

  Uri _pageFor(String? page) =>
      page == 'schedule' ? Uri.parse('$siteUrl?open=schedule') : Uri.parse(siteUrl);

  void _openFromNotification() {
    final page = Notifier.openPage.value;
    if (page == null) return;
    Notifier.openPage.value = null;
    _web.loadRequest(_pageFor(page));
  }

  /// صفحات الموقع جوه التطبيق؛ أي لينك برّه (صور ويكيبيديا، GitHub) بيفتح في
  /// المتصفح.
  /// The site's pages stay inside the app; any outside link (Wikipedia
  /// pictures, GitHub) opens in the browser.
  FutureOr<NavigationDecision> _onNavigation(NavigationRequest request) {
    final uri = Uri.parse(request.url);
    final site = Uri.parse(siteUrl);
    final inside = uri.host == site.host ||
        uri.scheme == 'about' ||
        uri.scheme == 'data' ||
        uri.scheme == 'blob' ||
        uri.host.endsWith('supabase.co');
    if (inside || !request.isMainFrame) return NavigationDecision.navigate;
    launchUrl(uri, mode: LaunchMode.externalApplication);
    return NavigationDecision.prevent;
  }

  Future<void> _afterLoad() async {
    if (!_askedPermissions) {
      _askedPermissions = true;
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('asked_permissions') ?? false)) {
        await prefs.setBool('asked_permissions', true);
        await Notifier.askPermissions();
      }
      if (mounted) unawaited(checkForUpdate(context));
    }
    // الموقع بيجدد التوكن أول ما يفتح؛ بنستنى شوية عشان نقرا الجديد.
    // The site renews its token as it opens; wait a moment to read the new one.
    await Future<void>.delayed(const Duration(seconds: 4));
    await _syncTimetable();
  }

  /// بيقرا جلسة الموقع من التخزين بتاعه، ويجيب الجدول بيها ويجدول الإشعارات.
  /// Reads the site's session from its storage, fetches the timetable with
  /// it, and schedules the notifications.
  Future<void> _syncTimetable() async {
    try {
      final raw = await _web.runJavaScriptReturningResult(r'''
(() => {
  for (const k of Object.keys(localStorage)) {
    if (!k.includes('auth-token')) continue;
    let v = localStorage.getItem(k);
    try { v = JSON.parse(v); if (typeof v === 'string') v = JSON.parse(v); } catch (e) {}
    if (v && v.access_token) return v.access_token;
  }
  return '';
})()
''');
      var token = '$raw';
      if (token.startsWith('"')) token = jsonDecode(token) as String;
      if (token.isEmpty || token == 'null') return;

      final table = await Timetable.fetch(token);
      await table.save();
      await Notifier.schedule(table);
    } catch (_) {
      // من غير نت أو مش مسجّل دخول: الجدول المحفوظ شغال زي ما هو.
      // Offline or signed out: the saved timetable keeps working as is.
    }
  }

  /// الموقع طلب يسمع الميكروفون (تسجيل محاضرة): بنطلب إذن أندرويد الأول.
  /// The site asked for the microphone (recording a lecture): Android's
  /// permission comes first.
  Future<void> _onPermission(WebViewPermissionRequest request) async {
    if (request.types.contains(WebViewPermissionResourceType.microphone)) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) return request.deny();
    }
    if (request.types.contains(WebViewPermissionResourceType.camera)) {
      final status = await Permission.camera.request();
      if (!status.isGranted) return request.deny();
    }
    return request.grant();
  }

  /// "اختار ملف" في الموقع بيفتح اختيار الملفات بتاع أندرويد.
  /// "Choose a file" in the site opens Android's file picker.
  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      final files = await FilePicker.pickFiles();
      final picked = params.mode == FileSelectorMode.openMultiple ? files : files.take(1);
      return [for (final f in picked) f.uri.toString()];
    } catch (_) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _web.canGoBack()) {
          await _web.goBack();
        } else {
          await SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F6F1),
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _web),
              if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
              if (_failed) _Offline(onRetry: () => _web.reload()),
            ],
          ),
        ),
      ),
    );
  }
}

/// لما الموقع ما يفتحش ومفيش نسخة محفوظة منه.
/// When the site will not open and has no saved copy.
class _Offline extends StatelessWidget {
  const _Offline({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFFF7F6F1),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off_rounded, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'مفيش نت دلوقتي',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'إشعارات محاضراتك شغالة عادي من غير نت.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: onRetry, child: const Text('جرّب تاني')),
                ],
              ),
            ),
          ),
        ),
      );
}
