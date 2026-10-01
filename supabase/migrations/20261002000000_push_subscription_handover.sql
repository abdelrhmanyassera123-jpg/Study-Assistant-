-- =====================================================================
-- اشتراك الإشعارات بينتقل للحساب اللي دخل على الجهاز
-- A push subscription moves to whichever account signs in on the device
-- =====================================================================
-- الـ endpoint فريد لكل جهاز ومحدش يعرفه غير الجهاز نفسه. لو حساب تاني دخل
-- على نفس الجهاز، الـ upsert كان بيفشل بصمت (الصف ملك الحساب الأول والـ RLS
-- بيمنع تعديله)، فالجهاز كان بيفضل يستقبل تنبيهات الحساب الأول ومش بيستقبل
-- تنبيهات الحساب الجديد. اللي معاه الـ endpoint هو صاحب الجهاز، فبينقله لنفسه.
--
-- An endpoint is unique to a device and known only to that device. When
-- another account signed in on the same device, the upsert failed silently
-- (the row belongs to the first account and RLS blocks changing it), so the
-- device kept receiving the first account's reminders and never the new
-- one's. Whoever presents the endpoint holds the device, so it moves to them.
-- =====================================================================

create or replace function public.claim_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth text
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.push_subscriptions (user_id, endpoint, p256dh, auth)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set user_id = excluded.user_id,
        p256dh = excluded.p256dh,
        auth = excluded.auth
  where auth.uid() is not null;
$$;

revoke all on function public.claim_push_subscription(text, text, text) from public, anon;
grant execute on function public.claim_push_subscription(text, text, text) to authenticated;
