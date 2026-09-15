-- =====================================================================
-- تمييز الإرسال حسب مدة التنبيه كمان، مش بس المحاضرة والمعاد
-- Dedupe sends by lead time too, not just the lecture and its occurrence
-- =====================================================================
-- لو المستخدم غيّر "قبلها بكام دقيقة" بعد ما التنبيه بتاع النهاردة بعت
-- بالفعل، كان التغيير مش بيأثر: نفس (entry_id, occurrence_at) يبقى
-- "مبعوت" خلاص حتى لو المدة اتغيّرت، فالتنبيه الجديد ما كانش بيطلع أبدًا
-- لحد بكرة.
--
-- Changing "how many minutes before" after today's reminder had already
-- gone out had no effect: the same (entry_id, occurrence_at) stayed
-- "already sent" even though the lead time changed, so the new reminder
-- never fired until tomorrow.
-- =====================================================================

alter table public.push_reminders_sent
  drop constraint push_reminders_sent_pkey;

alter table public.push_reminders_sent
  add column if not exists remind_minutes smallint not null default 0;

alter table public.push_reminders_sent
  add primary key (entry_id, occurrence_at, remind_minutes);

alter table public.push_reminders_sent
  alter column remind_minutes drop default;
