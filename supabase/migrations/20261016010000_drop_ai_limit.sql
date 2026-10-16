-- =====================================================================
-- من غير حد يومي للذكاء الاصطناعي
-- No daily AI cap
-- =====================================================================
-- الحد اليومي اتلغى بقرار صاحب المشروع: الاشتراك الشغال بيدّي استخدام من
-- غير حد. العدّ (ai_usage) فاضل للمعلومة بس في لوحة التحكم.
--
-- The daily cap is dropped by the owner's decision: a live subscription
-- gives unlimited use. The count (ai_usage) stays, for the dashboard only.
-- =====================================================================

drop function if exists public.admin_create_codes(integer, integer, text, timestamptz, text, integer);
drop function if exists public.admin_update_code(uuid, integer, boolean, text, integer, boolean);
drop function if exists public.admin_update_user(uuid, integer, timestamptz, boolean, boolean, integer, boolean);
drop function if exists public.admin_users();

alter table public.access_codes drop column if exists daily_ai_limit;
alter table public.subscriptions drop column if exists daily_ai_limit;

-- "تقدر تستخدم التطبيق؟" — التطبيق بيسأل دي أول ما يفتح.
-- "May this account use the app?" — asked by the app as it opens.
create or replace function public.my_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  s public.subscriptions;
  admin boolean := public.is_admin();
begin
  if uid is null then
    return jsonb_build_object('active', false, 'reason', 'signed_out');
  end if;

  select * into s from public.subscriptions where user_id = uid;
  return jsonb_build_object(
    'active', admin or (s.user_id is not null and not s.disabled and (s.ends_at is null or s.ends_at > now())),
    'reason', case
      when admin then 'admin'
      when s.user_id is null then 'none'
      when s.disabled then 'disabled'
      when s.ends_at is not null and s.ends_at <= now() then 'expired'
      else 'ok'
    end,
    'source', s.source,
    'ends_at', s.ends_at,
    'is_admin', admin
  );
end;
$$;

-- تفعيل كود — كله في عملية واحدة على السيرفر، فاتنين مينفعش يفعّلوا نفس الكود.
-- Redeems a code, all in one server-side step, so two people can never
-- redeem the same one.
create or replace function public.redeem_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  c public.access_codes;
  s public.subscriptions;
  k text;
  fails integer;
  base timestamptz;
  new_end timestamptz;
begin
  if uid is null then
    return jsonb_build_object('ok', false, 'error', 'signed_out');
  end if;

  -- 5 محاولات غلط في الساعة. الكود عشوائي (31^8 احتمال)، فالتخمين مستحيل عمليًا.
  -- Five wrong tries an hour. Codes are random (31^8 options), so guessing
  -- is hopeless in practice.
  select count(*) into fails from public.redeem_attempts
    where user_id = uid and not ok and at > now() - interval '1 hour';
  if fails >= 5 then
    return jsonb_build_object('ok', false, 'error', 'too_many_attempts');
  end if;

  k := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  if length(k) = 8 then k := 'SA' || k; end if;

  select * into c from public.access_codes where code_key = k for update;
  if not found then
    insert into public.redeem_attempts (user_id, ok) values (uid, false);
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if c.redeemed_by = uid then
    return jsonb_build_object('ok', false, 'error', 'already_yours');
  end if;
  if c.redeemed_by is not null then
    insert into public.redeem_attempts (user_id, ok) values (uid, false);
    return jsonb_build_object('ok', false, 'error', 'used');
  end if;
  if c.disabled then
    return jsonb_build_object('ok', false, 'error', 'disabled');
  end if;
  if c.valid_until is not null and c.valid_until < now() then
    return jsonb_build_object('ok', false, 'error', 'code_expired');
  end if;

  select * into s from public.subscriptions where user_id = uid for update;

  -- الحساب القديم شغال مجانًا ومن غير نهاية: مش محتاج كود.
  -- A legacy account runs free with no end: it needs no code.
  if s.source = 'legacy' and s.ends_at is null and not s.disabled then
    return jsonb_build_object('ok', false, 'error', 'not_needed');
  end if;

  -- التجريبي مرة واحدة لكل حساب.
  -- One trial per account.
  if c.kind = 'trial' and exists (
    select 1 from public.access_codes where redeemed_by = uid and kind = 'trial'
  ) then
    return jsonb_build_object('ok', false, 'error', 'trial_used');
  end if;

  -- الأيام اللي فاضلة بتتحسب: كود جديد قبل ما القديم يخلص بيزوّد عليه.
  -- Remaining days carry over: a new code before the old one ends adds on.
  base := case
    when s.user_id is not null and not s.disabled and s.ends_at > now() then s.ends_at
    else now()
  end;
  new_end := base + make_interval(days => c.days);

  update public.access_codes set redeemed_by = uid, redeemed_at = now() where id = c.id;

  insert into public.subscriptions (user_id, source, ends_at, disabled, code_id, updated_at)
  values (uid, 'code', new_end, false, c.id, now())
  on conflict (user_id) do update set
    source = 'code',
    ends_at = excluded.ends_at,
    disabled = false,
    code_id = excluded.code_id,
    updated_at = now();

  insert into public.redeem_attempts (user_id, ok) values (uid, true);
  insert into public.code_events (actor, code_id, user_id, action, detail)
  values (uid, c.id, uid, 'redeemed', jsonb_build_object('days', c.days, 'ends_at', new_end));

  return jsonb_build_object('ok', true, 'ends_at', new_end, 'days', c.days);
end;
$$;

