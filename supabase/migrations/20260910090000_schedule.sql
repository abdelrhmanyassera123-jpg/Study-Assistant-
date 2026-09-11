-- =====================================================================
-- schedule_entries — جدول المحاضرات الأسبوعي
-- =====================================================================
-- الجدول بيتكرر كل أسبوع، فبنخزن اليوم والوقت مش تاريخ بعينه. التاريخ بيتحسب
-- وقت العرض والتنبيه من اليوم الحالي.
--
-- The timetable repeats weekly, so a day and a time are stored rather than a
-- date. The actual date is worked out at display and reminder time from today.
-- =====================================================================

create table if not exists public.schedule_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  -- المادة اختيارية: الجدول بيتكتب قبل ما المواد تتسجل غالبًا.
  -- The subject is optional: a timetable is usually written down before the
  -- subjects themselves are entered.
  subject_id  uuid references public.subjects (id) on delete set null,
  title       text not null check (char_length(trim(title)) > 0),

  -- 1 = الاتنين ... 7 = الأحد، نفس ترقيم DateTime.weekday عشان ما يبقاش في
  -- تحويل في النص بين الداتابيز والتطبيق.
  -- 1 = Monday ... 7 = Sunday, matching DateTime.weekday so nothing has to be
  -- converted halfway between the database and the app.
  weekday     smallint not null check (weekday between 1 and 7),

  -- الوقت بالدقايق من نص الليل: بيترتب وبيتطرح منه من غير تحويل نصوص.
  -- Minutes from midnight: sorts and subtracts without parsing strings.
  start_minutes smallint not null check (start_minutes between 0 and 1439),
  end_minutes   smallint check (end_minutes between 0 and 1440),

  location    text not null default '',
  lecturer    text not null default '',
  notes       text not null default '',

  -- عدد الدقايق قبل المحاضرة اللي التنبيه بيطلع فيها. null = مفيش تنبيه،
  -- فالتفعيل والإيقاف بيبقى في نفس الحقل بدل عمود زيادة.
  -- How many minutes before the lecture the reminder fires. null = no
  -- reminder, so switching it on and off lives in one field instead of two.
  remind_minutes smallint check (remind_minutes between 0 and 240),

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists schedule_entries_user_day_idx
  on public.schedule_entries (user_id, weekday, start_minutes);

alter table public.schedule_entries enable row level security;

drop policy if exists "own_select" on public.schedule_entries;
drop policy if exists "own_insert" on public.schedule_entries;
drop policy if exists "own_update" on public.schedule_entries;
drop policy if exists "own_delete" on public.schedule_entries;

create policy "own_select" on public.schedule_entries
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.schedule_entries
  for insert with check (auth.uid() = user_id);
create policy "own_update" on public.schedule_entries
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.schedule_entries
  for delete using (auth.uid() = user_id);
