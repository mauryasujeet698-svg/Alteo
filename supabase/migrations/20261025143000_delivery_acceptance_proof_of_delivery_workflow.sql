create or replace function public.partner_update_delivery_status(
  p_delivery_job_id uuid,
  p_action text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job public.delivery_jobs%rowtype;
  v_order_payment text;
begin
  if (select auth.uid()) is null then
    raise exception 'sign-in required' using errcode = '42501';
  end if;

  select * into v_job
    from public.delivery_jobs
    where id = p_delivery_job_id
    for update;
  if not found or v_job.delivery_partner_id <> (select auth.uid()) then
    raise exception 'this delivery is not assigned to you' using errcode = '42501';
  end if;

  if p_action = 'accept' then
    update public.delivery_assignments
      set status = 'accepted', updated_at = now()
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status = 'offered';
    if not found then raise exception 'no pending offer found' using errcode = '22023'; end if;

    update public.delivery_jobs
      set status = 'accepted', updated_at = now()
      where id = p_delivery_job_id and status = 'assigned';
    if not found then raise exception 'delivery is not in the assigned state' using errcode = '22023'; end if;

  elsif p_action = 'reject' then
    update public.delivery_assignments
      set status = 'rejected', updated_at = now()
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status in ('offered', 'accepted');
    update public.delivery_jobs
      set delivery_partner_id = null, status = 'pending', updated_at = now()
      where id = p_delivery_job_id;

  elsif p_action = 'picked_up' then
    if not exists (
      select 1 from public.delivery_assignments
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status = 'accepted'
    ) then
      raise exception 'accept the assignment first' using errcode = '22023';
    end if;
    if v_job.status not in ('accepted', 'assigned') then
      raise exception 'delivery must be accepted before pickup' using errcode = '22023';
    end if;
    if v_job.order_id is not null then
      select payment_status into v_order_payment from public.orders where id = v_job.order_id;
      if v_order_payment <> 'paid' then
        raise exception 'order payment is not confirmed' using errcode = '22023';
      end if;
    end if;
    update public.delivery_jobs set status = 'picked_up', updated_at = now() where id = p_delivery_job_id;
    if v_job.order_id is not null then
      update public.orders set status = 'out_for_delivery', updated_at = now() where id = v_job.order_id;
    end if;

  elsif p_action = 'in_transit' then
    if v_job.status <> 'picked_up' then
      raise exception 'item must be picked up first' using errcode = '22023';
    end if;
    update public.delivery_jobs set status = 'in_transit', updated_at = now() where id = p_delivery_job_id;

  elsif p_action = 'delivered' then
    if v_job.status <> 'in_transit' then
      raise exception 'delivery must be in transit first' using errcode = '22023';
    end if;
    update public.delivery_jobs set status = 'delivered', updated_at = now() where id = p_delivery_job_id;
    update public.delivery_assignments
      set status = 'completed', updated_at = now()
      where delivery_job_id = p_delivery_job_id
        and partner_id = (select auth.uid())
        and status = 'accepted';
    if v_job.order_id is not null then
      update public.orders set status = 'completed', updated_at = now()
      where id = v_job.order_id and payment_status = 'paid';
    end if;

  else
    raise exception 'invalid delivery action' using errcode = '22023';
  end if;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
  values ((select auth.uid()), 'delivery.' || p_action, 'delivery_job', p_delivery_job_id,
    jsonb_build_object('status_before', v_job.status, 'action', p_action));
end;
$function$;

create or replace function public.partner_record_delivery_proof(
  p_delivery_job_id uuid,
  p_cloudinary_public_id text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job public.delivery_jobs%rowtype;
begin
  if auth.uid() is null then raise exception 'sign-in required' using errcode = '42501'; end if;
  if p_cloudinary_public_id is null
     or length(trim(p_cloudinary_public_id)) < 3
     or length(trim(p_cloudinary_public_id)) > 255
     or p_cloudinary_public_id !~ '^alteo/delivery-proof/' then
    raise exception 'invalid delivery proof reference' using errcode = '22023';
  end if;

  select * into v_job from public.delivery_jobs
    where id = p_delivery_job_id and delivery_partner_id = auth.uid()
    for update;
  if not found then raise exception 'this delivery is not assigned to you' using errcode = '42501'; end if;
  if v_job.status <> 'in_transit' then
    raise exception 'delivery proof can be added while the delivery is in transit' using errcode = '22023';
  end if;

  update public.delivery_jobs
    set proof_media_public_id = trim(p_cloudinary_public_id), updated_at = now()
    where id = p_delivery_job_id;

  insert into public.audit_events(actor_id, action, entity_type, entity_id, metadata)
    values(auth.uid(), 'delivery.proof_attached', 'delivery_job', p_delivery_job_id,
      jsonb_build_object('cloudinary_public_id', trim(p_cloudinary_public_id)));
end;
$function$;

revoke all on function public.partner_update_delivery_status(uuid, text) from public;
grant execute on function public.partner_update_delivery_status(uuid, text) to authenticated;
revoke all on function public.partner_record_delivery_proof(uuid, text) from public;
grant execute on function public.partner_record_delivery_proof(uuid, text) to authenticated;