-- بيشوف الحساب ليه اشتراك شغال، وبيعد النداء للمعلومة. بتتنادى من فنكشن
-- التلخيص بس (service role).
-- Checks the account has a live subscription and counts the call, for
-- information. Called only from the summarize function (service role).
create or replace function public.ai_allow(p_user uuid)
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

  insert into public.ai_usage (user_id, day, calls)
  values (p_user, (now() at time zone 'Africa/Cairo')::date, 1)
  on conflict (user_id, day) do update set calls = public.ai_usage.calls + 1;
  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.ai_allow(uuid) from public, anon, authenticated;

-- بيعمل [p_count] كود، كل واحد [p_days] يوم.
-- Makes [p_count] codes of [p_days] days each.
create or replace function public.admin_create_codes(
  p_count integer,
  p_days integer,
  p_kind text default 'trial',
  p_valid_until timestamptz default null,
  p_note text default ''
)
returns setof public.access_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  made public.access_codes;
begin
  perform public._require_admin();
  if p_count not between 1 and 500 then
    raise exception 'count must be 1..500';
  end if;
  for i in 1..p_count loop
    loop
      begin
        insert into public.access_codes (code, kind, days, valid_until, note, created_by)
        values (public._new_code(), p_kind, p_days, p_valid_until, coalesce(p_note, ''), auth.uid())
        returning * into made;
        exit;
      exception when unique_violation then
        -- نفس الكود اتعمل قبل كده (نادر جدًا) — جرّب واحد تاني.
        -- The same code already exists (very rare): try another.
      end;
    end loop;
    insert into public.code_events (actor, code_id, action, detail)
    values (auth.uid(), made.id, 'created', jsonb_build_object('days', p_days, 'kind', p_kind));
    return next made;
  end loop;
end;
$$;

-- تعديل كود: أيامه، قفله أو فتحه، ملاحظته. لو اتفعّل، التعديل بيوصل لاشتراك
-- اللي فعّله على طول.
-- Edits a code: its days, switching it off or on, its note. If it was
-- redeemed, the change reaches the redeemer's subscription at once.
create or replace function public.admin_update_code(
  p_id uuid,
  p_days integer default null,
  p_disabled boolean default null,
  p_note text default null
)
returns public.access_codes
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.access_codes;
  delta integer;
begin
  perform public._require_admin();
  select * into c from public.access_codes where id = p_id for update;
  if not found then raise exception 'no such code'; end if;

  delta := coalesce(p_days, c.days) - c.days;
  update public.access_codes set
    days = coalesce(p_days, days),
    disabled = coalesce(p_disabled, disabled),
    note = coalesce(p_note, note)
  where id = p_id
  returning * into c;

  if c.redeemed_by is not null then
    -- تغيير الأيام بيتطبق كفرق على نهاية الاشتراك، فالأيام اللي جت من أكواد
    -- تانية ما تضيعش.
    -- A change in days applies as a difference to the subscription's end,
    -- so days that came from other codes are not lost.
    update public.subscriptions set
      ends_at = case when delta <> 0 and ends_at is not null then ends_at + make_interval(days => delta) else ends_at end,
      disabled = coalesce(p_disabled, disabled),
      updated_at = now()
    where user_id = c.redeemed_by and code_id = c.id;
  end if;

  insert into public.code_events (actor, code_id, user_id, action, detail)
  values (auth.uid(), c.id, c.redeemed_by, 'updated',
          jsonb_strip_nulls(jsonb_build_object('days', p_days, 'disabled', p_disabled, 'note', p_note)));
  return c;
end;
$$;

-- كل الحسابات واشتراكاتهم واستهلاك النهاردة — الإيميل من auth.users اللي
-- التطبيق مالوش وصول ليه مباشرة.
-- Every account with its subscription and today's usage; the email comes
-- from auth.users, which the app cannot read directly.
create or replace function public.admin_users()
returns table (
  user_id uuid,
  email text,
  created_at timestamptz,
  last_sign_in_at timestamptz,
  source text,
  ends_at timestamptz,
  disabled boolean,
  used_today integer,
  code text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public._require_admin();
  return query
    select u.id, u.email::text, u.created_at, u.last_sign_in_at,
           s.source, s.ends_at, s.disabled,
           coalesce(a.calls, 0), c.code
    from auth.users u
    left join public.subscriptions s on s.user_id = u.id
    left join public.access_codes c on c.id = s.code_id
    left join public.ai_usage a on a.user_id = u.id and a.day = (now() at time zone 'Africa/Cairo')::date
    order by u.created_at desc;
end;
$$;

-- تعديل اشتراك حساب مباشرة: زوّد أيام، حدّد نهاية، من غير نهاية، اقفل/افتح.
-- لو مالوش اشتراك، بيتعمله واحد (admin).
-- Edits an account's subscription directly: add days, set an end, no end,
-- switch off/on. Without one, it gets one (admin).
create or replace function public.admin_update_user(
  p_user uuid,
  p_add_days integer default null,
  p_ends_at timestamptz default null,
  p_forever boolean default false,
  p_disabled boolean default null
)
returns public.subscriptions
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.subscriptions;
begin
  perform public._require_admin();
  insert into public.subscriptions (user_id, source, ends_at)
  values (p_user, 'admin', now())
  on conflict (user_id) do nothing;

  update public.subscriptions set
    ends_at = case
      when p_forever then null
      when p_ends_at is not null then p_ends_at
      when p_add_days is not null then greatest(coalesce(ends_at, now()), now()) + make_interval(days => p_add_days)
      else ends_at
    end,
    disabled = coalesce(p_disabled, disabled),
    updated_at = now()
  where user_id = p_user
  returning * into s;

  insert into public.code_events (actor, user_id, action, detail)
  values (auth.uid(), p_user, 'user_updated', jsonb_strip_nulls(jsonb_build_object(
    'add_days', p_add_days, 'ends_at', p_ends_at, 'forever', nullif(p_forever, false), 'disabled', p_disabled
  )));
  return s;
end;
$$;
