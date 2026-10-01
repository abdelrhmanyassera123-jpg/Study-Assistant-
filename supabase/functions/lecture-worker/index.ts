// =====================================================================
// lecture-worker — بيكمّل تلخيص المحاضرات على السيرفر
// lecture-worker — carries lecture summaries forward on the server
// =====================================================================
// بيتنادى كل دقيقة من الكرون (لو فيه شغل مستني)، ومن التطبيق نفسه أول ما
// شغل جديد يتحط عشان ما يستناش الدقيقة. كل نداء بيحجز شغل أو اتنين وبيمشّيهم
// خطوة خطوة لحد ما وقته يقرّب يخلص، وكل خطوة بتتحفظ أول ما تخلص — فالنداء
// اللي بعده بيكمّل من مكانه.
//
// Called every minute by the cron (when work is waiting), and by the app
// itself as soon as new work is queued so it need not wait for the minute.
// Each run claims a job or two and walks them step by step until its time
// is nearly up; every step is saved the moment it finishes, so the next
// run continues from there.
//
// النداءات للموديل بتعدّي على فنكشن summarize نفسها بالنيابة عن المستخدم:
// اختيار الموديل، الانتقال لما واحد يفشل، ومفتاح المستخدم الشخصي — كلهم في
// مكان واحد.
// Model calls go through the summarize function itself on the user's behalf:
// model choice, fallback when one fails, and the user's own key all live in
// one place.
//
// منشورة بـ --no-verify-jwt: الكرون بيبعت x-cron-secret، والتطبيق بيبعت
// Authorization بتاع المستخدم وبيتفحص هنا.
// Deployed with --no-verify-jwt: the cron sends x-cron-secret, and the app
// sends the user's Authorization, which is checked here.
// =====================================================================

import { PushGoneError, pushConfigured, sendWebPush } from "../_shared/webpush.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

/// بعد الوقت ده مفيش خطوة جديدة بتبدأ: الخطوة الواحدة ممكن تاخد دقيقة،
/// وسقف الفنكشن 150 ثانية.
/// No new step starts after this: one step can take a minute, and the
/// function's ceiling is 150 seconds.
const START_STEPS_FOR_MS = 70_000;

/// تحت الحجم ده الملف بيتبعت جوه الطلب، وفوقه بيترفع لجوجل الأول.
/// Below this a file rides inside the request; above it, it is uploaded to
/// Google first.
const INLINE_BYTES = 3 * 1024 * 1024;

const MAX_ATTEMPTS = 4;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface Part {
  path: string;
  mime: string;
  size: number;
  transcript?: string | null;
}

interface JobRequest {
  model?: string;
  transcribe_system: string;
  transcribe_prompt: string;
  no_speech_marker?: string;
  summary_system: string;
  summary_prompt: string;
  missed_system?: string;
  missed_prompt?: string;
  missed_box_title?: string;
  cards_system?: string;
  cards_prompt?: string;
  done_title?: string;
}

interface Block {
  type: string;
  title?: string;
  text?: string;
  items?: string[];
  color_index?: number;
  [key: string]: unknown;
}

interface Page {
  title?: string;
  blocks: Block[];
}

interface Job {
  id: string;
  user_id: string;
  subject_id: string | null;
  title: string;
  status: string;
  step: string;
  parts: Part[];
  docs: Part[];
  plain_text: string;
  request: JobRequest;
  result: Page | null;
  missed: string[] | null;
  note_id: string | null;
  cards_made: number;
  attempts: number;
  claims: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS_HEADERS });

  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !CRON_SECRET) {
    return reply({ error: "missing configuration" }, 500);
  }

  let userId: string | null = null;
  if (req.headers.get("x-cron-secret") !== CRON_SECRET) {
    userId = await signedInUser(req.headers.get("Authorization"));
    if (!userId) return reply({ error: "unauthorized" }, 401);
  }

  // الشغل بيكمّل بعد الرد: الكرون عنده 5 ثواني بس، والتطبيق مش لازم يستنى.
  // The work continues after replying: the cron allows only 5 seconds, and
  // the app need not wait.
  const work = runOnce(userId).catch((e) => console.error("worker run failed", e));
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
    return reply({ accepted: true }, 202);
  }
  await work;
  return reply({ done: true });
});

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function signedInUser(auth: string | null): Promise<string | null> {
  if (!auth) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: auth },
  });
  if (!res.ok) {
    await res.text();
    return null;
  }
  const user = await res.json();
  return typeof user?.id === "string" ? user.id : null;
}

