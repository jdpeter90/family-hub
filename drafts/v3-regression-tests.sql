-- Family Hub v3 staging-only regression tests
-- REQUIREMENTS: run on an ISOLATED TEST COPY after staging bootstrap and both v3 SQL files.
-- DO NOT run against production: temporarily modifies synthetic staging memberships.
-- The synthetic users and all fixture data are rolled back at the end.
BEGIN;

-- Synthetic fixtures created ONLY inside this transaction. These do not
-- create usable email-password logins and are removed by ROLLBACK.
INSERT INTO auth.users(id,aud,role,email,created_at,updated_at) VALUES
 ('00000000-0000-4000-8000-0000000000a1','authenticated','authenticated','stage-parent-a@example.invalid',now(),now()),
 ('00000000-0000-4000-8000-0000000000a2','authenticated','authenticated','stage-parent-b@example.invalid',now(),now());

INSERT INTO public.families(id,name)
VALUES ('00000000-0000-4000-8000-0000000000f1','Staging Family');
INSERT INTO public.family_members(family_id,user_id,role) VALUES
 ('00000000-0000-4000-8000-0000000000f1','00000000-0000-4000-8000-0000000000a1','admin'),
 ('00000000-0000-4000-8000-0000000000f1','00000000-0000-4000-8000-0000000000a2','admin');
INSERT INTO public.child_profiles(id,family_id,name)
VALUES ('00000000-0000-4000-8000-0000000000c1','00000000-0000-4000-8000-0000000000f1','Test Child');
INSERT INTO public.events(family_id,title,starts_at)
VALUES ('00000000-0000-4000-8000-0000000000f1','PRIVATE EVENT TEST',now());

DO $$
DECLARE
  fid uuid;
  parent_id uuid;
  tablet_id uuid;
  child_id uuid;
BEGIN
  SELECT family_id INTO fid FROM public.family_members GROUP BY family_id
  HAVING count(*) FILTER (WHERE role = 'admin') >= 2 LIMIT 1;
  IF fid IS NULL THEN RAISE EXCEPTION 'Needs a family with two test admin accounts'; END IF;
  SELECT user_id INTO parent_id FROM public.family_members
  WHERE family_id=fid AND role='admin' ORDER BY user_id LIMIT 1;
  SELECT user_id INTO tablet_id FROM public.family_members
  WHERE family_id=fid AND role='admin' AND user_id<>parent_id LIMIT 1;
  SELECT id INTO child_id FROM public.child_profiles WHERE family_id=fid LIMIT 1;
  IF child_id IS NULL THEN RAISE EXCEPTION 'Child fixture missing'; END IF;
  PERFORM set_config('test.fid',fid::text,true);
  PERFORM set_config('test.parent',parent_id::text,true);
  PERFORM set_config('test.tablet',tablet_id::text,true);
  PERFORM set_config('test.child',child_id::text,true);
  PERFORM set_config('request.jwt.claim.sub',parent_id::text,true);
END;
$$;

SET LOCAL ROLE authenticated;
DO $$
DECLARE cid uuid; rid uuid; BEGIN
  INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,times_per_day)
  VALUES(current_setting('test.fid')::uuid,current_setting('test.child')::uuid,
    'V3 TEST - daily chore',10,'daily',1) RETURNING id INTO cid;
  INSERT INTO public.rewards(family_id,title,points_cost)
  VALUES(current_setting('test.fid')::uuid,'V3 TEST - reward',4) RETURNING id INTO rid;
  PERFORM set_config('test.chore',cid::text,true);
  PERFORM set_config('test.reward',rid::text,true);
  ASSERT public.is_family_admin(current_setting('test.fid')::uuid);
END;
$$;

RESET ROLE;
UPDATE public.family_members SET role='tablet'
WHERE family_id=current_setting('test.fid')::uuid
 AND user_id=current_setting('test.tablet')::uuid;
SELECT set_config('request.jwt.claim.sub',current_setting('test.tablet'),true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE completion_id uuid; request_id uuid; BEGIN
  ASSERT NOT public.is_family_admin(current_setting('test.fid')::uuid);
  ASSERT NOT EXISTS (SELECT 1 FROM public.events
                     WHERE family_id=current_setting('test.fid')::uuid),
    'Tablet could read private calendar';

  -- A tablet must not create catalog records or approve its own work.
  BEGIN
    INSERT INTO public.rewards(family_id,title,points_cost)
    VALUES(current_setting('test.fid')::uuid,'ILLEGAL',1);
    RAISE EXCEPTION 'TEST FAILURE: tablet inserted reward';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE; END IF;
  END;

  completion_id := public.submit_chore(current_setting('test.chore')::uuid,1);
  PERFORM set_config('test.completion',completion_id::text,true);
  BEGIN
    PERFORM public.approve_chore(completion_id);
    RAISE EXCEPTION 'TEST FAILURE: tablet approved chore';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE; END IF;
  END;

  request_id := public.request_reward(current_setting('test.reward')::uuid,
                                      current_setting('test.child')::uuid);
  PERFORM set_config('test.request',request_id::text,true);
  BEGIN
    PERFORM public.approve_reward_request(request_id);
    RAISE EXCEPTION 'TEST FAILURE: tablet approved reward';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE; END IF;
  END;
END;
$$;

SELECT set_config('request.jwt.claim.sub',current_setting('test.parent'),true);
DO $$
DECLARE points_balance bigint; BEGIN
  ASSERT public.is_family_admin(current_setting('test.fid')::uuid);
  PERFORM public.approve_chore(current_setting('test.completion')::uuid);
  SELECT COALESCE(SUM(points),0) INTO points_balance
  FROM public.point_transactions WHERE child_id=current_setting('test.child')::uuid;
  IF points_balance<>10 THEN RAISE EXCEPTION 'Expected +10 after chore, got %',points_balance; END IF;

  BEGIN
    PERFORM public.approve_chore(current_setting('test.completion')::uuid);
    RAISE EXCEPTION 'TEST FAILURE: duplicate chore approved';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE; END IF;
  END;

  PERFORM public.approve_reward_request(current_setting('test.request')::uuid);
  SELECT COALESCE(SUM(points),0) INTO points_balance
  FROM public.point_transactions WHERE child_id=current_setting('test.child')::uuid;
  IF points_balance<>6 THEN RAISE EXCEPTION 'Expected 6 points after reward, got %',points_balance; END IF;

  BEGIN
    PERFORM public.approve_reward_request(current_setting('test.request')::uuid);
    RAISE EXCEPTION 'TEST FAILURE: duplicate reward approved';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE; END IF;
  END;

  PERFORM public.adjust_child_points(current_setting('test.child')::uuid,4,'Staging test bonus');
  SELECT COALESCE(SUM(points),0) INTO points_balance
  FROM public.point_transactions WHERE child_id=current_setting('test.child')::uuid;
  IF points_balance<>10 THEN RAISE EXCEPTION 'Expected 10 points after bonus, got %',points_balance; END IF;

  BEGIN
    PERFORM public.adjust_child_points(current_setting('test.child')::uuid,-100,'Staging overdraft test');
    RAISE EXCEPTION 'TEST FAILURE: negative balance allowed';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'TEST FAILURE:%' THEN RAISE; END IF;
  END;
END;
$$;

SELECT 'PASS: parent/tablet auth, chore approval, reward redemption, duplicate protection, point arithmetic' AS result;
ROLLBACK;
