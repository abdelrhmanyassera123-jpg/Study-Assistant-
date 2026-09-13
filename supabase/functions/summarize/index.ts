// =====================================================================
// summarize — وسيط بين التطبيق و Gemini
// =====================================================================
// سبب وجود الفنكشن دي إن مفتاح Gemini لازم يفضل على السيرفر. لو التطبيق نادى
// Gemini مباشرة، المفتاح هيبقى في ملفات الجافاسكريبت وأي حد يفتح الموقع
// يقدر يستخرجه ويستهلك الحصة.
//
// Why this function exists: the Gemini key must stay server-side. Calling
// Gemini straight from the Flutter app would ship the key inside the JS
// bundle, where anyone who opens the site can lift it and spend the quota.
//
// Supabase بيتحقق من الـ JWT قبل ما الطلب يوصل هنا (طالما ما اتنشرتش بـ
// --no-verify-jwt)، فاللي مش مسجّل دخول ما بيعديش من الأساس.
// Supabase verifies the JWT before the request reaches this code (as long as
// it isn't deployed with --no-verify-jwt), so anonymous callers never get in.
// =====================================================================

const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta";
const GEMINI_UPLOAD = "https://generativelanguage.googleapis.com/upload/v1beta";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  // هيدرز الرفع لازم تتذكر بالاسم: المتصفح بيرفض الطلب قبل ما يوصل أصلاً لو
  // هيدر مش مسموح بيه.
  // The upload headers must be named: the browser refuses the request before it
  // is even sent when one of them is not allowed.
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, " +
    "x-file-mime, x-file-size, x-file-name",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

/// بيتأكد إن اللي بينادي مستخدم مسجّل دخول فعلاً، مش الـ anon key.
/// Confirms the caller is a signed-in user, not the anon key.
///
/// تحقق Supabase الافتراضي بيقبل أي JWT موقّع من المشروع — والـ anon key
/// واحد منهم، وهو عام في كود الواجهة. من غير الفحص ده أي حد يفتح الموقع
/// يقدر يستهلك حصة Gemini. الإمضاء اتفحص قبل ما نوصل هنا، فقراءة الحمولة كفاية.
/// Supabase's built-in check accepts any JWT the project signed — and the anon
/// key is one of those, shipped publicly in the client. Without this, anyone
/// who opens the site could burn the Gemini quota. The signature is already
/// verified upstream, so reading the payload is enough.
function isSignedInUser(req: Request): boolean {
  const header = req.headers.get("Authorization") ?? "";
  const token = header.replace(/^Bearer\s+/i, "");
  const payloadPart = token.split(".")[1];
  if (!payloadPart) return false;

  try {
    const padded = payloadPart.replace(/-/g, "+").replace(/_/g, "/");
    const claims = JSON.parse(atob(padded.padEnd(
      padded.length + ((4 - (padded.length % 4)) % 4),
      "=",
    )));
    return claims.role === "authenticated" && typeof claims.sub === "string";
  } catch {
    return false;
  }
}

/// بيدوّر على مفتاح Gemini شخصي للمستخدم اللي بينادي، من جدول
/// "user_api_keys" — بيرجّع null لو مالوش مفتاح شخصي محفوظ.
///
/// بنستخدم توكن المستخدم نفسه (Authorization) بدل مفتاح الخدمة، عشان
/// Row Level Security على الجدول تحصر النتيجة في صف المستخدم ده بس تلقائيًا
/// — من غير ما نحتاج نفك التوكن أو نفلتر بـ user_id يدوي.
/// Looks up the calling user's personal Gemini key from "user_api_keys" —
/// returns null when they have none saved.
///
/// The caller's own token (Authorization) is used instead of a service key,
/// so Row Level Security on the table automatically scopes the result to
/// that user's own row — no need to decode the token or filter by user_id
/// by hand.
async function personalApiKey(req: Request): Promise<string | null> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const auth = req.headers.get("Authorization");
  if (!supabaseUrl || !anonKey || !auth) return null;

  try {
    const res = await fetch(
      `${supabaseUrl}/rest/v1/user_api_keys?select=gemini_api_key&limit=1`,
      { headers: { apikey: anonKey, Authorization: auth } },
    );
    if (!res.ok) return null;
    const rows = await res.json();
    const key = rows?.[0]?.gemini_api_key;
    return typeof key === "string" && key.trim() ? key.trim() : null;
  } catch {
    // فشل الاستعلام مش مبرر لإسقاط الطلب كله — بنكمل بالمفتاح المشترك.
    // A failed lookup is not a reason to drop the whole request — fall
    // through to the shared key.
    return null;
  }
}

