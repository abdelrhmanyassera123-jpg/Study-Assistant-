-- =====================================================================
-- push_subscriptions — اشتراكات Web Push لكل جهاز
-- =====================================================================
-- كل جهاز/متصفح بيشترك لوحده، فالمستخدم الواحد ممكن يكون ليه أكتر من صف هنا
-- (موبايل + لابتوب مثلاً). الـ endpoint فريد لأنه هو معرّف الاشتراك نفسه من
-- خدمة الـ push.
--
-- Each device/browser subscribes on its own, so one user can have more than
-- one row here (phone + laptop, say). The endpoint is unique because it *is*
-- the subscription's identity as far as the push service is concerned.
-- =====================================================================

create table if not exists public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  created_at  timestamptz not null default now()
);

create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

drop policy if exists "own_select" on public.push_subscriptions;
drop policy if exists "own_insert" on public.push_subscriptions;
drop policy if exists "own_update" on public.push_subscriptions;
drop policy if exists "own_delete" on public.push_subscriptions;

create policy "own_select" on public.push_subscriptions
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.push_subscriptions
  for insert with check (auth.uid() = user_id);
create policy "own_update" on public.push_subscriptions
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.push_subscriptions
  for delete using (auth.uid() = user_id);

-- =====================================================================
-- push_reminders_sent — سجل إرسال، يمنع تكرار نفس التنبيه
-- =====================================================================
-- المهمة المجدولة بتفحص كل دقيقة، فلازم سجل يمنعها تبعت نفس التنبيه مرتين لو
-- اتنفذت مرتين قريبين من بعض أو لقت نفس المحاضرة لسه في نافذة الإرسال.
--
-- The scheduled job checks every minute, so a log is needed to stop it
-- sending the same reminder twice if it runs close together or still finds
-- the same lecture inside the send window.
-- =====================================================================

create table if not exists public.push_reminders_sent (
  entry_id       uuid not null,
  occurrence_at  timestamptz not null,
  sent_at        timestamptz not null default now(),
  primary key (entry_id, occurrence_at)
);

-- الجدول ده بيتقرا ويتكتب من الفنكشن المجدولة بس (service role)، مفيش داعي
-- لأي policy تفتحه لمستخدمين عاديين.
-- This table is only read and written by the scheduled function (service
-- role); no policy is needed to open it to ordinary users.
alter table public.push_reminders_sent enable row level security;
