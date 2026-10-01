-- =====================================================================
-- past_questions — أسئلة امتحانات السنين اللي فاتت
-- past_questions — questions from previous years' exams
-- =====================================================================
-- كل سؤال صف لوحده، مربوط بالمحاضرة اللي جاي منها وبموضوع قصير. من هنا
-- بيتحسب "بيتسأل في كام امتحان" لكل موضوع، وبيتعمل امتحان تجريبي بنفس الشكل.
-- Each question is its own row, tied to the lecture it comes from and to a
-- short topic. "Asked in how many exams" per topic is worked out from here,
-- and a mock exam is made in the same shape.
-- =====================================================================

create table if not exists public.past_questions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  subject_id  uuid references public.subjects (id) on delete cascade,
  -- اسم الامتحان زي ما الطالب كتبه: "فاينل 2024"، "ميدترم 2023".
  -- The exam's name as the student wrote it: "Final 2024", "Midterm 2023".
  exam_label  text not null default '',
  question    text not null check (char_length(trim(question)) > 0),
  kind        text not null default 'written' check (kind in ('choice', 'written')),
  choices     jsonb not null default '[]'::jsonb,
  answer      text not null default '',
  lecture     text not null default '',
  topic       text not null default '',
  created_at  timestamptz not null default now()
);

create index if not exists past_questions_user_subject_idx
  on public.past_questions (user_id, subject_id);

alter table public.past_questions enable row level security;

drop policy if exists "own_select" on public.past_questions;
drop policy if exists "own_insert" on public.past_questions;
drop policy if exists "own_update" on public.past_questions;
drop policy if exists "own_delete" on public.past_questions;

create policy "own_select" on public.past_questions
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.past_questions
  for insert with check (auth.uid() = user_id);
create policy "own_update" on public.past_questions
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.past_questions
  for delete using (auth.uid() = user_id);
