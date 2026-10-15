# تطبيق أندرويد — مساعد المذاكرة

تطبيق أندرويد بيفتح الموقع (https://study-assistant-ten-psi.vercel.app) جواه،
وجنبه إشعارات أصلية متجدولة على الموبايل نفسه.

An Android app that opens the site inside a WebView, with native notifications
scheduled on the phone itself.

## إيه اللي فيه — What it does

| الجزء | بيعمل إيه |
|---|---|
| `main.dart` | الموقع جوه WebView: اختيار الملفات، الميكروفون، زرار الرجوع، واللينكات اللي برّه بتفتح في المتصفح |
| `timetable.dart` | بيقرا جلسة الموقع ويجيب الجدول وإعدادات التنبيه، ويحفظهم على الموبايل |
| `digest.dart` | قواعد إشعار محاضرات النهاردة — نفس `supabase/functions/_shared/today_digest.ts` |
| `table_image.dart` | بيرسم جدول اليوم صورة للإشعار المفتوح — نفس شكل `web/digest_table.js` |
| `notifier.dart` | بيجدول الإشعارات أسبوعيًا: إشعار اليوم بيتحدّث مع كل محاضرة، وتنبيه قبل كل واحدة |
| `updater.dart` | لو فيه APK أحدث على GitHub بيعرض "حدّث" |

## التحديثات — Updates

- **الموقع** بيتحدّث لوحده: أي push على `main` بيوصل للتطبيق فورًا.
- **التطبيق نفسه** (الكود اللي هنا): أي push بيغيّر `android_app/` بيخلّي
  GitHub Actions (`.github/workflows/android.yml`) يبني APK وينشره كـ Release
  باسم `android-<رقم>`. التطبيق المتثبّت بيلاقيه أول ما يفتح ويعرض "حدّث".

## التوقيع — Signing

كل نسخة لازم تتوقّع بنفس المفتاح، وإلا أندرويد يرفض التحديث فوق القديمة.
المفتاح في `D:\programming\study-assistant-signing` (برّه الريبو)، ونسخة منه
متشفّرة في GitHub Secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`).
**خلّي نسخة من الفولدر ده في مكان آمن.**

## حدود — Limits

- تصدير PDF/صورة من جوه الموقع ممكن ما يشتغلش جوه التطبيق (التحميل من
  WebView محدود) — استخدم الموقع من المتصفح لده.
- أندرويد 14 وما بعده بيسمح بسحب أي إشعار؛ إشعار اليوم بيرجع مع اللحظة الجاية.
