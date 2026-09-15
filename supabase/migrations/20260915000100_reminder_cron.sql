-- =====================================================================
-- المهمة المجدولة اللي بتبعت تنبيهات الـ push
-- The scheduled job that sends push reminders
-- =====================================================================
-- بتنادي فنكشن "send-reminders" كل دقيقة عن طريق pg_net. الفنكشن منشورة
-- بـ --no-verify-jwt (مفيش تحقق JWT من منصة Supabase على الطلب ده)، وبدل
-- كده بتتحقق بنفسها من هيدر "x-cron-secret" جوه الكود. قيمة السر دي متخزنة
-- كإعداد على مستوى الداتابيز (app.settings.cron_secret) بدل ما تتكتب هنا نص
-- صريح، عشان الملف ده يتنشر على GitHub من غير ما يسرّب أي حاجة. القيمة نفسها
-- بتتظبط مرة واحدة بأمر منفصل مش متسجّل في الجيت.
--
-- Calls the "send-reminders" function every minute via pg_net. The function
-- is deployed with --no-verify-jwt (Supabase's platform does not check a JWT
-- on this call), and instead checks the "x-cron-secret" header itself in
-- code. That secret's value lives as a database-level setting
-- (app.settings.cron_secret) instead of being written here as plain text, so
-- this file can be pushed to GitHub without leaking anything. The value
-- itself is set once by a separate command that is not committed to git.
-- =====================================================================

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

select cron.unschedule('send-reminders-every-minute')
where exists (
  select 1 from cron.job where jobname = 'send-reminders-every-minute'
);

select cron.schedule(
  'send-reminders-every-minute',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://epcddoelvsqzbsiaeyem.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', current_setting('app.settings.cron_secret', true)
    ),
    body := '{}'::jsonb
  );
  $$
);
