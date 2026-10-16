-- =====================================================================
-- الاشتراكات بأكواد التفعيل
-- Subscriptions through activation codes
-- =====================================================================
-- التطبيق بقى محتاج اشتراك شغال. الاشتراك بييجي من:
--   • legacy — الحسابات اللي كانت موجودة قبل الأكواد: مجانًا ومن غير نهاية.
--   • code   — كود تفعيل: بيتستخدم مرة واحدة لحساب واحد، وبيدّي عدد أيام.
--   • admin  — الأدمن إدّاه أيام مباشرة من لوحة التحكم.
-- لما الاشتراك يخلص أو يتقفل، التطبيق بيتقفل خالص.
--
-- The app now needs a live subscription. It comes from:
--   • legacy — accounts that existed before codes: free, with no end.
--   • code   — an activation code: used once, by one account, for N days.
--   • admin  — days given directly from the dashboard.
-- When it ends or is switched off, the app locks completely.
--
-- كمان كل اشتراك ليه حد يومي لنداءات الذكاء الاصطناعي (ai_usage)، عشان حصة
-- Gemini المشتركة ما تخلصش بسبب حساب واحد.
-- Each subscription also has a daily cap on AI calls (ai_usage), so the
-- shared Gemini quota is never drained by one account.
-- =====================================================================

-- ------------------------------------------------------------ admins
create table if not exists public.admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

-- ------------------------------------------------------- access_codes
create table if not exists public.access_codes (
  id             uuid primary key default gen_random_uuid(),
  -- بالشكل اللي بيتنسخ: SA-7K3P-Q9XM.
  -- As copied: SA-7K3P-Q9XM.
  code           text not null,
  -- من غير شرط ولا مسافات وبالكابيتال، للمقارنة: المستخدم ممكن يكتبه بأي شكل.
  -- No dashes or spaces, upper case, for matching: users type it any way.
  code_key       text generated always as (upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'))) stored unique,
  kind           text not null default 'trial' check (kind in ('trial', 'paid')),
  days           integer not null check (days between 1 and 3650),
  -- آخر لحظة ينفع يتفعّل فيها. null = في أي وقت.
  -- The last moment it can be redeemed. null = any time.
  valid_until    timestamptz,
  -- حد نداءات الذكاء الاصطناعي في اليوم للي يفعّله. null = من غير حد.
  -- The daily AI-call cap for whoever redeems it. null = no cap.
  daily_ai_limit integer check (daily_ai_limit >= 0),
  note           text not null default '',
  disabled       boolean not null default false,
  redeemed_by    uuid references auth.users (id) on delete set null,
  redeemed_at    timestamptz,
  created_at     timestamptz not null default now(),
  created_by     uuid references auth.users (id) on delete set null
);
alter table public.access_codes enable row level security;

-- ------------------------------------------------------ subscriptions
-- صف واحد لكل حساب: هو اللي التطبيق والسيرفر بيسألوه.
-- One row per account: what the app and the server ask.
create table if not exists public.subscriptions (
  user_id        uuid primary key references auth.users (id) on delete cascade,
  source         text not null check (source in ('legacy', 'code', 'admin')),
  -- null = من غير نهاية.
  -- null = no end.
  ends_at        timestamptz,
  disabled       boolean not null default false,
  daily_ai_limit integer check (daily_ai_limit >= 0),
  -- آخر كود اتفعّل — قفل الكود ده أو تعديل أيامه بيأثر هنا.
  -- The last code redeemed: switching it off or changing its days acts here.
  code_id        uuid references public.access_codes (id) on delete set null,
  updated_at     timestamptz not null default now()
);
alter table public.subscriptions enable row level security;

-- ------------------------------------------------------- code_events
create table if not exists public.code_events (
  id       bigserial primary key,
  at       timestamptz not null default now(),
  actor    uuid references auth.users (id) on delete set null,
  code_id  uuid references public.access_codes (id) on delete set null,
  user_id  uuid references auth.users (id) on delete set null,
  action   text not null,
  detail   jsonb not null default '{}'::jsonb
);
alter table public.code_events enable row level security;

-- --------------------------------------------------- redeem_attempts
-- محاولات إدخال كود — الغلط منها بيتعد عشان محدش يفضل يخمّن.
-- Code entry attempts; wrong ones are counted so nobody keeps guessing.
create table if not exists public.redeem_attempts (
  id      bigserial primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  at      timestamptz not null default now(),
  ok      boolean not null
);
create index if not exists redeem_attempts_user_at on public.redeem_attempts (user_id, at);
alter table public.redeem_attempts enable row level security;

-- ---------------------------------------------------------- ai_usage
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day     date not null,
  calls   integer not null default 0,
  primary key (user_id, day)
);
alter table public.ai_usage enable row level security;

-- ------------------------------------------------------------ policies
-- المستخدم بيشوف اشتراكه واستهلاكه هو بس؛ الأدمن بيشوف كل حاجة. الكتابة كلها
-- من الدوال تحت، مش من الجداول مباشرة.
-- A user sees only their own subscription and usage; the admin sees
-- everything. All writes go through the functions below, not the tables.
drop policy if exists "own_or_admin_select" on public.subscriptions;
create policy "own_or_admin_select" on public.subscriptions
  for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists "own_or_admin_select" on public.ai_usage;
