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