/// ترتيب الموديل — الأقل رقمًا يظهر الأول.
/// A model's rank; lower sorts first.
///
/// المعيار عام مش مربوط بأرقام إصدارات معينة، عشان القايمة تفضل معقولة لما
/// جوجل تطرح موديلات جديدة من غير ما نعدّل الكود.
///
/// [preferPro] بتقلب الأولوية: جدول كثيف كلاسيكيًا محتاج قراية دقيقة لشبكة
/// أعمدة صغيرة أهم من سرعة الرد — flash بيجري أسرع بس بيغلط في عدّ الأعمدة،
/// وpro أبطأ لكن أدق في القراية البصرية المزدحمة دي.
/// The rules are generic rather than pinned to version numbers, so the list
/// stays sensible as Google ships new models without us touching this code.
///
/// [preferPro] flips the priority: a dense timetable needs precise reading of
/// a small column grid more than a fast reply — flash answers quicker but
/// miscounts columns, while pro is slower but more reliable at this kind of
/// crowded visual reading.
function rank(name: string, preferPro = false): number {
  if (!name.startsWith("gemini-")) return 60; // gemma وغيرها
  let score = 0;
  if (name.includes("preview")) score += 20; // مش مستقر
  if (name.includes("exp")) score += 20;
  if (name.includes("image")) score += 15; // متخصص في الصور مش النص
  if (name.includes("lite")) score += 5; // أضعف في المهام الطويلة
  if (preferPro) {
    if (name.includes("pro")) score += 0;
    else if (name.includes("flash")) score += 2;
    else score += 10;
  } else {
    if (name.includes("flash")) score += 0; // الأنسب للتلخيص: سريع ورخيص
    else if (name.includes("pro")) score += 2;
    else score += 10;
  }
  // "-latest" بيشاور على أحدث موديل، وأحدث موديل حصته المجانية أضيق —
  // المستخدم على المفتاح المجاني بيستفيد أكتر من نسخة مستقرة برقم ثابت.
  // "-latest" tracks the newest model, and the newest model carries the
  // tightest free-tier quota; a pinned stable version serves a free key better.
  if (name.endsWith("-latest")) score += 1;
  return score;
}

/// نتيجة محاولات النداء على Gemini.
/// The outcome of the Gemini call attempts.
interface Attempt {
  response: Response | null;
  /// جسم آخر رد فاشل، متقروء **مرة واحدة** ومتخزن.
  /// The last failed body, read **once** and kept.
  errorBody: string;
}

/// بيعيد المحاولة على الازدحام المؤقت (503) بس.
/// Retries transient overload (503) only.
///
/// الجسم بيتقرا مرة واحدة بس وبيتخزن: قراءة `Response` مرتين بترمي
/// "Body already consumed" وبتخفي الخطأ الحقيقي ورا خطأ مضلل.
/// The body is read exactly once and cached: reading a `Response` twice throws
/// "Body already consumed", burying the real error behind a misleading one.
async function withRetry(
  send: () => Promise<Response>,
  maxAttempts = 3,
): Promise<Attempt> {
  let response: Response | null = null;
  let errorBody = "";

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (attempt > 0) await new Promise((r) => setTimeout(r, attempt * 1500));

    response = await send();
    if (response.ok) return { response, errorBody: "" };

    errorBody = await response.text();
    // 429 معناها الحصة خلصت — إعادة المحاولة بتستهلك منها أكتر وبتأخر
    // الرسالة على المستخدم. 503 بس هي الازدحام اللي بيروح لوحده.
    // A 429 is a spent quota: retrying eats more of it and delays telling the
    // user. Only 503 is the transient congestion worth retrying.
    if (response.status !== 503) break;
  }

  return { response, errorBody };
}

/// بيجرب الموديلات بالترتيب لحد ما واحد يرد.
/// Tries models in order until one answers.
///
/// مش كل موديل في القايمة شغال على كل مفتاح: بعضهم بيرجع 404 (مش متاح للمفتاح
/// ده)، وبعضهم 429 (حصته خلصت). التسلسل بينتقل للي بعده بدل ما يوقف المستخدم.
/// Not every listed model works on every key: some answer 404 (not available to
/// this key), others 429 (quota spent). The cascade moves on instead of
/// stopping the user.
async function firstWorking(
  candidates: string[],
  send: (model: string) => Promise<Response>,
  maxAttemptsPerModel = 3,
): Promise<{ model: string; attempt: Attempt }> {
  let last: Attempt = { response: null, errorBody: "no model available" };

  for (const model of candidates) {
    const attempt = await withRetry(() => send(model), maxAttemptsPerModel);
    if (attempt.response?.ok) return { model, attempt };

    last = attempt;
    const status = attempt.response?.status ?? 0;
    // 404 و429 معناهم "جرب غيره"؛ أي خطأ تاني غالبًا في الطلب نفسه فالتبديل
    // مش هيصلحه.
    // 404 and 429 mean "try another"; any other status usually points at the
    // request itself, which switching models will not fix.
    if (status !== 404 && status !== 429 && status !== 503) break;
  }

  return { model: candidates.at(-1) ?? "", attempt: last };
}