async function runOnce(userId: string | null): Promise<void> {
  const started = Date.now();
  const jobs = await claim(userId);
  await Promise.all(jobs.map((job) => advance(job, started)));
}

// =====================================================================
// الخطوات / steps
// =====================================================================

const MAX_CLAIMS = 30;

async function advance(job: Job, started: number): Promise<void> {
  if (job.claims > MAX_CLAIMS) {
    await fail(job, new FinalError("التلخيص اتأخر جدًا ووقف — جرّب تلخّصه من التطبيق."));
    return;
  }
  while (Date.now() - started < START_STEPS_FOR_MS) {
    try {
      const finished = await step(job);
      if (finished) return;
    } catch (e) {
      await fail(job, e);
      return;
    }
  }
  // الوقت خلص والشغل لسه: بيرجع للطابور والنداء الجاي يكمّل.
  // Out of time with work left: back to the queue for the next run.
  await patch(job.id, { status: "queued", locked_until: null });
}

/// بيعمل خطوة واحدة وبيرجّع true لما الشغل كله يخلص.
/// Does one step and returns true once the whole job is finished.
async function step(job: Job): Promise<boolean> {
  const r = job.request;

  // 1) تفريغ المقاطع واحد واحد.
  // 1) Transcribe the parts one by one.
  const index = job.parts.findIndex((p) => typeof p.transcript !== "string");
  if (index >= 0) {
    await patch(job.id, { step: `transcribe:${index + 1}/${job.parts.length}` });
    const part = job.parts[index];
    let text = (await streamText(job.user_id, {
      action: "summarize",
      model: r.model ?? "auto",
      system: r.transcribe_system,
      prompt: r.transcribe_prompt,
      temperature: 0,
      files: [await filePart(job.user_id, part)],
    })).trim();
    // "(مفيش كلام)" مش كلام — لو اتساب، بيعدّي فحص "مفيش حاجة تتلخص".
    // "(no speech)" is not speech: left in, it slips past the empty check.
    if (r.no_speech_marker) text = text.replaceAll(r.no_speech_marker, "").trim();
    job.parts[index] = { ...part, transcript: text };
    await patch(job.id, { parts: job.parts });
    return false;
  }

  const source = lectureText(job);

  // 2) التلخيص.
  // 2) The summary.
  if (!job.result) {
    if (!source && job.docs.length === 0) {
      throw new FinalError("مفيش كلام مفهوم في التسجيل.");
    }
    await patch(job.id, { step: "summarize" });
    const files = await Promise.all(job.docs.map((d) => filePart(job.user_id, d)));
    const result = await jsonCall(job.user_id, {
      action: "json",
      model: r.model ?? "auto",
      system: r.summary_system,
      prompt: r.summary_prompt.replaceAll("{{LECTURE}}", source),
      files: files.length ? files : undefined,
    }) as Page;
    if (!result || !Array.isArray(result.blocks) || result.blocks.length === 0) {
      throw new Error("التلخيص رجع فاضي.");
    }
    if (!result.title?.trim()) result.title = job.title;
    job.result = result;
    await patch(job.id, { result });
    return false;
  }

  // 3) إيه اللي اتقال ومادخلش — بيتضاف للصفحة على طول.
  // 3) What was said but left out — appended to the page right away.
  if (job.missed === null && r.missed_system && r.missed_prompt && source.length >= 200) {
    await patch(job.id, { step: "missed" });
    let missed: string[] = [];
    try {
      const out = await jsonCall(job.user_id, {
        action: "json",
        model: r.model ?? "auto",
        system: r.missed_system,
        prompt: r.missed_prompt
          .replaceAll("{{SOURCE}}", source.slice(0, 400_000))
          .replaceAll("{{SUMMARY}}", plainText(job.result)),
      }) as { missed?: unknown };
      missed = Array.isArray(out?.missed)
        ? out.missed.map((m) => `${m}`.trim()).filter(Boolean)
        : [];
    } catch (e) {
      // خطوة تحسين مش أساسية: فشلها ما يوقّفش الباقي.
      // An improvement, not essential: its failure does not stop the rest.
      console.error("missed check failed", job.id, e);
    }
    if (missed.length) {
      job.result.blocks.push({
        type: "box",
        title: r.missed_box_title ?? "نقط إضافية من المحاضرة",
        text: missed.map((m) => `• ${m}`).join("\n"),
        color_index: 1,
      });
    }
    job.missed = missed;
    await patch(job.id, { missed, result: job.result });
    return false;
  }

  // 4) ملاحظة تحت المادة.
  // 4) A note under the subject.
  if (!job.note_id) {
    await patch(job.id, { step: "note" });
    const rows = await rest("notes", {
      method: "POST",
      headers: { Prefer: "return=representation" },
      body: JSON.stringify({
        user_id: job.user_id,
        subject_id: job.subject_id,
        title: job.result.title || job.title,
        body: plainText(job.result),
      }),
    });
    job.note_id = rows?.[0]?.id ?? null;
    await patch(job.id, { note_id: job.note_id });
    return false;
  }

  // 5) كروت مراجعة مستحقة من النهاردة.
  // 5) Review cards, due from today.
  if (job.cards_made === 0 && r.cards_system && r.cards_prompt) {
    await patch(job.id, { step: "cards" });
    let made = -1;
    try {
      const out = await jsonCall(job.user_id, {
        action: "json",
        model: r.model ?? "auto",
        system: r.cards_system,
        prompt: r.cards_prompt.replaceAll("{{SOURCE}}", plainText(job.result)),
      }) as { cards?: unknown };
      const cards = (Array.isArray(out?.cards) ? out.cards : [])
        .map((c) => c as Record<string, unknown>)
        .map((c) => ({
          front: `${c.front ?? c.q ?? ""}`.trim(),
          back: `${c.back ?? c.a ?? ""}`.trim(),
        }))
        .filter((c) => c.front && c.back)
        .slice(0, 15);
      if (cards.length) {
        await rest("flashcards", {
          method: "POST",
          body: JSON.stringify(cards.map((c) => ({
            ...c,
            user_id: job.user_id,
            subject_id: job.subject_id,
          }))),
        });
        made = cards.length;
      }
    } catch (e) {
      console.error("cards failed", job.id, e);
    }
    job.cards_made = made;
    await patch(job.id, { cards_made: made });
    return false;
  }

  // 6) خلص: نشيل الصوت من التخزين ونبعت إشعار.
  // 6) Done: remove the audio from storage and send a notification.
  await patch(job.id, { status: "done", step: "", error: null, locked_until: null });
  // الصوت بيتمسح؛ الـ PDF بيفضل عشان التطبيق يرسم منه صفحات السلايدات.
  // The audio is removed; the PDFs stay so the app can draw slide pages
  // from them.
  await removeFiles(job.parts.map((p) => p.path));
  await notify(job);
  return true;
}

