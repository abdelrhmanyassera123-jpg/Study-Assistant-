-- =====================================================================
-- lecture_jobs — تلخيص المحاضرات على السيرفر، والتطبيق مقفول
-- lecture_jobs — summarizing lectures on the server, with the app closed
-- =====================================================================
-- التطبيق بيرفع التسجيل لـ Storage ويحط صف هنا، وفنكشن lecture-worker
-- بتكمّل الشغل خطوة خطوة كل دقيقة: تفريغ كل مقطع، تلخيص، "إيه اللي اتنسى"،
-- كروت، ملاحظة، وإشعار. كل خطوة بتتحفظ أول ما تخلص، فلو نداء وقع أو الفنكشن
-- وصلت لسقف وقتها، اللي بعده بيكمّل من مكانه.
--
-- The app uploads the recording to Storage and inserts a row here; the
-- lecture-worker function carries it forward one step at a time every
-- minute: transcribe each part, summarize, check what was missed, cards, a
-- note, and a notification. Each step is saved as soon as it finishes, so
-- if a call fails or the function hits its time ceiling, the next run
-- picks up where it left off.
--
-- البرومبتات بتتبني في التطبيق وتتحفظ في `request`: الأسلوب والأمثلة
-- وشكل الصفحة كلهم هناك، ونسخهم في TypeScript كان هيخليهم يختلفوا مع الوقت.
-- The prompts are built in the app and stored in `request`: the style, the
-- examples and the page look all live there, and copying them into
-- TypeScript would let the two drift apart.
-- =====================================================================

create table if not exists public.lecture_jobs (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  subject_id       uuid references public.subjects (id) on delete set null,
  schedule_entry_id uuid references public.schedule_entries (id) on delete set null,
  title            text not null default '',

  status           text not null default 'queued'
                     check (status in ('queued', 'working', 'done', 'failed')),
  -- وصف الخطوة الحالية للعرض: "transcribe:2/5" أو "summarize" ...
  -- The current step for display: "transcribe:2/5", "summarize", ...
  step             text not null default '',

  -- [{path, mime, size, transcript}] — الصوت، والتفريغ بيتملى مقطع مقطع.
  -- [{path, mime, size, transcript}] — the audio, transcripts filled part by part.
  parts            jsonb not null default '[]'::jsonb,
  -- [{path, mime, size}] — ملفات الموديل بيقراها بنفسه (PDF).
  -- [{path, mime, size}] — files the model reads itself (PDF).
  docs             jsonb not null default '[]'::jsonb,
  -- نص مستخرج في التطبيق (docx/pptx) أو ملزوق.
  -- Text extracted in the app (docx/pptx) or pasted.
  plain_text       text not null default '',

  request          jsonb not null,

  result           jsonb,
  missed           jsonb,
  note_id          uuid references public.notes (id) on delete set null,
  cards_made       integer not null default 0,
  error            text,

  attempts         integer not null default 0,
  -- كام مرة اتحجز. خطوة بتقع من سقف الوقت ما بتسجّلش فشل، فده اللي بيوقفها
  -- قبل ما تفضل تتعاد وتصرف من الحصة.
  -- How many times it was claimed. A step killed by the time ceiling records
  -- no failure, so this is what stops it repeating and spending quota.
  claims           integer not null default 0,
  locked_until     timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists lecture_jobs_pending_idx
  on public.lecture_jobs (status, created_at)
  where status in ('queued', 'working');
create index if not exists lecture_jobs_user_idx
  on public.lecture_jobs (user_id, created_at desc);

alter table public.lecture_jobs enable row level security;

drop policy if exists "own_select" on public.lecture_jobs;
drop policy if exists "own_insert" on public.lecture_jobs;
drop policy if exists "own_update" on public.lecture_jobs;
drop policy if exists "own_delete" on public.lecture_jobs;

create policy "own_select" on public.lecture_jobs
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.lecture_jobs
  for insert with check (auth.uid() = user_id);
-- التعديل من التطبيق للإعادة بس (failed → queued) أو تعديل الصفحة الناتجة.
-- Updates from the app are only for retrying (failed → queued) or editing
-- the resulting page.
create policy "own_update" on public.lecture_jobs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.lecture_jobs
  for delete using (auth.uid() = user_id);

-- بيحجز شغل للعامل. SKIP LOCKED عشان نداءين في نفس الدقيقة (الكرون + التطبيق)
-- ما يمسكوش نفس الشغل.
-- Claims work for the worker. SKIP LOCKED so two runs in the same minute
-- (cron + the app's nudge) never take the same job.
create or replace function public.claim_lecture_jobs(p_user uuid default null, p_limit int default 2)
returns setof public.lecture_jobs
language sql
security definer
set search_path = public
as $$
  update public.lecture_jobs j
     set locked_until = now() + interval '3 minutes',
         status = 'working',
         claims = j.claims + 1,
         updated_at = now()
   where j.id in (
     select id from public.lecture_jobs
      where status in ('queued', 'working')
        and (locked_until is null or locked_until < now())
        and (p_user is null or user_id = p_user)
      order by created_at
      for update skip locked
      limit p_limit
   )
  returning j.*;
$$;

revoke all on function public.claim_lecture_jobs(uuid, int) from public, anon, authenticated;
grant execute on function public.claim_lecture_jobs(uuid, int) to service_role;

-- ------------------------------------------------------------ Storage
-- كل مستخدم ليه فولدر باسم الـ id بتاعه، ومحدش يشوف فولدر غيره.
-- Each user has a folder named after their id, and nobody sees another's.
insert into storage.buckets (id, name, public)
values ('lectures', 'lectures', false)
on conflict (id) do nothing;

drop policy if exists "lectures_own_insert" on storage.objects;
drop policy if exists "lectures_own_select" on storage.objects;
drop policy if exists "lectures_own_delete" on storage.objects;

create policy "lectures_own_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'lectures' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "lectures_own_select" on storage.objects
  for select to authenticated
  using (bucket_id = 'lectures' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "lectures_own_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'lectures' and (storage.foldername(name))[1] = auth.uid()::text);

-- --------------------------------------------------------------- Cron
-- كل دقيقة، بس لو فيه شغل مستني — من غير كده الفنكشن بتتنادى على الفاضي.
-- Every minute, but only when work is waiting; otherwise the function would
-- be invoked for nothing.
select cron.unschedule('lecture-worker-every-minute')
where exists (select 1 from cron.job where jobname = 'lecture-worker-every-minute');

select cron.schedule(
  'lecture-worker-every-minute',
  '* * * * *',
  $$
    select net.http_post(
      url := 'https://epcddoelvsqzbsiaeyem.supabase.co/functions/v1/lecture-worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'cron_secret'
        )
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 5000
    )
    where exists (
      select 1 from public.lecture_jobs
       where status in ('queued', 'working')
         and (locked_until is null or locked_until < now())
    );
  $$
);