function retryFailure(attempt: Attempt): Response {
  const status = attempt.response?.status ?? 0;
  return json(
    {
      error: `Gemini returned ${status}`,
      detail: attempt.errorBody || "no response",
    },
    status && status !== 200 ? status : 502,
  );
}

/// أسماء الموديلات المفلترة (من غير ترتيب)، متخزنة مؤقتًا لكل مفتاح لوحده.
/// The filtered model names (unsorted), briefly cached per key on its own.
///
/// نداء التسلسل التلقائي محتاج القايمة قبل كل تلخيص؛ من غير التخزين ده هيبقى
/// في طلب زيادة لجوجل مع كل مرة. الترتيب اتفصل عن الفلترة عشان تفضيلة واحدة
/// (زي [preferPro]) ما تحتاجش تجيب القايمة من جوجل تاني — بترتب اللي اتخزن
/// بس.
///
/// **متخزنة لكل مفتاح لوحده**: من ساعة ما بقى فيه مفاتيح شخصية للمستخدمين،
/// موديلات مفتاح مستخدم ممكن تختلف تمامًا عن موديلات مفتاح تاني — تخزين
/// عام واحد كان هيسرّب قايمة مفتاح لطلبات مفتاح تاني.
/// Auto-mode needs the list before every summary; without this cache that is
/// an extra Google request each time. Sorting is split from filtering so a
/// one-off preference (like [preferPro]) does not need a fresh fetch — it
/// just re-sorts what is already cached.
///
/// **Cached per key on its own**: now that users can carry personal keys, one
/// key's models can differ entirely from another's — a single shared cache
/// would leak one key's list into another key's requests.
const filteredCache = new Map<string, { names: string[]; at: number }>();
const RANKED_TTL_MS = 10 * 60 * 1000;

async function filteredModelNames(apiKey: string): Promise<string[]> {
  const cached = filteredCache.get(apiKey);
  if (cached && Date.now() - cached.at < RANKED_TTL_MS) {
    return cached.names;
  }
  const upstream = await fetch(`${GEMINI_BASE}/models?key=${apiKey}&pageSize=200`);
  if (!upstream.ok) {
    await upstream.text();
    return [];
  }
  const names = filterModelNames(await upstream.json());
  filteredCache.set(apiKey, { names, at: Date.now() });
  return names;
}

async function rankedModels(apiKey: string, preferPro = false): Promise<string[]> {
  const names = await filteredModelNames(apiKey);
  return sortModels(names, preferPro);
}

/// بيرجّع الموديلات اللي بتدعم التوليد بالبث.
/// Returns the models that support streaming generation.
async function listModels(apiKey: string): Promise<Response> {
  const upstream = await fetch(`${GEMINI_BASE}/models?key=${apiKey}&pageSize=200`);

  if (!upstream.ok) {
    return json(
      { error: `Gemini returned ${upstream.status}`, detail: await upstream.text() },
      upstream.status,
    );
  }

  const body = await upstream.json();
  const all: Array<{ name?: string; supportedGenerationMethods?: string[] }> =
    body.models ?? [];

  const models = sortModels(filterModelNames(body));

  // بنرجّع الإجمالي عشان نفرق بين "جوجل ردت فاضي" و"الفلتر بتاعنا فضّاها".
  // Return the raw total so "Google sent nothing" is distinguishable from
  // "our filter removed everything".
  return json({ models, total: all.length });
}