function lectureText(job: Job): string {
  return [job.plain_text, ...job.parts.map((p) => p.transcript ?? "")]
    .map((t) => t.trim())
    .filter(Boolean)
    .join("\n\n");
}

/// نفس toPlainText في التطبيق: الملاحظة والكروت بيتعملوا من النص ده.
/// Mirrors toPlainText in the app: the note and the cards come from this.
function plainText(page: Page): string {
  const lines = [`# ${page.title ?? ""}`];
  for (const b of page.blocks) {
    const items = Array.isArray(b.items) ? b.items : [];
    switch (b.type) {
      case "heading": lines.push(`## ${b.text ?? ""}`); break;
      case "box": lines.push(`**${b.title ?? ""}**\n${b.text ?? ""}`); break;
      case "bullets": lines.push(items.map((i) => `- ${i}`).join("\n")); break;
      case "numbered": lines.push(items.map((i, n) => `${n + 1}. ${i}`).join("\n")); break;
      case "highlight": lines.push(`**${b.text ?? ""}**`); break;
      case "divider": lines.push("---"); break;
      case "image": if (b.text) lines.push(`[${b.text}]`); break;
      case "diagram": {
        const head = b.title ? `**${b.title}**\n` : "";
        if (b.kind === "compare") {
          const cols = Array.isArray(b.columns) ? b.columns as string[] : [];
          const rows = Array.isArray(b.rows) ? b.rows as string[][] : [];
          lines.push(head + [
            `| ${cols.join(" | ")} |`,
            `|${cols.map(() => "---").join("|")}|`,
            ...rows.map((r) => `| ${r.join(" | ")} |`),
          ].join("\n"));
        } else if (b.kind === "tree") {
          lines.push(head + items.map((i) => `- ${i}`).join("\n"));
        } else {
          lines.push(head + items.join(" ← "));
        }
        break;
      }
      default: if (b.text) lines.push(b.text);
    }
  }
  return lines.filter(Boolean).join("\n\n");
}

