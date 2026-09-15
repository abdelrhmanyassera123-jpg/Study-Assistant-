// Service worker مستقل بيفضل مسجّل — بيتاعنا مش بيتاع فلاتر.
// A standalone service worker that stays registered — ours, not Flutter's.
//
// نسخة فلاتر الحديثة (flutter_service_worker.js) بتسجّل نفسها وبعدين
// **تلغي تسجيلها على طول** كخطوة تنظيف لأي نسخة قديمة من الكاش عند
// المستخدمين الراجعين — مش نية تخريب، بس النتيجة إن كروم بيلاقي التطبيق
// من غير أي service worker مسجّل فعليًا وقت ما بيقرر يعرض زرار "تثبيت"،
// فبيرجع لخيار "إضافة اختصار" العادي بدل التثبيت الحقيقي. الملف ده منفصل
// تمامًا وهدفه الوحيد إنه يفضل مسجّل عشان يحقق الشرط ده، من غير أي علاقة
// بكاش فلاتر أو تحديثاته.
//
// A recent Flutter build (flutter_service_worker.js) registers itself and
// then **immediately unregisters** as a cleanup step for any stale cache
// from returning users on an older Flutter version — not a mistake, but the
// side effect is that Chrome finds no service worker actually registered by
// the time it decides whether to offer an "Install" button, so it falls
// back to the plain "Add shortcut" option instead of a real install. This
// file is entirely separate and exists only to stay registered and satisfy
// that check — it has nothing to do with Flutter's own caching or updates.

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

// مرّر أي طلب زي ما هو — مفيش كاش هنا، الهدف بس التسجيل نفسه.
// Pass every request straight through — no caching here, the point is
// simply staying registered.
self.addEventListener("fetch", (event) => {
  event.respondWith(fetch(event.request));
});

// تنبيه المحاضرة الجاي من السيرفر (send-reminders) — بيوصل حتى لو التطبيق
// مقفول خالص، عكس التنبيه المحلي في lib/core/notifications.dart اللي محتاج
// تاب مفتوح.
// A lecture reminder pushed from the server (send-reminders) — arrives even
// with the app fully closed, unlike the local notification in
// lib/core/notifications.dart which needs an open tab.
self.addEventListener("push", (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = {};
  }

  const title = data.title || "مساعد المذاكرة";
  const options = {
    body: data.body || "",
    tag: data.tag || undefined,
    // لو تنبيهين جم بنفس الـ tag (مش المفروض يحصل دلوقتي، كل معاد ليه tag
    // فريد بالسيرفر)، renotify يضمن إن الجديد يظهر ويهتز/يصوّت برضو بدل ما
    // يستبدل القديم بصمت من غير تنبيه.
    // If two notifications ever share a tag (shouldn't happen now — each
    // occurrence gets a unique tag server-side), renotify makes sure the new
    // one still alerts/vibrates instead of silently replacing the old one.
    renotify: true,
    icon: "icons/Icon-192.png",
    badge: "icons/Icon-192.png",
    silent: !!data.silent,
    vibrate: Array.isArray(data.vibrate) ? data.vibrate : [200, 100, 200],
    data: { url: "./" },
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// دوس على التنبيه يفتح تاب موجود أو تاب جديد على التطبيق.
// Tapping the notification focuses an existing tab or opens a new one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || "./";
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ("focus" in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    }),
  );
});