/// بيفلتر رد قائمة الموديلات لأسماء صالحة للتلخيص، من غير ترتيب.
/// Filters the model-list response to names usable for summarizing, unsorted.
function filterModelNames(body: {
  models?: Array<{ name?: string; supportedGenerationMethods?: string[] }>;
}): string[] {
  const all = body.models ?? [];
  return all
    .filter((m) => {
      // الفلتر متسامح بقصد: لو جوجل ما رجّعتش قائمة الطرق المدعومة، بنعتبر
      // الموديل صالح بدل ما نشيله. الفلترة الصارمة كانت بتفضي القائمة كلها.
      // Deliberately tolerant: when Google omits the supported-methods list we
      // keep the model rather than drop it. Strict filtering emptied the list.
      const methods = m.supportedGenerationMethods;
      if (!Array.isArray(methods) || methods.length === 0) return true;
      return methods.includes("streamGenerateContent") ||
        methods.includes("generateContent");
    })
    // بنشيل بادئة "models/" عشان الاسم يبقى مقروء في القايمة.
    // Strip the "models/" prefix so the dropdown reads cleanly.
    .map((m) => (m.name ?? "").replace(/^models\//, ""))
    .filter((name) =>
      name.length > 0 &&
      // موديلات التضمين والصور والصوت مش بتلخص نص.
      // Embedding, image and audio models don't summarize text.
      !name.includes("embedding") &&
      !name.includes("imagen") &&
      !name.includes("veo") &&
      !name.includes("tts")
    );
}

/// بيرتّب أسماء موديلات مفلترة بالفايدة مش بالأبجدية.
/// Sorts already-filtered model names by usefulness, not alphabetically.
function sortModels(names: string[], preferPro = false): string[] {
  // الأول في القايمة هو اللي بيتجرب الأول.
  // The first entry is the one tried first.
  return [...names].sort((a, b) =>
    rank(a, preferPro) - rank(b, preferPro) || a.localeCompare(b)
  );
}

/// ملف داخل الطلب: إما بايتاته جوه الطلب، أو إشارة لملف مرفوع عند جوجل.
/// A file in the request: either its bytes inline, or a pointer at a file
/// already uploaded to Google.
interface RequestFile {
  mime_type?: string;
  data?: string;
  file_uri?: string;
}

/// بيحوّل الملفات لأجزاء زي ما Gemini مستنيها.
/// Turns the files into the parts Gemini expects.
///
/// الملف الكبير ما بيعديش جوه الطلب: حد النداء الواحد 20 ميجا، وترميز base64
/// بيزود الحجم الثلث. الملفات الكبيرة بتترفع مرة واحدة على Files API وبعدين
/// بيتشار لها بالرابط، والمحاضرة الساعتين بتعدي في نداء واحد.
/// A large file cannot travel inside the request: one call caps at 20 MB and
/// base64 adds a third on top. Large files are uploaded once to the Files API
/// and then referenced by URI, which lets a two-hour lecture go in one call.
function fileParts(files?: RequestFile[]): Array<Record<string, unknown>> {
  const parts: Array<Record<string, unknown>> = [];
  for (const f of files ?? []) {
    if (!f?.mime_type) continue;
    if (f.file_uri) {
      parts.push({ file_data: { mime_type: f.mime_type, file_uri: f.file_uri } });
    } else if (f.data) {
      parts.push({ inline_data: { mime_type: f.mime_type, data: f.data } });
    }
  }
  return parts;
}

/// بيرفع ملف لـ Files API بتاعة جوجل **بالتمرير**.
/// Streams a file up to Google's Files API.
///
/// جسم الطلب بيتمرر زي ما هو من المتصفح لجوجل من غير ما يتجمع في ذاكرة
/// الفنكشن. ده الفرق بين محاضرة 80 ميجا بتعدي، وبين WORKER_RESOURCE_LIMIT.
/// The request body is piped straight from the browser to Google without ever
/// being gathered in the function's memory. That is the difference between an
/// 80 MB lecture going through and a WORKER_RESOURCE_LIMIT.
///
/// الملف بيقعد عند جوجل 48 ساعة وبعدين بيتمسح لوحده — مفيش تخزين بنديره.
/// The file lives 48 hours at Google then deletes itself; there is no storage
/// for us to manage.
async function uploadFile(apiKey: string, req: Request): Promise<Response> {
  const mime = req.headers.get("x-file-mime") ?? "application/octet-stream";
  const size = req.headers.get("x-file-size") ?? "";
  const name = req.headers.get("x-file-name") ?? "lecture";

  if (!req.body) return json({ error: "no file body" }, 400);
  if (!/^\d+$/.test(size)) return json({ error: "x-file-size is required" }, 400);

  // 1) بنقول لجوجل إن في رفع جاي وبكام — بترجّع رابط الرفع.
  // 1) Tell Google a upload is coming and how big; it returns the upload URL.
  const start = await fetch(`${GEMINI_UPLOAD}/files?key=${apiKey}`, {
    method: "POST",
    headers: {
      "X-Goog-Upload-Protocol": "resumable",
      "X-Goog-Upload-Command": "start",
      "X-Goog-Upload-Header-Content-Length": size,
      "X-Goog-Upload-Header-Content-Type": mime,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ file: { display_name: name } }),
  });

  const uploadUrl = start.headers.get("x-goog-upload-url");
  if (!start.ok || !uploadUrl) {
    return json({
      error: `Gemini returned ${start.status}`,
      detail: await start.text(),
    }, start.status === 200 ? 502 : start.status);
  }
  await start.text();

  // 2) البايتات بتتمرر من طلب المتصفح لطلب جوجل مباشرة.
  // 2) The bytes are piped from the browser's request into Google's.
  const put = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      "Content-Length": size,
      "X-Goog-Upload-Offset": "0",
      "X-Goog-Upload-Command": "upload, finalize",
    },
    body: req.body,
    // مطلوبة عشان الجسم يبقى تيار مش بايتات متجمعة.
    // Required for the body to be a stream rather than gathered bytes.
    duplex: "half",
  } as RequestInit);

  if (!put.ok) {
    return json({
      error: `Gemini returned ${put.status}`,
      detail: await put.text(),
    }, put.status);
  }

  const info = await put.json();
  const file = info?.file ?? {};
  if (!file.uri || !file.name) {
    return json({ error: "الرفع رجع من غير رابط ملف." }, 502);
  }

  // 3) الصوت بيتعالج عند جوجل قبل ما يبقى صالح للقراية.
  // 3) Audio is processed at Google's end before it can be read.
  const ready = await waitForActive(apiKey, file.name, file.state);
  return json({
    uri: file.uri,
    name: file.name,
    mime_type: file.mimeType ?? mime,
    state: ready,
  });
}