create policy "own_or_admin_select" on public.ai_usage
  for select using (user_id = auth.uid() or public.is_admin());

drop policy if exists "admin_select" on public.access_codes;
create policy "admin_select" on public.access_codes for select using (public.is_admin());

drop policy if exists "admin_select" on public.code_events;
create policy "admin_select" on public.code_events for select using (public.is_admin());

drop policy if exists "admin_select" on public.redeem_attempts;
create policy "admin_select" on public.redeem_attempts for select using (public.is_admin());

drop policy if exists "admin_select" on public.admins;
create policy "admin_select" on public.admins for select using (public.is_admin());

-- =====================================================================
-- دوال المستخدم
-- User functions
-- =====================================================================

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
  used integer;
  admin boolean := public.is_admin();
begin
  if uid is null then
    return jsonb_build_object('active', false, 'reason', 'signed_out');
  end if;

  select * into s from public.subscriptions where user_id = uid;
  select coalesce(calls, 0) into used
    from public.ai_usage where user_id = uid and day = (now() at time zone 'Africa/Cairo')::date;

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
    'daily_ai_limit', case when admin then null else s.daily_ai_limit end,
    'used_today', coalesce(used, 0),
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

  insert into public.subscriptions (user_id, source, ends_at, disabled, daily_ai_limit, code_id, updated_at)
  values (uid, 'code', new_end, false, c.daily_ai_limit, c.id, now())
  on conflict (user_id) do update set
    source = 'code',
    ends_at = excluded.ends_at,
    disabled = false,
    daily_ai_limit = excluded.daily_ai_limit,
    code_id = excluded.code_id,
    updated_at = now();

  insert into public.redeem_attempts (user_id, ok) values (uid, true);
  insert into public.code_events (actor, code_id, user_id, action, detail)
  values (uid, c.id, uid, 'redeemed', jsonb_build_object('days', c.days, 'ends_at', new_end));

  return jsonb_build_object('ok', true, 'ends_at', new_end, 'days', c.days);
end;
$$;

-- =====================================================================
-- الحصة — بتتنادى من فنكشن التلخيص بس (service role)
-- The quota, called only from the summarize function (service role)
-- =====================================================================

