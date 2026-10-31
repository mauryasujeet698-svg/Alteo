do $schedule$
declare v_job record;
begin
  for v_job in
    select jobid from cron.job where jobname = 'alteo_delivery_partner_inactivity_offline'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'alteo_delivery_partner_inactivity_offline',
    '* * * * *',
    'select private.mark_stale_delivery_partners_offline();'
  );
end
$schedule$;