/// بيستنى الملف لحد ما يبقى جاهز، وبيسيبه لو طوّل.
/// Waits until the file is ready, giving up if it takes too long.
///
/// الفنكشن نفسها ليها سقف وقت، فبنستنى لحد حد معقول وبنرجّع الحالة زي ما هي؛
/// التطبيق بيقدر يسأل تاني بدل ما الطلب يموت.
/// The function has its own time budget, so we wait up to a sane bound and
/// return the state as it stands; the app can ask again instead of the request
/// dying.
async function waitForActive(
  apiKey: string,
  name: string,
  state: string,
  attempts = 12,
): Promise<string> {
  let current = state;
  for (let i = 0; i < attempts && current === "PROCESSING"; i++) {
    await new Promise((r) => setTimeout(r, 2500));
    const res = await fetch(`${GEMINI_BASE}/${name}?key=${apiKey}`);
    if (!res.ok) {
      await res.text();
      break;
    }
    current = (await res.json())?.state ?? current;
  }
  return current;
}

/// بيرجّع حالة ملف مرفوع.
/// Returns an uploaded file's state.
async function fileState(apiKey: string, name: string): Promise<Response> {
  const res = await fetch(`${GEMINI_BASE}/${name}?key=${apiKey}`);
  if (!res.ok) {
    return json({ error: `Gemini returned ${res.status}`, detail: await res.text() },
      res.status);
  }
  const body = await res.json();
  return json({ state: body?.state ?? "UNKNOWN", uri: body?.uri });
}

