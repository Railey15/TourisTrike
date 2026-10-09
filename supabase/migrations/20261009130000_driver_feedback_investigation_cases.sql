-- A verified tour review may be escalated into the same auditable municipal
-- case workflow. Opening a case never suspends the driver automatically.
begin;

alter table public.municipal_complaints
  add column source_review_id uuid unique references public.driver_reviews(id)
    on delete restrict;

create function public.open_municipal_driver_feedback_case(
  p_review_id uuid,p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_review public.driver_reviews;
  v_booking public.package_bookings;
  v_id uuid;
begin
  select * into v_review from public.driver_reviews where id=p_review_id;
  if not found then raise exception 'VERIFIED_REVIEW_NOT_FOUND'; end if;
  select * into v_booking from public.package_bookings
    where id=v_review.booking_id;
  if not found or not public.is_municipal_complaint_officer(
      v_booking.municipality,v_booking.province) then
    raise exception 'MTO_SCOPE_REQUIRED' using errcode='42501';
  end if;
  if v_review.tourist_id is distinct from v_booking.tourist_id
     or not exists(select 1 from public.booking_drivers d
       where d.booking_id=v_booking.id and d.driver_id=v_review.driver_id
         and d.status='completed') then
    raise exception 'REVIEW_BOOKING_MISMATCH' using errcode='42501';
  end if;
  if char_length(btrim(coalesce(p_description,''))) not between 20 and 2000 then
    raise exception 'DOCUMENTED_REVIEW_REASON_REQUIRED' using errcode='22023';
  end if;
  if exists(select 1 from public.municipal_complaints
      where source_review_id=p_review_id) then
    raise exception 'REVIEW_CASE_ALREADY_EXISTS' using errcode='23505';
  end if;
  insert into public.municipal_complaints(booking_id,municipality,province,
    reporter_id,reported_user_id,reported_role,category,description,
    source_review_id)
  values(v_booking.id,v_booking.municipality,v_booking.province,auth.uid(),
    v_review.driver_id,'driver','service',btrim(p_description),p_review_id)
  returning id into v_id;
  insert into public.municipal_complaint_events
    (complaint_id,actor_id,action,details)
  values(v_id,auth.uid(),'submitted',
    'MTO opened a case from verified driver review '||p_review_id::text);
  insert into public.notifications(user_id,title,body,type)
  values(v_review.driver_id,'Feedback under municipal review',
    'Your completed-tour feedback is under municipal review. You can view the case and any decision in TourisTrike.',
    'municipal_complaint');
  return v_id;
end $$;

revoke all on function public.open_municipal_driver_feedback_case(uuid,text)
  from public,anon;
grant execute on function public.open_municipal_driver_feedback_case(uuid,text)
  to authenticated;

commit;