class FinalError extends Error {}

async function fail(job: Job, e: unknown): Promise<void> {
  const message = e instanceof Error ? e.message : `${e}`;
  const attempts = job.attempts + 1;
  const final = e instanceof FinalError || attempts >= MAX_ATTEMPTS;
  console.error("job step failed", job.id, attempts, message);
  await patch(job.id, {
    status: final ? "failed" : "queued",
    attempts,
    error: message.slice(0, 500),
    // إعادة المحاولة بعد شوية: غالبًا الحصة خلصت أو جوجل مشغولة.
    // Retry a little later: usually the quota ran out or Google is busy.
    locked_until: final ? null : new Date(Date.now() + attempts * 2 * 60_000).toISOString(),
  });
  if (final) await notify({ ...job, status: "failed" }, message);
}

// =====================================================================
// الملفات / files
// =====================================================================

/// الملف الصغير بيتبعت جوه الطلب، والكبير بيترفع لجوجل بالتمرير من التخزين.
/// A small file rides inside the request; a large one is streamed from
/// storage up to Google.
async function filePart(userId: string, part: Part): Promise<Record<string, string>> {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/lectures/${part.path}`, {
    headers: serviceHeaders(),
  });
  if (!res.ok || !res.body) {
    throw new FinalError(`الملف مش موجود في التخزين (${res.status}).`);
  }

  if (part.size <= INLINE_BYTES) {
    const bytes = new Uint8Array(await res.arrayBuffer());
    return { mime_type: part.mime, data: base64(bytes) };
  }

  const up = await fetch(`${SUPABASE_URL}/functions/v1/summarize?action=upload`, {
    method: "POST",
    headers: {
      ...workerHeaders(userId),
      "Content-Type": "application/octet-stream",
      "x-file-mime": part.mime,
      "x-file-size": `${part.size}`,
      "x-file-name": part.path.split("/").pop() ?? "lecture",
    },
    body: res.body,
    duplex: "half",
  } as RequestInit);
  const info = await up.json();
  if (!up.ok || !info?.uri) throw new Error(info?.error ?? `upload ${up.status}`);

  let state = info.state;
  for (let i = 0; i < 20 && state === "PROCESSING"; i++) {
    await new Promise((r) => setTimeout(r, 3000));
    const check = await jsonCall(userId, { action: "file_state", file_name: info.name }, false);
    state = (check as { state?: string })?.state ?? state;
  }
  if (state !== "ACTIVE") throw new Error(`الملف لسه بيتجهز عند جوجل (${state}).`);
  return { mime_type: info.mime_type || part.mime, file_uri: info.uri };
}

async function removeFiles(paths: string[]): Promise<void> {
  if (!paths.length) return;
  try {
    await fetch(`${SUPABASE_URL}/storage/v1/object/lectures`, {
      method: "DELETE",
      headers: { ...serviceHeaders(), "Content-Type": "application/json" },
      body: JSON.stringify({ prefixes: paths }),
    });
  } catch (e) {
    console.error("storage cleanup failed", e);
  }
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

// =====================================================================
// نداءات summarize / summarize calls
// =====================================================================

function workerHeaders(userId: string): Record<string, string> {
  return {
    apikey: ANON_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    "x-worker-secret": CRON_SECRET,
    "x-act-as": userId,
  };
}

/// نداء بيرجع NDJSON (بينج وسطر نتيجة) أو JSON عادي.
/// A call answering NDJSON (heartbeats then a result line) or plain JSON.
async function jsonCall(
  userId: string,
  body: Record<string, unknown>,
  ndjson = true,
): Promise<unknown> {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/summarize`, {
    method: "POST",
    headers: { ...workerHeaders(userId), "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!ndjson) {
    const parsed = JSON.parse(text);
    if (!res.ok) throw new Error(parsed?.error ?? `summarize ${res.status}`);
    return parsed;
  }
  let last: Record<string, unknown> | null = null;
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    const obj = JSON.parse(line);
    if (obj.pending) continue;
    last = obj;
  }
  if (!res.ok || !last) throw new Error(`summarize ${res.status}: ${text.slice(0, 300)}`);
  if (last.error) throw new Error(`${last.error}${last.detail ? ` — ${`${last.detail}`.slice(0, 200)}` : ""}`);
  return last.result;
}