/// بيطلب رد JSON منظم من Gemini ويرجّعه NDJSON: بينج دوري وسطر نتيجة أخير.
/// Asks Gemini for one structured JSON reply and relays it as NDJSON: a
/// periodic heartbeat, then one final result line.
///
/// أقل موديلات وأقل إعادة محاولة لنداءات الملفات (مضبوطة في نداء الفنكشن)
/// بتقصّر الانتظار في الغالب، لكن مستند معقد لسه ممكن ياخد وقت طويل عند
/// جوجل وحده. النداء نفسه مش بث عند جوجل، فالفنكشن هتفضل ساكتة تمامًا وهي
/// مستنية — وده اللي كان بيضرب حد الخمول عند Supabase (546 قبل كده،
/// "IDLE_TIMEOUT" بعد 150 ثانية بعد كده). البينج بيخلي بايتات تتبعت باستمرار
/// من غير ما يتغيّر شكل النتيجة النهائية.
///
/// **اتفحص محليًا قبل النشر** بسيرفر Node بسيط بنفس المنطق (بينج كل نص
/// ثانية + سطر نتيجة أخير) وعميل بيقرا NDJSON زي عميل Flutter بالظبط: البايتات
/// وصلت لحظة بلحظة مش دفعة واحدة، وتقسيم الأسطر شغال حتى لو كذا سطر وصلوا
/// في نفس الحزمة الشبكية.
/// Fewer candidate models and fewer retries for file-bearing calls (set at
/// the call site) usually shorten the wait, but a genuinely complex document
/// can still take Google a long time on its own. The call itself is not a
/// stream at Google's end, so the function would otherwise sit completely
/// silent while waiting — which is what tripped Supabase's idle limit (546
/// before, "IDLE_TIMEOUT" after 150s afterward). The heartbeat keeps bytes
/// flowing continuously without changing the shape of the final result.
///
/// **Verified locally before shipping this time**: a small Node server with
/// the identical logic (heartbeat every 500ms, one final result line) and a
/// client reading NDJSON the same way the Flutter client does — bytes
/// arrived incrementally, not all at once, and line-splitting held up even
/// when several lines landed in the same network packet.
function generateJson(
  apiKey: string,
  candidates: string[],
  system: string,
  prompt: string,
  files?: RequestFile[],
  maxAttemptsPerModel = 3,
): Response {
  const parts = fileParts(files);
  parts.push({ text: prompt });

  const body = JSON.stringify({
    system_instruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts }],
    // من غير سقف صريح، رد كثيف (جدول فيه عشرات المحاضرات) بيتقطع فجأة في
    // نص الـ JSON (finishReason: "MAX_TOKENS") بمجرد ما يوصل لسقف افتراضي
    // للموديل — وده بالظبط اللي كان بيظهر للمستخدم كـ"رد فاضي" غير مفهوم.
    // موديلات التفكير (زي Gemini 2.5/3) بتحسب توكنز التفكير من نفس السقف
    // كمان، فالسقف الافتراضي بيتاكل قبل ما يوصل للرد الفعلي على جدول معقد.
    // Without an explicit ceiling, a dense reply (a table with dozens of
    // lectures) gets cut mid-JSON ("MAX_TOKENS") the moment it hits a
    // model's default cap — this is exactly what showed up to the user as
    // an unparseable "empty reply". Thinking models (Gemini 2.5/3) also
    // charge their reasoning tokens against that same cap, so the default
    // gets eaten before the real answer on a complex table.
    generationConfig: {
      temperature: 0.3,
      responseMimeType: "application/json",
      maxOutputTokens: 65536,
    },
  });

  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    async start(controller) {
      const emit = (obj: unknown) =>
        controller.enqueue(encoder.encode(`${JSON.stringify(obj)}\n`));

      const heartbeat = setInterval(() => emit({ pending: true }), 15_000);

      try {
        const picked = await firstWorking(
          candidates,
          (model) =>
            fetch(`${GEMINI_BASE}/models/${model}:generateContent?key=${apiKey}`, {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body,
            }),
          maxAttemptsPerModel,
        );

        if (!picked.attempt.response?.ok) {
          const status = picked.attempt.response?.status || 502;
          emit({
            error: `Gemini returned ${status}`,
            detail: picked.attempt.errorBody || "no response",
            status,
          });
          return;
        }

        const upstream = picked.attempt.response;
        const model = picked.model;

        const data = await upstream.json();
        const text = data?.candidates?.[0]?.content?.parts
          ?.map((p: { text?: string }) => p.text ?? "")
          .join("") ?? "";

        const blocked = data?.promptFeedback?.blockReason;
        if (blocked) {
          emit({ error: `Gemini رفض المحتوى (${blocked}).`, status: 422 });
          return;
        }

        try {
          // بنفك الترميز هنا عشان أي رد مش JSON يبان كخطأ واضح بدل ما يوصل
          // للتطبيق ويكسره وهو بيحاول يقراه.
          // Parsed here so a non-JSON reply surfaces as a clear error instead
          // of reaching the app and breaking it mid-read.
          emit({ result: JSON.parse(text), model });
        } catch {
          emit({
            error: "الموديل رجّع رد مش JSON.",
            detail: text.slice(0, 400),
            status: 502,
          });
        }
      } catch (e) {
        emit({ error: `${e}`, status: 500 });
      } finally {
        clearInterval(heartbeat);
        controller.close();
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/x-ndjson",
      "Cache-Control": "no-cache",
    },
  });
}

