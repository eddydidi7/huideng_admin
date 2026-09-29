-- Optional deployment step after enabling Supabase Cron on the target STAGING project.
-- The database owner schedules this internal function; no public function endpoint.
select cron.schedule('huideng-publish-notices', '* * * * *',
  'select public.huideng_publish_due_notices();');
-- Check cron.job before execution to avoid duplicate jobs. Monitor cron.job_run_details.
