-- =====================================================================
-- Study Assistant — Supabase schema
-- =====================================================================
-- شغّل الملف ده مرة واحدة في: Supabase Dashboard -> SQL Editor -> New query
-- Run this once in: Supabase Dashboard -> SQL Editor -> New query
--
-- كل جدول مربوط بـ auth.users وعليه RLS، يعني كل مستخدم يشوف داتاه هو بس.
-- Every table is keyed to auth.users and protected by RLS, so each user
-- can only ever read or write their own rows.
-- =====================================================================

-- ------------------------------------------------------------ subjects
create table if not exists public.subjects (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  name        text not null check (char_length(trim(name)) between 1 and 120),
  color       bigint not null default 4283385573, -- 0xFF4F46E5
  created_at  timestamptz not null default now()
);

-- --------------------------------------------------------------- tasks
create table if not exists public.tasks (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  subject_id    uuid references public.subjects (id) on delete cascade,
  title         text not null check (char_length(trim(title)) between 1 and 300),
  details       text,
  due_date      timestamptz,
  priority      smallint not null default 1 check (priority between 0 and 2),
  is_done       boolean not null default false,
  completed_at  timestamptz,
  created_at    timestamptz not null default now()
);

-- --------------------------------------------------------------- notes
create table if not exists public.notes (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  subject_id  uuid references public.subjects (id) on delete cascade,
  title       text not null default '',
  body        text not null default '',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------- flashcards
-- الأعمدة من ease لـ due_at هي حالة خوارزمية SM-2 لكل كارت.
-- Columns ease..due_at hold the per-card SM-2 scheduling state.
create table if not exists public.flashcards (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  subject_id     uuid references public.subjects (id) on delete cascade,
  front          text not null check (char_length(trim(front)) > 0),
  back           text not null check (char_length(trim(back)) > 0),
  ease           double precision not null default 2.5,
  interval_days  integer not null default 0,
  repetitions    integer not null default 0,
  lapses         integer not null default 0,
  due_at         timestamptz not null default now(),
  created_at     timestamptz not null default now()
);

-- ----------------------------------------------------- study_sessions
create table if not exists public.study_sessions (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references auth.users (id) on delete cascade,
  subject_id        uuid references public.subjects (id) on delete set null,
  started_at        timestamptz not null default now(),
  duration_seconds  integer not null check (duration_seconds >= 0)
);

-- -------------------------------------------------------- card_reviews
-- سجل كل مراجعة — بيغذي إحصائية "كروت اتراجعت".
-- One row per review; feeds the "cards reviewed" stat.
create table if not exists public.card_reviews (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users (id) on delete cascade,
  card_id     uuid references public.flashcards (id) on delete cascade,
  grade       smallint not null check (grade between 0 and 3),
  reviewed_at timestamptz not null default now()
);

-- ------------------------------------------------------------- indexes
create index if not exists subjects_user_idx        on public.subjects (user_id);
create index if not exists tasks_user_due_idx       on public.tasks (user_id, is_done, due_date);
create index if not exists notes_user_updated_idx   on public.notes (user_id, updated_at desc);
create index if not exists flashcards_user_due_idx  on public.flashcards (user_id, due_at);
create index if not exists sessions_user_start_idx  on public.study_sessions (user_id, started_at desc);
create index if not exists reviews_user_time_idx    on public.card_reviews (user_id, reviewed_at desc);

-- =====================================================================
-- Row Level Security — كل مستخدم على داتاه بس
-- =====================================================================
alter table public.subjects       enable row level security;
alter table public.tasks          enable row level security;
alter table public.notes          enable row level security;
alter table public.flashcards     enable row level security;
alter table public.study_sessions enable row level security;
alter table public.card_reviews   enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'subjects', 'tasks', 'notes', 'flashcards', 'study_sessions', 'card_reviews'
  ] loop
    execute format('drop policy if exists "own_select" on public.%I', t);
    execute format('drop policy if exists "own_insert" on public.%I', t);
    execute format('drop policy if exists "own_update" on public.%I', t);
    execute format('drop policy if exists "own_delete" on public.%I', t);

    execute format(
      'create policy "own_select" on public.%I for select using (auth.uid() = user_id)', t);
    execute format(
      'create policy "own_insert" on public.%I for insert with check (auth.uid() = user_id)', t);
    execute format(
      'create policy "own_update" on public.%I for update using (auth.uid() = user_id) '
      'with check (auth.uid() = user_id)', t);
    execute format(
      'create policy "own_delete" on public.%I for delete using (auth.uid() = user_id)', t);
  end loop;
end $$;