/// بيبث التلخيص من Gemini للتطبيق على شكل NDJSON.
/// Streams the summary from Gemini to the app as NDJSON.
async function streamSummary(
  apiKey: string,
  candidates: string[],
  system: string,
  prompt: string,
  files?: RequestFile[],
  temperature = 0.4,
): Promise<Response> {
  // الملف بيتحط قبل النص: جوجل بتوصي بترتيب الملف أولاً عشان التعليمات
  // اللي بعده تتفسّر في سياقه.
  // The file goes before the text: Google recommends leading with the file so
  // the instructions that follow are read in its context.
  const parts = fileParts(files);
  parts.push({ text: prompt });

  const body = JSON.stringify({
    system_instruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts }],
    // حرارة منخفضة: عايزين اتباع أمين للأسلوب، مش إبداع. والتفريغ الصوتي
    // بيبعت صفر — نقل حرفي مش صياغة.
    // Low temperature: faithful style-following, not invention. Transcription
    // sends zero: it copies what was said rather than phrasing it.
    generationConfig: { temperature },
  });

  // الازدحام (503) شائع على الخطة المجانية وبيروح لوحده بعد ثواني. بنعيد
  // المحاولة هنا على السيرفر بدل ما نرمي الخطأ للمستخدم ويعيد إرسال المحاضرة كلها.
  // 503 overload is common on the free tier and usually clears in seconds.
  // Retrying here avoids making the user resend the whole lecture.
  const picked = await firstWorking(
    candidates,
    (model) =>
      fetch(
        `${GEMINI_BASE}/models/${model}:streamGenerateContent?alt=sse&key=${apiKey}`,
        { method: "POST", headers: { "Content-Type": "application/json" }, body },
      ),
  );

  if (!picked.attempt.response?.ok || !picked.attempt.response.body) {
    return retryFailure(picked.attempt);
  }
  const upstream = picked.attempt.response;

  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  const reader = upstream.body.getReader();

  // الرد SSE، بنحوّله NDJSON عشان يبقى نفس شكل Ollama على جهة التطبيق.
  // The upstream is SSE; we re-emit NDJSON so the app parses both providers
  // through one code path.
  const stream = new ReadableStream({
    async start(controller) {
      const emit = (obj: unknown) =>
        controller.enqueue(encoder.encode(`${JSON.stringify(obj)}\n`));

      // أول سطر بيقول أي موديل رد فعلاً — التطبيق محتاجه عشان يعدّ الاستهلاك
      // ويعرض اللي اشتغل، خصوصًا في الوضع التلقائي.
      // The first line names the model that actually answered; the app needs it
      // to count usage and show what ran, especially in auto mode.
      emit({ model: picked.model });

      // الحزم بتتقطع في نص السطر، فبنمسك الباقي لحد ما السطر يكتمل.
      // Packets split mid-line, so hold the remainder until a line completes.
      let buffered = "";

      const handleLine = (line: string) => {
        if (!line.startsWith("data:")) return;

        const payload = line.slice(5).trim();
        if (!payload || payload === "[DONE]") return;

        try {
          const chunk = JSON.parse(payload);

          const blocked = chunk.promptFeedback?.blockReason;
          if (blocked) {
            emit({ error: `Gemini رفض المحتوى (${blocked}).` });
            return;
          }

          const parts = chunk.candidates?.[0]?.content?.parts ?? [];
          for (const part of parts) {
            if (typeof part.text === "string" && part.text.length > 0) {
              emit({ text: part.text });
            }
          }

          const finish = chunk.candidates?.[0]?.finishReason;
          if (finish && finish !== "STOP") {
            emit({ error: `التوليد وقف بسبب: ${finish}` });
          }
        } catch {
          // سطر مش JSON صالح — بنتجاهله بدل ما نكسر البث كله.
          // A malformed line is skipped rather than killing the whole stream.
        }
      };

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffered += decoder.decode(value, { stream: true });
          const lines = buffered.split("\n");
          buffered = lines.pop() ?? "";
          for (const line of lines) handleLine(line.trim());
        }
        if (buffered.trim()) handleLine(buffered.trim());
        emit({ done: true });
      } catch (e) {
        emit({ error: `${e}` });
      } finally {
        controller.close();
        reader.releaseLock();
      }
    },
  });

  return new Response(stream, {
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/x-ndjson",
      "Cache-Control": "no-cache",
    },
  });
}