-- بيشوف الحساب ليه اشتراك ولسه تحت حده اليومي، ولو آه بيعد النداء ده.
-- Checks the account has a subscription and is still under its daily cap,
-- and if so counts this call.
create or replace function public.ai_allow(p_user uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.subscriptions;
  today date := (now() at time zone 'Africa/Cairo')::date;
  used integer;
begin
  if exists (select 1 from public.admins where user_id = p_user) then
    insert into public.ai_usage (user_id, day, calls) values (p_user, today, 1)
      on conflict (user_id, day) do update set calls = public.ai_usage.calls + 1;
    return jsonb_build_object('ok', true);
  end if;

  select * into s from public.subscriptions where user_id = p_user;
  if s.user_id is null or s.disabled or (s.ends_at is not null and s.ends_at <= now()) then
    return jsonb_build_object('ok', false, 'error', 'no_subscription');
  end if;

  insert into public.ai_usage (user_id, day, calls) values (p_user, today, 0)
    on conflict (user_id, day) do nothing;
  select calls into used from public.ai_usage where user_id = p_user and day = today for update;
  if s.daily_ai_limit is not null and used >= s.daily_ai_limit then
    return jsonb_build_object('ok', false, 'error', 'daily_limit', 'limit', s.daily_ai_limit);
  end if;

  update public.ai_usage set calls = calls + 1 where user_id = p_user and day = today;
  return jsonb_build_object('ok', true, 'used', used + 1, 'limit', s.daily_ai_limit);
end;
$$;

revoke all on function public.ai_allow(uuid) from public, anon, authenticated;

-- =====================================================================
-- دوال الأدمن — كلها بتتأكد إن اللي بينادي أدمن الأول
-- Admin functions; each checks the caller is an admin first
-- =====================================================================

create or replace function public._require_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admins only' using errcode = '42501';
  end if;
end;
$$;

-- كود عشوائي SA-XXXX-XXXX من حروف وأرقام مش بتتلخبط (من غير 0/O و1/I/L).
-- A random SA-XXXX-XXXX code from characters that cannot be confused (no
-- 0/O or 1/I/L).
create or replace function public._new_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  bytes bytea := extensions.gen_random_bytes(8);
  body text := '';
begin
  for i in 0..7 loop
    body := body || substr(alphabet, (get_byte(bytes, i) % 31) + 1, 1);
  end loop;
  return 'SA-' || substr(body, 1, 4) || '-' || substr(body, 5, 4);
end;
$$;

-- بيعمل [p_count] كود، كل واحد [p_days] يوم.
-- Makes [p_count] codes of [p_days] days each.
create or replace function public.admin_create_codes(
  p_count integer,
  p_days integer,
  p_kind text default 'trial',
  p_valid_until timestamptz default null,
  p_note text default '',
  p_daily_ai_limit integer default null
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
        insert into public.access_codes (code, kind, days, valid_until, daily_ai_limit, note, created_by)
        values (public._new_code(), p_kind, p_days, p_valid_until, p_daily_ai_limit, coalesce(p_note, ''), auth.uid())
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

-- تعديل كود: أيامه، قفله أو فتحه، ملاحظته، حده اليومي. لو اتفعّل، التعديل
-- بيوصل لاشتراك اللي فعّله على طول.
-- Edits a code: its days, switching it off or on, its note, its daily cap.
-- If it was redeemed, the change reaches the redeemer's subscription at once.
create or replace function public.admin_update_code(
  p_id uuid,
  p_days integer default null,
  p_disabled boolean default null,
  p_note text default null,
  p_daily_ai_limit integer default null,
  p_clear_limit boolean default false
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
    note = coalesce(p_note, note),
    daily_ai_limit = case when p_clear_limit then null else coalesce(p_daily_ai_limit, daily_ai_limit) end
  where id = p_id
  returning * into c;

  if c.redeemed_by is not null then
    -- تغيير الأيام بيتطبق كفرق على نهاية الاشتراك، فالأيام اللي جت من أكواد
    -- تانية ما تضيعش.
    -- A change in days applies as a difference to the subscription's end,
    -- so days that came from other codes are not lost.
    update public.subscriptions set
      ends_at = case when delta <> 0 and ends_at is not null then ends_at + make_interval(days => delta) else ends_at end,
      disabled = case when p_disabled is not null then p_disabled else disabled end,
      daily_ai_limit = case
        when p_clear_limit then null
        when p_daily_ai_limit is not null then p_daily_ai_limit
        else daily_ai_limit
      end,
      updated_at = now()
    where user_id = c.redeemed_by and code_id = c.id;
  end if;

  insert into public.code_events (actor, code_id, user_id, action, detail)
  values (auth.uid(), c.id, c.redeemed_by, 'updated', jsonb_strip_nulls(jsonb_build_object(
    'days', p_days, 'disabled', p_disabled, 'note', p_note,
    'daily_ai_limit', p_daily_ai_limit, 'clear_limit', nullif(p_clear_limit, false)
  )));
  return c;
end;
$$;

-- مسح كود لسه ما اتستخدمش. المستخدم قبل كده بيتقفل مش بيتمسح، عشان السجل.
-- Deletes an unused code. A used one is switched off instead, to keep the
-- record.
create or replace function public.admin_delete_code(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._require_admin();
  delete from public.access_codes where id = p_id and redeemed_by is null;
  if not found then raise exception 'only unused codes can be deleted'; end if;
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
  daily_ai_limit integer,
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
           s.source, s.ends_at, s.disabled, s.daily_ai_limit,
           coalesce(a.calls, 0), c.code
    from auth.users u
    left join public.subscriptions s on s.user_id = u.id
    left join public.access_codes c on c.id = s.code_id
    left join public.ai_usage a on a.user_id = u.id and a.day = (now() at time zone 'Africa/Cairo')::date
    order by u.created_at desc;
end;
$$;

-- تعديل اشتراك حساب مباشرة: زوّد أيام، حدّد نهاية، من غير نهاية، اقفل/افتح،
-- حد يومي. لو مالوش اشتراك، بيتعمله واحد (admin).
-- Edits an account's subscription directly: add days, set an end, no end,
-- switch off/on, daily cap. Without one, it gets one (admin).
create or replace function public.admin_update_user(
  p_user uuid,
  p_add_days integer default null,
  p_ends_at timestamptz default null,
  p_forever boolean default false,
  p_disabled boolean default null,
  p_daily_ai_limit integer default null,
  p_clear_limit boolean default false
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
    daily_ai_limit = case
      when p_clear_limit then null
      when p_daily_ai_limit is not null then p_daily_ai_limit
      else daily_ai_limit
    end,
    updated_at = now()
  where user_id = p_user
  returning * into s;

  insert into public.code_events (actor, user_id, action, detail)
  values (auth.uid(), p_user, 'user_updated', jsonb_strip_nulls(jsonb_build_object(
    'add_days', p_add_days, 'ends_at', p_ends_at, 'forever', nullif(p_forever, false),
    'disabled', p_disabled, 'daily_ai_limit', p_daily_ai_limit, 'clear_limit', nullif(p_clear_limit, false)
  )));
  return s;
end;
$$;

revoke all on function public._require_admin() from public, anon;
revoke all on function public._new_code() from public, anon, authenticated;

-- =====================================================================
-- البداية: الحسابات الموجودة تكمّل مجانًا، وصاحب المشروع أدمن
-- To start: existing accounts carry on free, and the owner is the admin
-- =====================================================================
insert into public.subscriptions (user_id, source, ends_at)
select id, 'legacy', null from auth.users
on conflict (user_id) do nothing;

insert into public.admins (user_id)
select id from auth.users where email = 'abdelrhmanyassera123@gmail.com'
on conflict (user_id) do nothing;
