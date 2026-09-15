-- =====================================================================
-- الكرون بيقرا سر الحماية من Vault، مش من app.settings
-- The cron job reads the guard secret from Vault, not app.settings
-- =====================================================================
-- ALTER DATABASE ... SET رفضته صلاحيات الدور اللي الـ CLI بيوصل بيه
-- (permission denied to set parameter)، فالسر بقى متخزّن في Supabase Vault
-- بدالها (extension "supabase_vault" متفعّلة بالفعل على المشروع ده). القيمة
-- نفسها اتحطت مرة واحدة بأمر منفصل مش متسجّل في الجيت، بالظبط زي القيمة
-- القديمة في app.settings.
--
-- ALTER DATABASE ... SET was refused by the role the CLI connects as
-- (permission denied to set parameter), so the secret now lives in Supabase
-- Vault instead (the "supabase_vault" extension is already enabled on this
-- project). The value itself was set once by a separate command not
-- committed to git, exactly like the old app.settings value.
-- =====================================================================

select cron.alter_job(
  (select jobid from cron.job where jobname = 'send-reminders-every-minute'),
  command := $$
    select net.http_post(
      url := 'https://epcddoelvsqzbsiaeyem.supabase.co/functions/v1/send-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'cron_secret'
        )
      ),
      body := '{}'::jsonb
    );
  $$
);
