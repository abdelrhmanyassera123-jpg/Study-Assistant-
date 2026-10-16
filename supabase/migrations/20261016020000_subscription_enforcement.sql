-- =====================================================================
-- تطبيق الاشتراك: القفل الفوري والفحص على السيرفر
-- Enforcing the subscription: instant lock and the server-side check
-- =====================================================================

-- التطبيق بيسمع لتغييرات صف اشتراكه (Realtime) — لو الأدمن قفله، بيتقفل في
-- نفس اللحظة. RLS على الجدول بتخلّي كل واحد يسمع صفه هو بس.
-- The app listens for changes to its own subscription row (Realtime): when
-- the admin switches it off, it locks that moment. RLS on the table lets
-- each account hear only its own row.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'subscriptions'
  ) then
    alter publication supabase_realtime add table public.subscriptions;
  end if;
end $$;

-- فنكشن التلخيص بتسأل قبل كل طلب (من غير عدّ — رفع ملف بييجي على أجزاء
-- كتير)، وبتعدّ نداءات الموديل بس.
-- The summarize function asks before every request (without counting: an
-- upload arrives in many pieces), and counts only the model calls.
drop function if exists public.ai_allow(uuid);

create or replace function public.ai_allow(p_user uuid, p_count boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.subscriptions;
begin
  if not exists (select 1 from public.admins where user_id = p_user) then
    select * into s from public.subscriptions where user_id = p_user;
    if s.user_id is null or s.disabled or (s.ends_at is not null and s.ends_at <= now()) then
      return jsonb_build_object('ok', false, 'error', 'no_subscription');
    end if;
  end if;

  if p_count then
    insert into public.ai_usage (user_id, day, calls)
    values (p_user, (now() at time zone 'Africa/Cairo')::date, 1)
    on conflict (user_id, day) do update set calls = public.ai_usage.calls + 1;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.ai_allow(uuid, boolean) from public, anon, authenticated;
