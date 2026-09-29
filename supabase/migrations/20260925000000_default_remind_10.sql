-- =====================================================================
-- مدة التنبيه الافتراضية بقت 10 دقايق بدل 15
-- Default reminder lead time is now 10 minutes instead of 15
-- =====================================================================

alter table public.notification_prefs
  alter column default_remind_minutes set default 10;

-- الصفوف الموجودة اللي لسه على القيمة الافتراضية القديمة (يعني محدّش غيّرها
-- بنفسه) بتتحدّث للقيمة الجديدة. صف مُتغيّر يدويًا (أي رقم غير 15) بيفضل
-- زي ما هو.
-- Existing rows still on the old default (meaning nobody changed it
-- themselves) are updated to the new value. A row someone set by hand (any
-- number other than 15) is left untouched.
update public.notification_prefs
set default_remind_minutes = 10
where default_remind_minutes = 15;
