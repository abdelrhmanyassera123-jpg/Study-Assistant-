-- =====================================================================
-- style_profiles — الشكل البصري لتلخيصات المستخدم
-- =====================================================================
-- جدول style_samples بيمسك *نص* التلخيص (الأسلوب اللغوي). الجدول ده بيمسك
-- *شكله*: الألوان، المربعات، ترتيب الأقسام، التنقيط — مستخرج من صور كراسته.
--
-- style_samples holds the *words* of a summary (the written voice). This table
-- holds its *look*: colours, boxes, section order, bullet habits — extracted by
-- vision from photos of the user's own notebook.
--
-- الملف الخام مش بيتخزن، بس التحليل — عشان الجدول يفضل خفيف والصور تفضل عندك.
-- The source images are not stored, only the analysis, so the table stays small
-- and the photos stay on the user's machine.
-- =====================================================================

create table if not exists public.style_profiles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  -- بروفايل واحد لكل مادة، وبروفايل بـ null كافتراضي عام.
  -- One profile per subject; a null subject acts as the general default.
  subject_id  uuid references public.subjects (id) on delete cascade,
  label       text not null default '',
  -- تحليل الشكل كـ JSON: ألوان، أنواع الأقسام، عادات التنسيق.
  -- The layout analysis as JSON: colours, section kinds, formatting habits.
  profile     jsonb not null,
  -- عدد الصور اللي التحليل اتبنى عليها — مؤشر لجودة البروفايل.
  -- How many images the analysis was built from; a quality signal.
  source_count integer not null default 1 check (source_count > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- بروفايل واحد بس لكل (مستخدم، مادة) — التحليل الجديد بيحل محل القديم.
-- Exactly one profile per (user, subject); a new analysis replaces the old one.
create unique index if not exists style_profiles_user_subject_key
  on public.style_profiles (user_id, coalesce(subject_id, '00000000-0000-0000-0000-000000000000'::uuid));

alter table public.style_profiles enable row level security;

drop policy if exists "own_select" on public.style_profiles;
drop policy if exists "own_insert" on public.style_profiles;
drop policy if exists "own_update" on public.style_profiles;
drop policy if exists "own_delete" on public.style_profiles;

create policy "own_select" on public.style_profiles
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.style_profiles
  for insert with check (auth.uid() = user_id);
create policy "own_update" on public.style_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.style_profiles
  for delete using (auth.uid() = user_id);
