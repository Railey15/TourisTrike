import { readFileSync } from 'node:fs';

// Runs within the isolated waiting/review database, using current backend bodies
// for the financial path. External completion/payout services stay stubbed.
export async function runPaymentCases({db,check,failure,scalar,login,uuid,migration,section}) {
  await login('');
  await db.exec(`
    alter table package_bookings add column downpayment_amount numeric default 0,
      add column required_drivers integer default 1;
    alter table booking_drivers add column accepted_at timestamptz default now();
    alter table package_activities add column tour_status text,add column updated_at timestamptz;
    alter table payment_records alter column id set default gen_random_uuid();
    alter table payment_records add column payer_id uuid,add column payee_id uuid,
      add column provider text default 'manual',add column payment_method text default 'cash',
      add column currency text default 'PHP',add column provider_status text,
      add column provider_reference text,add column provider_livemode boolean default false,
      add column idempotency_key text,add column service_description text,
      add column provider_payment_id text,add column provider_checkout_id text,
      add column provider_payment_intent_id text,add column provider_payload jsonb,
      add column provider_fee_amount numeric,add column provider_net_amount numeric;
    create table payment_allocations(id uuid primary key default gen_random_uuid(),
      payment_record_id uuid,booking_id uuid,booking_driver_id uuid,driver_id uuid,
      gross_amount numeric,platform_fee numeric,driver_amount numeric,split_basis_points integer,
      currency text,status text,provider_recipient_id text,created_at timestamptz default now(),
      paid_at timestamptz,last_error text,unique(payment_record_id,driver_id));
    create table driver_payout_accounts(driver_id uuid,provider text,destination_type text,
      verification_status text,is_default boolean,provider_livemode boolean,
      provider_recipient_id text,updated_at timestamptz);
    create table payment_provider_events(id uuid default gen_random_uuid(),provider text,
      provider_event_id text,event_type text,provider_livemode boolean,provider_payment_id text,
      provider_checkout_id text,payload jsonb,processing_status text,processed_at timestamptz,
      process_error text,payment_record_id uuid,unique(provider,provider_event_id));
    create function subtenant_can_access_payment_record(uuid) returns boolean language sql as $$select false$$;
    create function finalize_package_booking_if_eligible(uuid) returns jsonb language sql as $$select '{}'::jsonb$$;
  `);
  await db.exec(readFileSync(new URL('./tour_payment_architecture_fixture.sql',import.meta.url),'utf8'));
  // Earlier report-only tests deliberately used impossible submission amounts
  // to distinguish pending from collected cash. Retire those two synthetic
  // rows before enabling actual payment constraints for the financial cases.
  await db.query('delete from payment_records where id in ($1,$2)',[uuid(50),uuid(51)]);
  // The existing index includes confirmed receipts. Execute the exact feature
  // extension against that original index and the actual preparation functions.
  await db.exec(`create unique index payment_records_one_active_booking_stage_idx
    on payment_records(booking_id,payment_stage) where booking_id is not null and status <> 'cancelled';`);
  const start=migration.indexOf('drop index public.payment_records_one_active_booking_stage_idx;');
  const end=migration.indexOf('end $waiting_payment_reuse$;',start);
  await db.exec(migration.slice(start,end+'end $waiting_payment_reuse$;'.length));
  await db.exec(`
    create trigger trg_validate_booking_payment_submission before insert on payment_records
      for each row execute function validate_booking_payment_submission();
    create trigger trg_finalize_booking_after_payment_requirement after insert or update
      on booking_payment_requirements for each row execute function finalize_booking_after_payment_requirement();
  `);
  const tourist=uuid(2),driver=uuid(3);
  let serial=500;
  const seed=async({obligation=750,credited=750,requirement=obligation}={})=>{
    await login('');
    const bid=uuid(serial++),roster=uuid(serial++),oldReceipt=uuid(serial++);
    // The examples concern the remaining stage. A separate already confirmed
    // downpayment supplies normal preparation prerequisites, never credits it twice.
    await db.query(`insert into package_bookings(id,tourist_id,municipality,province,status,
      booking_status,total_amount,downpayment_amount,remaining_balance)
      values($1,$2,'Alpha','Bulacan','ongoing','on_tour',$3+750,750,$3-$4)`,[bid,tourist,obligation,credited]);
    await db.query(`insert into booking_drivers(id,booking_id,driver_id,status) values($1,$2,$3,'accepted')`,[roster,bid,driver]);
    await db.exec('alter table payment_records disable trigger trg_validate_booking_payment_submission');
    await db.query(`insert into payment_records(id,booking_id,payment_stage,status,amount,payer_id,payee_id)
      values($1,$2,'down_payment','confirmed',750,$3,$4)`,[uuid(serial++),bid,tourist,driver]);
    if(credited>0)await db.query(`insert into payment_records(id,booking_id,payment_stage,status,amount,payer_id,payee_id)
      values($1,$2,'remaining_balance','confirmed',$3,$4,$5)`,[oldReceipt,bid,credited,tourist,driver]);
    if(credited>0)await db.query(`insert into payment_allocations(payment_record_id,booking_id,booking_driver_id,driver_id,gross_amount,platform_fee,driver_amount,split_basis_points,currency,status)
      values($1,$2,$3,$4,$5,0,$5,10000,'PHP','cash_confirmed')`,[oldReceipt,bid,roster,driver,credited]);
    await db.exec('alter table payment_records enable trigger trg_validate_booking_payment_submission');
    // Legacy partial-credit state is preserved, without inventing support for
    // new partial submissions. A satisfied stage is inserted only at zero debt.
    await db.query(`insert into booking_payment_requirements(booking_id,payment_stage,amount,status,satisfied_by_payment_record_id)
      values($1,'remaining_balance',$2,$3,$4)`,[bid,requirement,credited===obligation?'satisfied':'required',credited===obligation?oldReceipt:null]);
    return {bid,roster,oldReceipt,base:obligation,packageAmount:obligation+750};
  };
  const stop=async(bid,{minutes=1,rate=40}={})=>{
    await login('');
    const sid=uuid(serial++);
    await db.query(`insert into booking_itinerary_items(id,booking_id,destination_name,estimated_stay_duration_minutes,spot_status)
      values($1,$2,'Financial regression',60,'completed')`,[sid,bid]);
    await db.query(`update booking_itinerary_items set actual_arrival_time='2026-09-28 08:00+00' where id=$1`,[sid]);
    // Per-stop fixture snapshot, never municipal business-rate configuration.
    await db.query('update booking_stop_waiting_charges set rate_per_interval=$2 where itinerary_item_id=$1',[sid,rate]);
    await db.query(`update booking_itinerary_items set actual_departure_time='2026-09-28 09:00+00'::timestamptz+make_interval(mins=>$2) where id=$1`,[sid,minutes]);
    return sid;
  };
  const debt=bid=>scalar('select remaining_balance from package_bookings where id=$1',[bid]).then(Number);
  const required=bid=>scalar("select amount from booking_payment_requirements where booking_id=$1 and payment_stage='remaining_balance'",[bid]).then(Number);
  const jsonReceipt=id=>scalar('select to_jsonb(p) from payment_records p where id=$1',[id]);
  const amounts=async b=>({historical:b.base+Number(await scalar("select coalesce(sum(additional_amount),0) from booking_stop_waiting_charges where booking_id=$1",[b.bid])),
    confirmed:Number(await scalar("select coalesce(sum(amount),0) from payment_records where booking_id=$1 and payment_stage='remaining_balance' and status='confirmed'",[b.bid])),outstanding:await debt(b.bid),requirement:await required(b.bid)});
  const cash=async b=>{
    await login(tourist);
    return (await db.query('select to_jsonb(public.prepare_group_cash_remaining_balance($1,$2)) as payment',[b.bid,'financial-regression-'+b.bid])).rows[0].payment;
  };
  const confirm=async id=>{await login(driver);return db.query('select public.confirm_group_cash_share($1)',[id]);};

  const unpaid=await seed({credited:0});
  await stop(unpaid.bid,{minutes:0});
  check(await amounts(unpaid),{historical:750,confirmed:0,outstanding:750,requirement:750},'unpaid package and no overtime retain original obligation');

  const partial=await seed({obligation:1000,credited:400});
  await stop(partial.bid);
  check(await amounts(partial),{historical:1040,confirmed:400,outstanding:640,requirement:640},'existing partial credit is not billed or subtracted twice');
  const partialPayment=await cash(partial);
  check(Number(partialPayment.amount),640,'partial-credit booking requires only unpaid 640');
  await confirm(partialPayment.id);
  check(await debt(partial.bid),0,'partial-credit booking can settle current unpaid amount');

  const b=await seed();
  const old=await jsonReceipt(b.oldReceipt);
  const oldAllocation=await scalar('select to_jsonb(a) from payment_allocations a where payment_record_id=$1',[b.oldReceipt]);
  const sid=await stop(b.bid);
  check(await amounts(b),{historical:790,confirmed:750,outstanding:40,requirement:40},'exact paid-750 plus waiting-40 regression');
  check(await scalar("select satisfied_by_payment_record_id from booking_payment_requirements where booking_id=$1 and payment_stage='remaining_balance'",[b.bid]),null,'new debt clears old payment proof');
  check(await scalar('select is_booking_remaining_payment_satisfied($1)',[b.bid]),false,'old receipt cannot satisfy new obligation');
  await login(tourist);
  for(const amount of [0,-1,20,790])await failure(`insert into payment_records(booking_id,payment_stage,status,amount,payer_id,payee_id)
    values($1,'remaining_balance','pending_confirmation',$2,$3,$4)`,[b.bid,amount,tourist,driver],'INVALID_PAYMENT_AMOUNT');
  const p=await cash(b);
  check(Number(p.amount),40,'actual group-cash backend accepts correct 40 submission');
  check(Number(await scalar('select sum(gross_amount) from payment_allocations where payment_record_id=$1',[p.id])),40,'new allocations cover only new debt');
  check((await cash(b)).id,p.id,'reconnect/preparation retry reuses the unresolved collection');
  check(Number(await scalar('select count(*) from payment_allocations where payment_record_id=$1',[p.id])),1,'retry does not duplicate allocations');
  await failure(`insert into payment_records(booking_id,payment_stage,status,amount,payer_id,payee_id)
    values($1,'remaining_balance','pending_confirmation',40,$2,$3)`,[b.bid,tourist,driver],'payment_records_one_active_booking_stage_idx');
  await login('');
  await db.query('update booking_itinerary_items set actual_departure_time=actual_departure_time where id=$1',[sid]);
  check(await debt(b.bid),40,'departure retry/realtime repeat does not duplicate debt');
  check(await required(b.bid),40,'departure retry does not duplicate requirement');
  await confirm(p.id);
  check(await amounts(b),{historical:790,confirmed:790,outstanding:0,requirement:40},'legitimate 40 confirmation settles debt without deleting historical obligation');
  const paid=await jsonReceipt(p.id);
  await confirm(p.id);
  check(await jsonReceipt(p.id),paid,'duplicate cash confirmation preserves receipt');
  check(await debt(b.bid),0,'duplicate confirmation does not credit twice');
  check(await jsonReceipt(b.oldReceipt),old,'historical confirmed 750 remains byte-for-byte unchanged');
  check(await scalar('select to_jsonb(a) from payment_allocations a where payment_record_id=$1',[b.oldReceipt]),oldAllocation,'historical allocation remains byte-for-byte unchanged');
  check(Number(await scalar('select total_amount from package_bookings where id=$1',[b.bid])),b.packageAmount,'original package price remains unchanged');
  check(Number(await scalar('select additional_amount from booking_stop_waiting_charges where itinerary_item_id=$1',[sid])),40,'historical waiting ledger survives settlement');
  await login(tourist);
  await failure('select prepare_group_cash_remaining_balance($1,$2)',[b.bid,'no-more-debt-payment-key'],'PAYMENT_STAGE_NOT_DUE');

  // An old confirmation replay after a later charge cannot close its new stage.
  await stop(b.bid,{rate:20});
  await confirm(p.id);
  check(await debt(b.bid),20,'old confirmed allocation replay cannot erase later waiting debt');
  check(await scalar('select is_booking_remaining_payment_satisfied($1)',[b.bid]),false,'later obligation still needs new proof');

  const multiple=await seed();
  await stop(multiple.bid);await stop(multiple.bid,{rate:20});
  check(await amounts(multiple),{historical:810,confirmed:750,outstanding:60,requirement:60},'multiple finalized stops aggregate to current 60 debt');
  await login(tourist);
  await failure(`insert into payment_records(booking_id,payment_stage,status,amount,payer_id,payee_id)
    values($1,'remaining_balance','pending_confirmation',40,$2,$3)`,[multiple.bid,tourist,driver],'INVALID_PAYMENT_AMOUNT');
  const aggregate=await cash(multiple);await confirm(aggregate.id);
  check(await debt(multiple.bid),0,'legitimate full 60 payment settles aggregate waiting');

  const uncollected=await seed({credited:0});
  await stop(uncollected.bid,{rate:30,minutes:16});
  check(await amounts(uncollected),{historical:810,confirmed:0,outstanding:810,requirement:810},'750 unpaid plus 60 waiting requires 810');
  const final810=await cash(uncollected);await confirm(final810.id);
  check(await debt(uncollected.bid),0,'legitimate 810 payment credits outstanding exactly once');
  check(Number(await scalar('select sum(additional_amount) from booking_stop_waiting_charges where booking_id=$1',[uncollected.bid])),60,'paid 810 retains historical waiting of 60');

  const missing=await seed({credited:0});
  await db.query("delete from booking_payment_requirements where booking_id=$1",[missing.bid]);
  await stop(missing.bid);
  check(await required(missing.bid),790,'missing requirement is inserted for all current debt, not only fee');

  const online=await seed();
  await stop(online.bid);
  await login(tourist);
  const prepared=(await db.query("select prepare_paymongo_payment_authenticated_impl($1,'remaining_balance',$2,$3,false) as result",[online.bid,'paymongo-waiting-regression-key',tourist])).rows[0].result;
  check(Number(prepared.payment.amount),40,'PayMongo preparation ignores historical manual confirmed receipt');
  const reused=(await db.query("select prepare_paymongo_payment_authenticated_impl($1,'remaining_balance',$2,$3,false) as result",[online.bid,'paymongo-waiting-regression-key',tourist])).rows[0].result;
  check(reused.payment.id,prepared.payment.id,'PayMongo idempotency key reuses original pending receipt');
  check(Number(await scalar('select sum(gross_amount) from payment_allocations where payment_record_id=$1',[prepared.payment.id])),40,'PayMongo allocations total new debt only');
  await login(driver);
  await failure('select confirm_payment_record($1)',[prepared.payment.id],'PROVIDER_WEBHOOK_REQUIRED');
  await login('');
  const webhook=async event=>scalar(`select process_paymongo_webhook_event($1,'payment.paid',false,'fixture-provider-payment',null,null,$2,'paid',4000,null,null,'{}'::jsonb)`,[event,prepared.payment.provider_reference]);
  check((await webhook('fixture-paid-event-1')).confirmed,true,'trusted PayMongo webhook confirms actual 40 receipt');
  check(await debt(online.bid),0,'PayMongo confirmation clears only current 40 debt');
  const onlinePaid=await jsonReceipt(prepared.payment.id);
  const onlineAlloc=await scalar('select to_jsonb(a) from payment_allocations a where payment_record_id=$1',[prepared.payment.id]);
  check((await webhook('fixture-paid-event-1')).duplicate,true,'same webhook event is idempotent');
  await stop(online.bid);
  check((await webhook('fixture-paid-event-2')).duplicate,true,'different paid event for old receipt is ignored');
  check(await debt(online.bid),40,'old equal-amount webhook cannot settle a later 40 obligation');
  check(await jsonReceipt(prepared.payment.id),onlinePaid,'provider replay preserves confirmed payment history');
  check(await scalar('select to_jsonb(a) from payment_allocations a where payment_record_id=$1',[prepared.payment.id]),onlineAlloc,'provider replay preserves allocation history');

  // The scoped report must count confirmed records, never gross requirements.
  await login(uuid(1));
  const report=await scalar("select get_tour_operations_report('2026-01-01','2027-01-01','Alpha')");
  const confirmed=Number(await scalar("select coalesce(sum(p.amount),0) from payment_records p join package_bookings b on b.id=p.booking_id where p.status='confirmed' and b.municipality='Alpha' and b.province='Bulacan'"));
  check(Number(report.confirmed_collections),confirmed,'report collections count only confirmed receipts');
  await login(tourist);
  const summary=await scalar('select get_booking_waiting_summary($1)',[b.bid]);
  check(Number(summary.total_remaining),20,'waiting summary reports actual post-settlement current outstanding');
  check(Number(summary.finalized_waiting),60,'waiting summary retains finalized history after collection');
}
