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

// مرّر أي طلب زي ما هو — إلا مشاركة ملف من تطبيق تاني (Android share sheet)،
// دي بتوصل هنا كـ POST على "/share-target" ومفيش صفحة حقيقية ترد عليها.
// Pass every request straight through — except a file shared from another
// app (the Android share sheet), which arrives here as a POST to
// "/share-target" with no real page to answer it.
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method === "POST" && url.pathname.endsWith("/share-target")) {
    event.respondWith(handleShareTarget(event.request));
    return;
  }
  event.respondWith(fetch(event.request));
});

// بيدّي الملف المشارك مكان مؤقت (Cache Storage، دقيقة أو اتنين بالكتير) وبعدين
// بيحوّل لصفحة التطبيق العادية بـ ?shared=1 — الصفحة نفسها هي اللي بتقراه من
// هناك وتمسحه. لازم يرجّع تحويل (redirect) مش رد مباشر: المتصفح بيتنقّل
// لعنوان الـ POST ده، ومفيش HTML حقيقي نرسمه هنا.
// Gives the shared file a brief home (Cache Storage, a minute or two at
// most) then redirects to the app's normal page with ?shared=1 — the page
// itself reads it from there and deletes it. Must return a redirect, not a
// direct response: the browser navigates to this POST's URL, and there is
// no real HTML to render here.
async function handleShareTarget(request) {
  try {
    const formData = await request.formData();
    const file = formData.get("file");
    if (file) {
      const cache = await caches.open("share-target-cache");
      await cache.put(
        "/shared-file",
        new Response(file, {
          headers: {
            "Content-Type": file.type || "application/octet-stream",
            "X-File-Name": encodeURIComponent(file.name || "shared-file"),
          },
        }),
      );
    }
  } catch (e) {
    // فشل قراءة الملف مش سبب يوقّف التحويل — الصفحة هتلاقي مفيش ملف وتتجاهله.
    // A failed read is no reason to block the redirect — the page will find
    // no file and move on.
  }
  return Response.redirect("./?shared=1", 303);
}

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
    data: {
      url: data.url || "./",
      actions: Array.isArray(data.actions) ? data.actions : [],
    },
    actions: (Array.isArray(data.actions) ? data.actions : []).map((a) => ({
      action: a.action,
      title: a.title,
    })),
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// دوس على التنبيه يفتح تاب موجود أو تاب جديد على التطبيق.
// Tapping the notification focuses an existing tab or opens a new one.
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  // زرار جوه التنبيه ليه صفحته؛ الضغط على التنبيه نفسه بيفتح صفحته العامة.
  // A button inside the notification has its own page; tapping the
  // notification itself opens its general one.
  const action = (data.actions || []).find((a) => a.action === event.action);
  const url = (action && action.url) || data.url || "./";
  const target = new URL(url, self.registration.scope).href;
  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        // التاب المفتوح بيروح للصفحة المطلوبة بدل ما يتفتح تاب تاني.
        // An open tab goes to the requested page instead of opening another.
        if ("navigate" in client && target !== self.registration.scope) {
          return client.navigate(target).then((c) => (c || client).focus());
        }
        if ("focus" in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
    }),
  );
});
