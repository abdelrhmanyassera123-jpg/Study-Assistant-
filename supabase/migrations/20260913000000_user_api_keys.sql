-- =====================================================================
-- user_api_keys — مفتاح Gemini شخصي اختياري لكل مستخدم
-- =====================================================================
-- المستخدم اللي بيحط مفتاحه الشخصي بيستهلك من حصته هو بس، بدل ما يشارك حصة
-- مفتاح Gemini المشترك مع كل مستخدمين التطبيق. الفنكشن بتفضّله على المفتاح
-- المشترك لو موجود، وبترجع للمشترك تلقائيًا لو مالوش (row policy بتحصر كل
-- مستخدم في صفه هو بس).
--
-- A user who sets their own key spends from their own quota instead of
-- sharing the app's shared Gemini key with every other user. The function
-- prefers it over the shared key when present, and falls back to the shared
-- one automatically when absent (row policies keep every user to their own
-- row only).
-- =====================================================================

create table if not exists public.user_api_keys (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  gemini_api_key text not null check (char_length(trim(gemini_api_key)) > 0),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

alter table public.user_api_keys enable row level security;

drop policy if exists "own_select" on public.user_api_keys;
drop policy if exists "own_insert" on public.user_api_keys;
drop policy if exists "own_update" on public.user_api_keys;
drop policy if exists "own_delete" on public.user_api_keys;

create policy "own_select" on public.user_api_keys
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.user_api_keys
  for insert with check (auth.uid() = user_id);
create policy "own_update" on public.user_api_keys
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.user_api_keys
  for delete using (auth.uid() = user_id);
