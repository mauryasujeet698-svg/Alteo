-- Retry queued work when an approved partner becomes available or the Admin
-- enables automatic dispatch. Previously the triggers ran only when an order/job
-- was created or changed, so a pending job could remain unassigned after a partner
-- came online.
create or replace function public.dispatch_on_partner_availability()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.is_online is true then
    if new.role = 'driver_partner' then
      perform private.dispatch_pending_rides(new.area_code);
    elsif new.role = 'delivery_partner' then
      perform private.dispatch_pending_deliveries(new.area_code);
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists partner_presence_dispatch_pending on public.partner_presence;
create trigger partner_presence_dispatch_pending
after insert or update of is_online, area_code
on public.partner_presence
for each row
when (new.is_online is true and new.role in ('driver_partner', 'delivery_partner'))
execute function public.dispatch_on_partner_availability();

create or replace function public.dispatch_on_service_control_enabled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.enabled is true and new.automatic_assignment is true then
    if new.service = 'ride' then
      perform private.dispatch_pending_rides(new.area_code);
    else
      perform private.dispatch_pending_deliveries(new.area_code);
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists service_controls_auto_dispatch on public.service_controls;
create trigger service_controls_auto_dispatch
after insert or update of enabled, automatic_assignment
on public.service_controls
for each row
when (new.enabled is true and new.automatic_assignment is true)
execute function public.dispatch_on_service_control_enabled();

comment on function public.dispatch_on_partner_availability() is
  'Automatically retry pending rides or deliveries when an approved driver/delivery partner comes online.';
comment on function public.dispatch_on_service_control_enabled() is
  'Automatically retry eligible pending jobs when a service and automatic assignment are enabled.';