/// بيحدد الموديلات اللي هتتجرب: واحد بعينه، ولا القايمة المرتّبة في الوضع
/// التلقائي.
/// Decides which models to try: one named model, or the ranked list in auto
/// mode.
async function candidatesFor(
  apiKey: string,
  model?: string,
  limit = 5,
  preferPro = false,
  preferredModel?: string,
): Promise<string[]> {
  if (model && model != "auto") return [model];

  const ranked = await rankedModels(apiKey, preferPro);

  // موديل معيّن اتأكد إنه بيقرا الحالة دي أدق (زي preview موديل جدول
  // الجداول)، بس مش كل مفتاح بالضرورة عنده وصول له — يتقدّم على الترتيب
  // العادي، وباقي القايمة المرتّبة بتفضل ورا كخط رجعة.
  // A specific model confirmed to read this case more accurately (like the
  // preview model for schedule tables), but not every key necessarily has
  // access to it — it goes first, with the normally-ranked list kept behind
  // it as a fallback.
  const withPreferred = preferredModel
    ? [preferredModel, ...ranked.filter((m) => m !== preferredModel)]
    : ranked;

  // بنقف عند الحد المطلوب: بعد كده الانتظار بيبقى أطول من فايدته للمستخدم.
  // Capped at the requested limit: past that the wait costs the user more
  // than it buys.
  return withPreferred.slice(0, limit);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "POST only" }, 405);
  }

  if (!isSignedInUser(req)) {
    return json({ error: "لازم تكون مسجّل دخول." }, 401);
  }

  // مفتاح المستخدم الشخصي (لو محطوط) بيتقدّم على المفتاح المشترك — بيستهلك
  // من حصته هو بس، بدل ما يشارك حصة كل مستخدمين التطبيق.
  // The user's own key (when set) is preferred over the shared one — it
  // spends from their own quota instead of sharing every app user's quota.
  const personalKey = await personalApiKey(req);
  const apiKeyEarly = personalKey ?? Deno.env.get("GEMINI_API_KEY");

  // الرفع بيتحدد من الرابط مش من الجسم: الجسم نفسه هو الملف، وقرايته كـ JSON
  // هي بالظبط اللي بنحاول نتجنبه.
  // Uploads are named in the URL rather than the body: the body *is* the file,
  // and reading it as JSON is exactly what we are avoiding.
  const action = new URL(req.url).searchParams.get("action");
  if (action === "upload") {
    if (!apiKeyEarly) return json({ error: "GEMINI_API_KEY مش متظبط." }, 500);
    try {
      return await uploadFile(apiKeyEarly, req);
    } catch (e) {
      return json({ error: `${e}` }, 500);
    }
  }

  const apiKey = apiKeyEarly;
  if (!apiKey) {
    return json(
      {
        error: "GEMINI_API_KEY مش متظبط.",
        detail: "npx supabase secrets set GEMINI_API_KEY=...",
      },
      500,
    );
  }

  let body: {
    action?: string;
    model?: string;
    system?: string;
    prompt?: string;
    file?: RequestFile;
    files?: RequestFile[];
    temperature?: number;
    file_name?: string;
    prefer_pro?: boolean;
    preferred_model?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  try {
    if (body.action === "models") {
      return await listModels(apiKey);
    }

    if (body.action === "file_state") {
      if (!body.file_name) return json({ error: "file_name is required" }, 400);
      return await fileState(apiKey, body.file_name);
    }

    if (body.action === "summarize") {
      if (!body.prompt) return json({ error: "prompt is required" }, 400);
      return await streamSummary(
        apiKey,
        await candidatesFor(apiKey, body.model),
        body.system ?? "",
        body.prompt,
        body.files ?? (body.file ? [body.file] : undefined),
        typeof body.temperature === "number" ? body.temperature : undefined,
      );
    }

    if (body.action === "json") {
      if (!body.prompt) return json({ error: "prompt is required" }, 400);
      const files = body.files ?? (body.file ? [body.file] : undefined);
      // نداءات الملفات (جدول، تحليل شكل) قيسناها حقيقي: موديل واحد بيرد في
      // ~117 ثانية، لكن لو الأول فشل وعدّى لتاني **بعد ما استهلك وقته
      // بمحاولة حقيقية بطيئة**، ده وحده وصل لـ ~126 ثانية — قريب جدًا من حد
      // الـ 150. الخطر ده خاص بمحاولتين بطيئتين ورا بعض، مش برفض سريع
      // (404 لموديل مش متاح للمفتاح، أو 429 حصته خلصت) اللي بيرجع فورًا من
      // غير ما ياخد وقت حقيقي. فبنسيب مرشّح واحد بس عادةً، وبنسمح باتنين
      // بس لما `preferPro` مفعّلة — موديلات pro مش دايمًا متاحة لكل مفتاح
      // مجاني، فلو الأول (pro) اترفض فورًا، التاني (flash غالبًا) بياخد
      // نفس الوقت وكأنه المحاولة الأولى، من غير ما يضيف وقت حقيقي فوقه.
      // File-bearing calls (schedule, style analysis) were measured for
      // real: one model answers in ~117s, but falling back to a second
      // candidate **after it burned its own time on a real slow attempt**
      // alone took ~126s — uncomfortably close to the 150s ceiling. That
      // risk is specific to two slow attempts stacking, not to a fast
      // rejection (404 for a model unavailable to this key, or 429 spent
      // quota) which returns immediately without spending real time. So
      // this stays at one candidate normally, but allows two when
      // `preferPro` or `preferred_model` is set — neither is guaranteed
      // available on a free key, and if the first is rejected outright, the
      // second (usually flash) costs the same as if it had been tried
      // first, with no real time added on top.
      const wantsFallback = body.prefer_pro === true || !!body.preferred_model;
      const jsonMaxCandidates = files?.length ? (wantsFallback ? 2 : 1) : 5;
      const jsonMaxAttempts = files?.length ? 1 : 3;
      return await generateJson(
        apiKey,
        await candidatesFor(
          apiKey,
          body.model,
          jsonMaxCandidates,
          body.prefer_pro === true,
          body.preferred_model,
        ),
        body.system ?? "",
        body.prompt,
        files,
        jsonMaxAttempts,
      );
    }

    return json({ error: `unknown action: ${body.action}` }, 400);
  } catch (e) {
    return json({ error: `${e}` }, 500);
  }
});
