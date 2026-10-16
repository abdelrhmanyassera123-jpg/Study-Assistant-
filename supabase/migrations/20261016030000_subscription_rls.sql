-- =====================================================================
-- الاشتراك مطلوب على مستوى الداتابيز
-- A subscription is required at the database itself
-- =====================================================================
-- شاشة الكود في التطبيق لوحدها مش كفاية: نسخة قديمة من التطبيق محفوظة على
-- الموبايل (أو أي حد بينادي الـ API مباشرة) كانت بتعدّي من غيرها. دلوقتي أي
-- حساب مالوش اشتراك شغال مش بيقدر يقرا ولا يكتب داتا المذاكرة خالص.
--
-- The app's code screen alone was not enough: an older copy of the app
-- saved on a phone (or anyone calling the API directly) got past it. Now an
-- account without a live subscription can neither read nor write any study
-- data at all.
--
-- سياسة restrictive بتتضاف (AND) على سياسات "own_*" اللي موجودة. مفتاح
-- الخدمة (الفنكشنز) مش بيتأثر — هو أصلًا فوق RLS.
-- A restrictive policy is ANDed onto the existing "own_*" policies. The
-- service key (the functions) is unaffected — it sits above RLS anyway.
-- =====================================================================

create or replace function public.has_access()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
      or exists (
        select 1 from public.subscriptions s
        where s.user_id = auth.uid()
          and not s.disabled
          and (s.ends_at is null or s.ends_at > now())
      );
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'subjects', 'tasks', 'notes', 'flashcards', 'card_reviews', 'study_sessions',
    'style_samples', 'style_profiles', 'schedule_entries', 'lecture_jobs', 'past_questions'
  ] loop
    execute format('drop policy if exists "subscription_required" on public.%I', t);
    -- (select ...) بتتحسب مرة واحدة للاستعلام كله، مش مرة لكل صف.
    -- (select ...) is evaluated once per query, not once per row.
    execute format(
      'create policy "subscription_required" on public.%I as restrictive for all to authenticated '
      'using ((select public.has_access())) with check ((select public.has_access()))',
      t
    );
  end loop;
end $$;
