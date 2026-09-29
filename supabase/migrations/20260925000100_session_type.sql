-- =====================================================================
-- نوع الجلسة — محاضرة / سكشن / لاب، لو الجدول المستورد بيوضحه
-- Session type — lecture / section / lab, when the imported table shows it
-- =====================================================================

alter table public.schedule_entries
  add column if not exists session_type text not null default ''
    check (session_type in ('', 'lecture', 'section', 'lab'));
