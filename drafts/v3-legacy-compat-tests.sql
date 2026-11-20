-- STAGING ONLY. Verify v2.1 CRUD behavior survives the v3 RLS rollout.
-- Parent can add/edit/remove all four legacy record types.
-- Tablet may not read or write those records.
-- Everything rolls back; no family data is changed.
BEGIN;
DO $setup$
DECLARE fid uuid; p uuid; t uuid;
BEGIN
 SELECT id INTO STRICT fid FROM public.families WHERE name='Family Hub v3 - STAGING ONLY';
 SELECT id INTO STRICT p FROM auth.users WHERE email='daniel+fhv3parent@gmail.com';
 SELECT id INTO STRICT t FROM auth.users WHERE email='daniel+fhv3tablet@gmail.com';
 PERFORM set_config('test.fid',fid::text,true);
 PERFORM set_config('test.parent',p::text,true);
 PERFORM set_config('test.tablet',t::text,true);
END;
$setup$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.parent'),true);
SET LOCAL ROLE authenticated;
DO $parent$
DECLARE e uuid; c uuid; g uuid; m uuid; n int;
BEGIN
 INSERT INTO public.events(family_id,title,description,starts_at,ends_at,assigned_to,color)
 VALUES(current_setting('test.fid')::uuid,'V2 COMPAT - event','FH_ALL_DAY',now(),NULL,'Family','#123456')
 RETURNING id INTO e;
 INSERT INTO public.chores(family_id,title,assigned_to,completed)
 VALUES(current_setting('test.fid')::uuid,'V2 COMPAT - chore','Mom',false)
 RETURNING id INTO c;
 INSERT INTO public.groceries(family_id,item_name,quantity,completed)
 VALUES(current_setting('test.fid')::uuid,'V2 COMPAT - grocery','2',false)
 RETURNING id INTO g;
 INSERT INTO public.meals(family_id,day_of_week,meal_name)
 VALUES(current_setting('test.fid')::uuid,0,'V2 COMPAT - meal')
 RETURNING id INTO m;
 UPDATE public.events SET title='V2 COMPAT - updated event' WHERE id=e;
 UPDATE public.chores SET completed=true WHERE id=c;
 UPDATE public.groceries SET completed=true WHERE id=g;
 UPDATE public.meals SET meal_name='V2 COMPAT - updated meal' WHERE id=m;
 SELECT count(*) INTO n FROM public.events WHERE id=e AND title='V2 COMPAT - updated event';
 IF n<>1 THEN RAISE EXCEPTION 'Parent event update failed';END IF;
 SELECT count(*) INTO n FROM public.chores WHERE id=c AND completed=true;
 IF n<>1 THEN RAISE EXCEPTION 'Parent chore update failed';END IF;
 SELECT count(*) INTO n FROM public.groceries WHERE id=g AND completed=true;
 IF n<>1 THEN RAISE EXCEPTION 'Parent grocery update failed';END IF;
 SELECT count(*) INTO n FROM public.meals WHERE id=m AND meal_name='V2 COMPAT - updated meal';
 IF n<>1 THEN RAISE EXCEPTION 'Parent meal update failed';END IF;
 PERFORM set_config('test.event',e::text,true);
 PERFORM set_config('test.chore',c::text,true);
 PERFORM set_config('test.grocery',g::text,true);
 PERFORM set_config('test.meal',m::text,true);
END;
$parent$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.tablet'),true);
DO $tablet$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.events WHERE id=current_setting('test.event')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'FAIL: tablet sees event';END IF;
 SELECT count(*) INTO n FROM public.chores WHERE id=current_setting('test.chore')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'FAIL: tablet sees legacy chores';END IF;
 SELECT count(*) INTO n FROM public.groceries WHERE id=current_setting('test.grocery')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'FAIL: tablet sees groceries';END IF;
 SELECT count(*) INTO n FROM public.meals WHERE id=current_setting('test.meal')::uuid;
 IF n<>0 THEN RAISE EXCEPTION 'FAIL: tablet sees meals';END IF;
 BEGIN
  INSERT INTO public.chores(family_id,title) VALUES(current_setting('test.fid')::uuid,'V2 ILLEGAL - chore');
  RAISE EXCEPTION 'FAIL: tablet inserted chore';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL:%' THEN RAISE;END IF;
  IF SQLSTATE<>'42501' THEN RAISE EXCEPTION 'Unexpected chore error: %',SQLERRM;END IF;
 END;
 BEGIN
  UPDATE public.groceries SET completed=false WHERE id=current_setting('test.grocery')::uuid;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>0 THEN RAISE EXCEPTION 'FAIL: tablet updated grocery';END IF;
 END;
END;
$tablet$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.parent'),true);
DO $delete$
DECLARE n int;
BEGIN
 DELETE FROM public.events WHERE id=current_setting('test.event')::uuid;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 THEN RAISE EXCEPTION 'Parent event delete failed'; END IF;
 DELETE FROM public.chores WHERE id=current_setting('test.chore')::uuid;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 THEN RAISE EXCEPTION 'Parent chore delete failed'; END IF;
 DELETE FROM public.groceries WHERE id=current_setting('test.grocery')::uuid;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 THEN RAISE EXCEPTION 'Parent grocery delete failed'; END IF;
 DELETE FROM public.meals WHERE id=current_setting('test.meal')::uuid;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 THEN RAISE EXCEPTION 'Parent meal delete failed'; END IF;
END;
$delete$;
SELECT 'PASS: v2.1 parent CRUD across calendar, chores, groceries and meals; tablet isolation' AS result;
ROLLBACK;