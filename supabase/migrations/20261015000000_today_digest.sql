-- =====================================================================
-- إشعار "محاضرات النهاردة" — إعداده وسجل اللي اتبعت منه
-- The "today's lectures" notification: its setting and a log of what went out
-- =====================================================================
-- الإشعار بيوصل أول اليوم وبيتحدّث مع كل محاضرة وبيختفي بعد آخرها (شوف
-- supabase/functions/_shared/today_digest.ts). شغال افتراضيًا، والمستخدم
-- يقفله من الإعدادات.
--
-- The notification arrives at the start of the day, updates with each
-- lecture and disappears after the last (see
-- supabase/functions/_shared/today_digest.ts). On by default; the user can
-- turn it off in settings.
-- =====================================================================

alter table public.notification_prefs
  add column if not exists daily_digest boolean not null default true,
  -- ميعاد أول اليوم بالدقايق من نص الليل بتوقيت القاهرة (420 = 7:00 ص).
  -- The start-of-day time in minutes after midnight, Cairo time (420 = 7 AM).
  add column if not exists digest_minutes smallint not null default 420
    check (digest_minutes between 0 and 1439);

-- كل حدث (أول اليوم، بداية محاضرة، النهاية) بيتحجز مرة واحدة في اليوم، عشان
-- نداءات الكرون اللي كل دقيقة ما تبعتوش تاني.
-- Each event (start of day, a lecture starting, the end) is claimed once a
-- day, so the every-minute cron calls never send it twice.
create table if not exists public.push_digest_sent (
  user_id  uuid not null references auth.users (id) on delete cascade,
  day      date not null,
  event    text not null,
  sent_at  timestamptz not null default now(),
  primary key (user_id, day, event)
);

-- مفيش policies: الفنكشن بس (service role) هي اللي بتقرا وتكتب هنا.
-- No policies: only the function (service role) reads and writes here.
alter table public.push_digest_sent enable row level security;