/// نداء بيبث نص (التفريغ): بيجمّع كل سطور {text}.
/// A call streaming text (the transcript): gathers every {text} line.
async function streamText(userId: string, body: Record<string, unknown>): Promise<string> {
  const res = await fetch(`${SUPABASE_URL}/functions/v1/summarize`, {
    method: "POST",
    headers: { ...workerHeaders(userId), "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`summarize ${res.status}: ${text.slice(0, 300)}`);
  let out = "";
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    const obj = JSON.parse(line);
    if (obj.error) throw new Error(`${obj.error}`);
    if (typeof obj.text === "string") out += obj.text;
  }
  return out;
}

// =====================================================================
// الداتابيز / database
// =====================================================================

function serviceHeaders(): Record<string, string> {
  return { apikey: SERVICE_ROLE_KEY, Authorization: `Bearer ${SERVICE_ROLE_KEY}` };
}

// deno-lint-ignore no-explicit-any
async function rest(path: string, init: RequestInit = {}): Promise<any> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      ...serviceHeaders(),
      "Content-Type": "application/json",
      ...(init.headers as Record<string, string> ?? {}),
    },
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`db ${path} ${res.status}: ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : null;
}

async function claim(userId: string | null): Promise<Job[]> {
  const rows = await rest("rpc/claim_lecture_jobs", {
    method: "POST",
    body: JSON.stringify({ p_user: userId, p_limit: 2 }),
  });
  return (Array.isArray(rows) ? rows : []).map((row) => ({
    ...row,
    parts: Array.isArray(row.parts) ? row.parts : [],
    docs: Array.isArray(row.docs) ? row.docs : [],
    plain_text: row.plain_text ?? "",
  }));
}

async function patch(id: string, fields: Record<string, unknown>): Promise<void> {
  await rest(`lecture_jobs?id=eq.${id}`, {
    method: "PATCH",
    body: JSON.stringify({ ...fields, updated_at: new Date().toISOString() }),
  });
}

// =====================================================================
// الإشعار / notification
// =====================================================================

async function notify(job: Job, error?: string): Promise<void> {
  if (!pushConfigured()) return;
  try {
    const subs = await rest(
      `push_subscriptions?select=id,endpoint,p256dh,auth&user_id=eq.${job.user_id}`,
    );
    const ok = job.status !== "failed";
    const title = ok ? (job.request.done_title ?? "التلخيص جاهز") : "التلخيص ما كملش";
    const body = ok
      ? `${job.result?.title || job.title}${job.cards_made > 0 ? ` · ${job.cards_made} كارت` : ""}`
      : `${job.title} — ${error ?? ""}`.slice(0, 180);
    for (const sub of subs ?? []) {
      try {
        await sendWebPush(sub, { title, body, tag: `job:${job.id}`, url: `./?job=${job.id}` });
      } catch (e) {
        if (e instanceof PushGoneError) {
          await rest(`push_subscriptions?id=eq.${sub.id}`, { method: "DELETE" });
        } else {
          console.error("push failed", job.id, e);
        }
      }
    }
  } catch (e) {
    console.error("notify failed", job.id, e);
  }
}
