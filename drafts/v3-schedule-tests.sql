-- Staging-only scheduling regression test (rolled back).
-- Tested on Family Hub v3 Staging 2026-11-20.
BEGIN;
DO $fixtures$
DECLARE fid uuid; cid uuid; p uuid; d uuid; today date; dow int; task_id uuid;
BEGIN
 SELECT id INTO STRICT fid FROM public.families WHERE name='Family Hub v3 - STAGING ONLY';
 SELECT id INTO STRICT cid FROM public.child_profiles WHERE family_id=fid AND name='Carson (TEST)';
 SELECT id INTO STRICT p FROM auth.users WHERE email='daniel+fhv3parent@gmail.com';
 SELECT id INTO STRICT d FROM auth.users WHERE email='daniel+fhv3tablet@gmail.com';
 today:=(now() AT TIME ZONE 'America/Chicago')::date;
 dow:=EXTRACT(DOW FROM today)::int;
 PERFORM set_config('test.family',fid::text,true);
 PERFORM set_config('test.child',cid::text,true);
 PERFORM set_config('test.parent',p::text,true);
 PERFORM set_config('test.tablet',d::text,true);
 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,times_per_day)
 VALUES(fid,cid,'TEMP - three times daily',2,'daily',3) RETURNING id INTO task_id;
 PERFORM set_config('test.daily',task_id::text,true);
 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,day_of_week)
 VALUES(fid,cid,'TEMP - weekly today',4,'weekly',dow) RETURNING id INTO task_id;
 PERFORM set_config('test.weekly_today',task_id::text,true);
 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,day_of_week)
 VALUES(fid,cid,'TEMP - weekly tomorrow',4,'weekly',(dow+1)%7) RETURNING id INTO task_id;
 PERFORM set_config('test.weekly_tomorrow',task_id::text,true);
 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,due_date)
 VALUES(fid,cid,'TEMP - future one-off',8,'once',today+1) RETURNING id INTO task_id;
 PERFORM set_config('test.future_once',task_id::text,true);
END;
$fixtures$;
SELECT set_config('request.jwt.claim.sub',current_setting('test.tablet'),true);
SET LOCAL ROLE authenticated;
DO $schedule$
DECLARE i int; ids uuid[]:=ARRAY[]::uuid[]; id1 uuid; total int; z int;
BEGIN
 FOR i IN 1..3 LOOP
  ids:=array_append(ids,public.submit_chore(current_setting('test.daily')::uuid,i));
 END LOOP;
 IF array_length(ids,1)<>3 OR ids[1]=ids[2] OR ids[2]=ids[3] THEN
  RAISE EXCEPTION 'FAIL: daily occurrences not unique';
 END IF;
 BEGIN
   PERFORM public.submit_chore(current_setting('test.daily')::uuid,4);
   RAISE EXCEPTION 'FAIL: fourth occurrence allowed';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
   IF SQLERRM<>'Invalid chore occurrence' THEN RAISE EXCEPTION 'Unexpected daily limit error: %', SQLERRM; END IF;
 END;
 BEGIN
   PERFORM public.submit_chore(current_setting('test.daily')::uuid,1);
   RAISE EXCEPTION 'FAIL: duplicate daily occurrence allowed';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
   IF SQLERRM<>'Chore already submitted or approved' THEN RAISE EXCEPTION 'Unexpected duplicate error: %', SQLERRM; END IF;
 END;
 id1:=public.submit_chore(current_setting('test.weekly_today')::uuid,1);
 IF id1 IS NULL THEN RAISE EXCEPTION 'FAIL: weekly current day failed'; END IF;
 BEGIN
   PERFORM public.submit_chore(current_setting('test.weekly_tomorrow')::uuid,1);
   RAISE EXCEPTION 'FAIL: future weekday allowed';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
   IF SQLERRM<>'Chore is not scheduled for today' THEN RAISE EXCEPTION 'Unexpected weekly error: %',SQLERRM; END IF;
 END;
 BEGIN
   PERFORM public.submit_chore(current_setting('test.future_once')::uuid,1);
   RAISE EXCEPTION 'FAIL: future one-off allowed';
 EXCEPTION WHEN OTHERS THEN
   IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
   IF SQLERRM<>'Chore is not due yet' THEN RAISE EXCEPTION 'Unexpected future error: %',SQLERRM; END IF;
 END;
 SELECT COUNT(*) INTO total FROM public.chore_completions WHERE id=ANY(ids);
 IF total<>3 THEN RAISE EXCEPTION 'FAIL: expected 3 daily submissions, got %',total; END IF;
 SELECT COALESCE(SUM(pt.points),0) INTO z FROM public.point_transactions pt
 WHERE pt.chore_completion_id=ANY(ids);
 IF z<>0 THEN RAISE EXCEPTION 'FAIL: points were awarded before approval'; END IF;
END;
$schedule$;
SELECT 'PASS: daily 3x with limit; weekly correct/wrong day; once in future; no points before approval' AS result;
ROLLBACK;