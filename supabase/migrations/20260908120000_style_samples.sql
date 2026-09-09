-- =====================================================================
-- style_samples — أمثلة أسلوب التلخيص
-- =====================================================================
-- دي التلخيصات اللي المستخدم بيكتبها بنفسه، والموديل بيقلد أسلوبها.
-- عددها المفيد صغير (3-5 لكل مادة) — الكمية مش هي المطلوب هنا، التمثيل هو.
--
-- The user's own summaries, used as few-shot style examples. A handful per
-- subject (3-5) is what works; more examples dilute the style rather than
-- sharpen it.
-- =====================================================================

create table if not exists public.style_samples (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  -- المادة اختيارية: العينات من غير مادة بتشتغل كأسلوب عام لأي مادة.
  -- Subject is optional; unassigned samples act as a global style fallback.
  subject_id  uuid references public.subjects (id) on delete set null,
  title       text not null default '',
  body        text not null check (char_length(trim(body)) > 0),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists style_samples_user_subject_idx
  on public.style_samples (user_id, subject_id, created_at desc);

alter table public.style_samples enable row level security;

drop policy if exists "own_select" on public.style_samples;
drop policy if exists "own_insert" on public.style_samples;
drop policy if exists "own_update" on public.style_samples;
drop policy if exists "own_delete" on public.style_samples;

create policy "own_select" on public.style_samples
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.style_samples
  for insert with check (auth.uid() = user_id);
create policy "own_update" on public.style_samples
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.style_samples
  for delete using (auth.uid() = user_id);
