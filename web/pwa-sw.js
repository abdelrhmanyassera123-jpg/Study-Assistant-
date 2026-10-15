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
const SHELL_CACHE = "app-shell-v1";

// النت الضعيف ما بيفشلش، بيعلّق. لو معانا نسخة محفوظة ما نستناش أكتر من
// كده؛ الطلب بيكمّل في الخلفية ويحدّث النسخة للفتحة الجاية.
// A weak connection does not fail, it hangs. With a saved copy we wait no
// longer than this; the request carries on in the background and refreshes
// the copy for the next open.
const NETWORK_TIMEOUT_MS = 4000;

async function savedCopy(cache, request) {
  const navigate = request.mode === "navigate";
  const saved = await cache.match(request, { ignoreSearch: navigate });
  if (saved || !navigate) return saved;
  // التطبيق صفحة واحدة: أي عنوان بيفتح نفس index.html.
  // The app is a single page: any address opens the same index.html.
  return (await cache.match(new URL("./", self.registration.scope).href, { ignoreSearch: true })) ||
    (await cache.match(new URL("index.html", self.registration.scope).href, { ignoreSearch: true }));
}

async function networkFirst(event) {
  const request = event.request;
  const cache = await caches.open(SHELL_CACHE);
  const live = fetch(request).then((response) => {
    if (response.ok || response.type === "opaque") {
      return cache.put(request, response.clone()).then(() => response, () => response);
    }
    return response;
  });
  event.waitUntil(live.catch(() => {}));

  const saved = await savedCopy(cache, request);
  if (!saved) return live;
  const timeout = new Promise((resolve) => setTimeout(() => resolve(null), NETWORK_TIMEOUT_MS));
  try {
    return (await Promise.race([live, timeout])) || saved;
  } catch (e) {
    return saved;
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(SHELL_CACHE);
  const saved = await cache.match(request);
  if (saved) return saved;
  const response = await fetch(request);
  if (response.ok || response.type === "opaque") cache.put(request, response.clone());
  return response;
}

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (event.request.method === "POST" && url.pathname.endsWith("/share-target")) {
    event.respondWith(handleShareTarget(event.request));
    return;
  }
  if (event.request.method !== "GET") return;

  // ملفات التطبيق نفسه (والخط ومحرك الرسم من جوجل): الشبكة الأول عشان
  // التحديثات توصل، والنسخة المحفوظة لو مفيش نت — كده التطبيق بيفتح أوفلاين.
  // The app's own files (plus Google's fonts and rendering engine): network
  // first so updates arrive, the saved copy when offline — so the app opens
  // without a connection.
  if (url.origin === self.location.origin && !url.pathname.startsWith("/__offline__/")) {
    event.respondWith(networkFirst(event));
    return;
  }
  if (/(^|\.)gstatic\.com$|^fonts\.googleapis\.com$/.test(url.hostname)) {
    event.respondWith(networkFirst(event));
    return;
  }
  // صور التلخيص من ويكيميديا ما بتتغيرش، فالمحفوظة الأول.
  // Summary pictures from Wikimedia never change, so the saved one first.
  if (url.hostname === "upload.wikimedia.org") {
    event.respondWith(cacheFirst(event.request));
    return;
  }
  // الباقي (Supabase، جوجل) بيعدّي زي ما هو — بياناته بتتحفظ من جوه التطبيق.
  // Everything else (Supabase, Google) passes through; its data is saved
  // from inside the app.
});

// بيدّي الملفات المشاركة مكان مؤقت (Cache Storage، دقيقة أو اتنين بالكتير) وبعدين
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
    const cache = await caches.open("share-target-cache");
    // مشاركة قديمة ما اتقرتش ما تتخلطش بالجديدة.
    // An old share that was never read must not mix with the new one.
    for (const key of await cache.keys()) await cache.delete(key);

    // كل الملفات مش أول واحد بس — ممكن تشارك تسجيل وسلايداته مع بعض.
    // Every file, not just the first — a recording and its slides can be
    // shared together.
    const files = formData.getAll("file").filter((f) => f && typeof f !== "string");
    for (let i = 0; i < files.length; i++) {
      await cache.put(
        `/shared-file/${i}`,
        new Response(files[i], {
          headers: {
            "Content-Type": files[i].type || "application/octet-stream",
            "X-File-Name": encodeURIComponent(files[i].name || "shared-file"),
          },
        }),
      );
    }

    // نص أو لينك متشارك (من واتساب، كروم، ...) بيروح لخانة نص المحاضرة.
    // Shared text or a link (from WhatsApp, Chrome, ...) goes to the lecture
    // text box.
    const text = ["title", "text", "url"]
      .map((k) => formData.get(k))
      .filter((v) => typeof v === "string" && v.trim())
      .join("\n");
    await cache.put(
      "/shared-meta",
      new Response(JSON.stringify({ count: files.length, text })),
    );
  } catch (e) {
    // فشل القراية مش سبب يوقّف التحويل — الصفحة هتلاقي مفيش حاجة وتكمّل.
    // A failed read is no reason to block the redirect — the page will find
    // nothing and carry on.
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

  // "اقفل": إشعار محاضرات النهاردة بعد آخر محاضرة — بيتشال بدل ما يتعرض جديد.
  // "Close": today's lectures notification after the last lecture, removed
  // instead of a new one being shown.
  if (data.close && data.tag) {
    event.waitUntil(
      self.registration.getNotifications({ tag: data.tag }).then((list) => {
        for (const n of list) n.close();
      }),
    );
    return;
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
    // إشعار محاضرات النهاردة بيبعت false: التحديث يحل محل القديم بهدوء.
    // Today's lectures notification sends false: the update quietly replaces
    // the old one.
    renotify: data.renotify !== false && !!data.tag,
    icon: "icons/Icon-192.png",
    badge: "icons/Icon-192.png",
    silent: !!data.silent,
    data: {
      url: data.url || "./",
      actions: Array.isArray(data.actions) ? data.actions : [],
    },
    actions: (Array.isArray(data.actions) ? data.actions : []).map((a) => ({
      action: a.action,
      title: a.title,
    })),
  };

  // الإشعار الصامت مينفعش يبقى معاه اهتزاز: المتصفح بيرفضه كله ومش بيظهر
  // حاجة (ده اللي كان مخبّي إشعار محاضرات النهاردة). الاهتزاز للمسموع بس.
  // A silent notification may not carry a vibration: the browser rejects the
  // whole thing and shows nothing (which is what hid today's lectures
  // notification). Vibration is for audible ones only.
  if (!options.silent) {
    options.vibrate = Array.isArray(data.vibrate) ? data.vibrate : [200, 100, 200];
  }

  // لو المتصفح رفض أي اختيار تاني، الإشعار يظهر بالأساسيات بدل ما يضيع.
  // Should the browser reject any other option, the notification still shows
  // with the basics instead of being lost.
  event.waitUntil(
    self.registration.showNotification(title, options).catch(() =>
      self.registration.showNotification(title, {
        body: options.body,
        tag: options.tag,
        icon: options.icon,
        data: options.data,
      })
    ),
  );
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
