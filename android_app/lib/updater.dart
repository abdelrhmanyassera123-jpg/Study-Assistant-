import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config.dart';

/// بيشوف فيه نسخة APK أحدث على GitHub ولا لأ، ولو فيه بيعرض "حدّث".
/// Checks GitHub for a newer APK and, if there is one, offers to update.
///
/// كل push بيبني نسخة رقمها رقم البناء (android-37 مثلًا)، ونفس الرقم بيبقى
/// buildNumber جوه التطبيق — فالمقارنة رقم برقم.
/// Every push builds a release numbered by its build (android-37, say), and
/// the same number is the app's buildNumber, so the comparison is number to
/// number.
///
/// الموقع نفسه بيتحدّث لوحده من غير ده؛ ده لتحديثات التطبيق بس (الإشعارات،
/// الصلاحيات)، وده نادر.
/// The site updates by itself without this; this is only for updates to the
/// app (notifications, permissions), which are rare.
Future<void> checkForUpdate(BuildContext context) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final mine = int.tryParse(info.buildNumber) ?? 0;

    final res = await http
        .get(
          Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return;
    final release = jsonDecode(res.body) as Map<String, dynamic>;
    final latest = int.tryParse('${release['tag_name']}'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (latest <= mine) return;

    final assets = (release['assets'] as List? ?? const []).cast<Map>();
    final apk = assets.where((a) => '${a['name']}'.endsWith('.apk')).firstOrNull;
    if (apk == null || !context.mounted) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('فيه تحديث للتطبيق'),
          content: const Text(
            'هيتحمّل ملف التحديث، افتحه من الإشعارات واضغط "تثبيت". داتاك مش هتتأثر.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بعدين')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حدّث')),
          ],
        ),
      ),
    );
    if (go == true) {
      await launchUrl(Uri.parse('${apk['browser_download_url']}'), mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // من غير نت أو GitHub مش راد — نحاول تاني الفتحة الجاية.
    // No connection, or GitHub not answering: try again next open.
  }
}
