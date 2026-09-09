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

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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

/// ترتيب الموديل للتلخيص النصي — الأقل رقمًا يظهر الأول.
/// A model's rank for text summarizing; lower sorts first.
///
/// المعيار عام مش مربوط بأرقام إصدارات معينة، عشان القايمة تفضل معقولة لما
/// جوجل تطرح موديلات جديدة من غير ما نعدّل الكود.
/// The rules are generic rather than pinned to version numbers, so the list
/// stays sensible as Google ships new models without us touching this code.
function rank(name: string): number {
  if (!name.startsWith("gemini-")) return 60; // gemma وغيرها
  let score = 0;
  if (name.includes("preview")) score += 20; // مش مستقر
  if (name.includes("exp")) score += 20;
  if (name.includes("image")) score += 15; // متخصص في الصور مش النص
  if (name.includes("lite")) score += 5; // أضعف في المهام الطويلة
  if (name.includes("flash")) score += 0; // الأنسب للتلخيص: سريع ورخيص
  else if (name.includes("pro")) score += 2;
  else score += 10;
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
async function withRetry(send: () => Promise<Response>): Promise<Attempt> {
  let response: Response | null = null;
  let errorBody = "";

  for (let attempt = 0; attempt < 3; attempt++) {
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

  const models: string[] = all
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

  // الترتيب بالفايدة مش بالأبجدية: أول عنصر في القايمة هو اللي التطبيق بيختاره
  // تلقائيًا، والترتيب الأبجدي بيحط موديلات تجريبية غريبة في المقدمة.
  // Ranked by usefulness, not alphabetically: the app auto-selects the first
  // entry, and alphabetical order puts odd experimental models at the top.
  models.sort((a, b) => rank(a) - rank(b) || a.localeCompare(b));

  // بنرجّع الإجمالي عشان نفرق بين "جوجل ردت فاضي" و"الفلتر بتاعنا فضّاها".
  // Return the raw total so "Google sent nothing" is distinguishable from
  // "our filter removed everything".
  return json({ models, total: all.length });
}

/// بيطلب رد JSON منظم من Gemini ويرجّعه كما هو.
/// Asks Gemini for one structured JSON reply and passes it straight back.
///
/// الردود المنظمة مش بتستفيد من البث — JSON نصّه مش مفيد قبل ما يكتمل — فبناخدها
/// دفعة واحدة بدل ما نعقّد الطرفين.
/// Structured replies gain nothing from streaming: half a JSON document is
/// useless, so we take it in one piece instead of complicating both ends.
async function generateJson(
  apiKey: string,
  model: string,
  system: string,
  prompt: string,
  files?: Array<{ mime_type?: string; data?: string }>,
): Promise<Response> {
  const parts: Array<Record<string, unknown>> = [];
  for (const f of files ?? []) {
    if (f?.data && f.mime_type) {
      parts.push({ inline_data: { mime_type: f.mime_type, data: f.data } });
    }
  }
  parts.push({ text: prompt });

  const attempt = await withRetry(() =>
    fetch(`${GEMINI_BASE}/models/${model}:generateContent?key=${apiKey}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: system }] },
        contents: [{ role: "user", parts }],
        generationConfig: {
          temperature: 0.3,
          responseMimeType: "application/json",
        },
      }),
    })
  );

  if (!attempt.response?.ok) return retryFailure(attempt);
  const upstream = attempt.response;

  const data = await upstream.json();
  const text = data?.candidates?.[0]?.content?.parts
    ?.map((p: { text?: string }) => p.text ?? "")
    .join("") ?? "";

  const blocked = data?.promptFeedback?.blockReason;
  if (blocked) return json({ error: `Gemini رفض المحتوى (${blocked}).` }, 422);

  try {
    // بنفك الترميز هنا عشان أي رد مش JSON يبان كخطأ واضح بدل ما يوصل للتطبيق
    // ويكسره وهو بيحاول يقراه.
    // Parsed here so a non-JSON reply surfaces as a clear error instead of
    // reaching the app and breaking it mid-read.
    return json({ result: JSON.parse(text) });
  } catch {
    return json({ error: "الموديل رجّع رد مش JSON.", detail: text.slice(0, 400) }, 502);
  }
}

/// بيبث التلخيص من Gemini للتطبيق على شكل NDJSON.
/// Streams the summary from Gemini to the app as NDJSON.
async function streamSummary(
  apiKey: string,
  model: string,
  system: string,
  prompt: string,
  files?: Array<{ mime_type?: string; data?: string }>,
): Promise<Response> {
  // الملف بيتحط قبل النص: جوجل بتوصي بترتيب الملف أولاً عشان التعليمات
  // اللي بعده تتفسّر في سياقه.
  // The file goes before the text: Google recommends leading with the file so
  // the instructions that follow are read in its context.
  const parts: Array<Record<string, unknown>> = [];
  for (const f of files ?? []) {
    if (f?.data && f.mime_type) {
      parts.push({ inline_data: { mime_type: f.mime_type, data: f.data } });
    }
  }
  parts.push({ text: prompt });

  const body = JSON.stringify({
    system_instruction: { parts: [{ text: system }] },
    contents: [{ role: "user", parts }],
    // حرارة منخفضة: عايزين اتباع أمين للأسلوب، مش إبداع.
    // Low temperature: faithful style-following, not invention.
    generationConfig: { temperature: 0.4 },
  });

  // الازدحام (503) شائع على الخطة المجانية وبيروح لوحده بعد ثواني. بنعيد
  // المحاولة هنا على السيرفر بدل ما نرمي الخطأ للمستخدم ويعيد إرسال المحاضرة كلها.
  // 503 overload is common on the free tier and usually clears in seconds.
  // Retrying here avoids making the user resend the whole lecture.
  const attempt = await withRetry(() =>
    fetch(
      `${GEMINI_BASE}/models/${model}:streamGenerateContent?alt=sse&key=${apiKey}`,
      { method: "POST", headers: { "Content-Type": "application/json" }, body },
    )
  );

  if (!attempt.response?.ok || !attempt.response.body) return retryFailure(attempt);
  const upstream = attempt.response;

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

  const apiKey = Deno.env.get("GEMINI_API_KEY");
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
    file?: { mime_type?: string; data?: string };
    files?: Array<{ mime_type?: string; data?: string }>;
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

    if (body.action === "summarize") {
      if (!body.model) return json({ error: "model is required" }, 400);
      if (!body.prompt) return json({ error: "prompt is required" }, 400);
      return await streamSummary(
        apiKey,
        body.model,
        body.system ?? "",
        body.prompt,
        body.files ?? (body.file ? [body.file] : undefined),
      );
    }

    if (body.action === "json") {
      if (!body.model) return json({ error: "model is required" }, 400);
      if (!body.prompt) return json({ error: "prompt is required" }, 400);
      return await generateJson(
        apiKey,
        body.model,
        body.system ?? "",
        body.prompt,
        body.files ?? (body.file ? [body.file] : undefined),
      );
    }

    return json({ error: `unknown action: ${body.action}` }, 400);
  } catch (e) {
    return json({ error: `${e}` }, 500);
  }
});
