-- STAGING ONLY: one-time reward and repeatability change tests. ROLLBACK.
BEGIN;
DO $setup$
DECLARE fid uuid; c uuid; p uuid; t uuid; r1 uuid; r2 uuid; balance bigint;
BEGIN
 SELECT id INTO STRICT fid FROM public.families WHERE name='Family Hub v3 - STAGING ONLY';
 SELECT id INTO STRICT c FROM public.child_profiles WHERE family_id=fid AND name='Adalee (TEST)';
 SELECT id INTO STRICT p FROM auth.users WHERE email='daniel+fhv3parent@gmail.com';
 SELECT id INTO STRICT t FROM auth.users WHERE email='daniel+fhv3tablet@gmail.com';
 SELECT COALESCE(SUM(points),0) INTO balance FROM public.point_transactions WHERE child_id=c;
 IF balance<>20 THEN RAISE EXCEPTION 'Unexpected staging balance %',balance;END IF;
 INSERT INTO public.rewards(family_id,title,points_cost,repeatable) VALUES(fid,'TEMP ONE TIME TEST',5,false) RETURNING id INTO r1;
 INSERT INTO public.rewards(family_id,title,points_cost,repeatable) VALUES(fid,'TEMP REPEAT CHANGE TEST',3,true) RETURNING id INTO r2;
 PERFORM set_config('test.child',c::text,true);
 PERFORM set_config('test.parent',p::text,true);
 PERFORM set_config('test.tablet',t::text,true);
 PERFORM set_config('test.once_reward',r1::text,true);
 PERFORM set_config('test.changing_reward',r2::text,true);
END;
$setup$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.tablet'),true);
SET LOCAL ROLE authenticated;
SELECT set_config('test.once_request',public.request_reward(current_setting('test.once_reward')::uuid,current_setting('test.child')::uuid)::text,true);
SELECT set_config('request.jwt.claim.sub',current_setting('test.parent'),true);
SELECT public.approve_reward_request(current_setting('test.once_request')::uuid);
SELECT set_config('request.jwt.claim.sub',current_setting('test.tablet'),true);
DO $once$
BEGIN
 BEGIN
  PERFORM public.request_reward(current_setting('test.once_reward')::uuid,current_setting('test.child')::uuid);
  RAISE EXCEPTION 'TEST FAILURE: redeemed a one-time reward twice';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE;END IF;
  IF SQLERRM NOT LIKE 'This one-time reward has already%' THEN RAISE;END IF;
 END;
END;$once$;
-- Prove changing a reward to one-time also blocks approval of an already
-- pending second request, while preserving the first approved redemption.
SELECT set_config('test.first_repeat_request',public.request_reward(current_setting('test.changing_reward')::uuid,current_setting('test.child')::uuid)::text,true);
SELECT set_config('request.jwt.claim.sub',current_setting('test.parent'),true);
SELECT public.approve_reward_request(current_setting('test.first_repeat_request')::uuid);
SELECT set_config('request.jwt.claim.sub',current_setting('test.tablet'),true);
SELECT set_config('test.second_repeat_request',public.request_reward(current_setting('test.changing_reward')::uuid,current_setting('test.child')::uuid)::text,true);
SELECT set_config('request.jwt.claim.sub',current_setting('test.parent'),true);
UPDATE public.rewards SET repeatable=false WHERE id=current_setting('test.changing_reward')::uuid;
DO $check$
DECLARE points_now bigint; first_count int;
BEGIN
 BEGIN
  PERFORM public.approve_reward_request(current_setting('test.second_repeat_request')::uuid);
  RAISE EXCEPTION 'TEST FAILURE: approved a second redemption after one-time toggle';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE;END IF;
  IF SQLERRM NOT LIKE 'This one-time reward has already%' THEN RAISE;END IF;
 END;
 PERFORM public.decline_reward_request(current_setting('test.second_repeat_request')::uuid);
 SELECT COALESCE(SUM(points),0) INTO points_now FROM public.point_transactions WHERE child_id=current_setting('test.child')::uuid;
 IF points_now<>12 THEN RAISE EXCEPTION 'Unexpected point balance %',points_now;END IF;
 SELECT COUNT(*) INTO first_count FROM public.point_transactions WHERE reward_request_id=current_setting('test.once_request')::uuid;
 IF first_count<>1 THEN RAISE EXCEPTION 'Duplicate one-time debit %',first_count;END IF;
END;$check$;
SELECT 'PASS: one-time reward limited to one approval, repeatable change guarded, no duplicate debit, balance sound' AS result;
ROLLBACK;