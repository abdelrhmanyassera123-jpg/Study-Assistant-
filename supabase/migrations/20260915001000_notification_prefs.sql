-- =====================================================================
-- notification_prefs — تخصيص التنبيه لكل مستخدم
-- =====================================================================
-- صف واحد لكل مستخدم. بيتقرا من التطبيق (التنبيه المحلي) ومن فنكشن
-- send-reminders (التنبيه الحقيقي عن بعد) عشان الاتنين يطلعوا بنفس الشكل.
--
-- One row per user. Read both by the app (local reminder) and by the
-- send-reminders function (the real remote push) so both come out looking
-- the same.
-- =====================================================================

create table if not exists public.notification_prefs (
  user_id     uuid primary key references auth.users (id) on delete cascade,
  sound_on    boolean not null default true,
  vibrate_on  boolean not null default true,

  -- null = الصيغة الافتراضية. لو متحطة، بتتعوض فيها {minutes} {location}
  -- {lecture} {lecturer}.
  -- null = the default wording. When set, {minutes} {location} {lecture}
  -- {lecturer} are substituted inside it.
  custom_body text,

  default_remind_minutes smallint not null default 15
    check (default_remind_minutes between 0 and 240),

  updated_at  timestamptz not null default now()
);

alter table public.notification_prefs enable row level security;

drop policy if exists "own_select" on public.notification_prefs;
drop policy if exists "own_insert" on public.notification_prefs;
drop policy if exists "own_update" on public.notification_prefs;
drop policy if exists "own_delete" on public.notification_prefs;

create policy "own_select" on public.notification_prefs
  for select using (auth.uid() = user_id);
create policy "own_insert" on public.notification_prefs
  for insert with check (auth.uid() = user_id);
create policy "own_update" on public.notification_prefs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own_delete" on public.notification_prefs
  for delete using (auth.uid() = user_id);
