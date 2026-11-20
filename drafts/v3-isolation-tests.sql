-- Family Hub v3 - Cross-family / tablet isolation regression.
-- STAGING DATABASE ONLY. Entire test is rolled back.
BEGIN;

INSERT INTO auth.users(id,aud,role,email,created_at,updated_at) VALUES
 ('00000000-0000-4000-8000-0000000000b1','authenticated','authenticated','isolation-a@example.invalid',now(),now()),
 ('00000000-0000-4000-8000-0000000000b2','authenticated','authenticated','isolation-tablet@example.invalid',now(),now()),
 ('00000000-0000-4000-8000-0000000000b3','authenticated','authenticated','isolation-b@example.invalid',now(),now());

INSERT INTO public.families(id,name) VALUES
 ('00000000-0000-4000-8000-0000000000f1','A - Staging'),
 ('00000000-0000-4000-8000-0000000000f2','B - Staging');
INSERT INTO public.family_members(family_id,user_id,role) VALUES
 ('00000000-0000-4000-8000-0000000000f1','00000000-0000-4000-8000-0000000000b1','admin'),
 ('00000000-0000-4000-8000-0000000000f1','00000000-0000-4000-8000-0000000000b2','tablet'),
 ('00000000-0000-4000-8000-0000000000f2','00000000-0000-4000-8000-0000000000b3','admin');
INSERT INTO public.child_profiles(id,family_id,name) VALUES
 ('00000000-0000-4000-8000-0000000000c1','00000000-0000-4000-8000-0000000000f1','A Child'),
 ('00000000-0000-4000-8000-0000000000c2','00000000-0000-4000-8000-0000000000f2','B Child');
INSERT INTO public.events(family_id,title,starts_at) VALUES
 ('00000000-0000-4000-8000-0000000000f1','A private event',now()),
 ('00000000-0000-4000-8000-0000000000f2','B private event',now());
INSERT INTO public.rewards(id,family_id,title,points_cost) VALUES
 ('00000000-0000-4000-8000-0000000000e1','00000000-0000-4000-8000-0000000000f1','A reward',10),
 ('00000000-0000-4000-8000-0000000000e2','00000000-0000-4000-8000-0000000000f2','B reward',10);
INSERT INTO public.chore_assignments(id,family_id,child_id,title,points,frequency) VALUES
 ('00000000-0000-4000-8000-0000000000d1','00000000-0000-4000-8000-0000000000f1','00000000-0000-4000-8000-0000000000c1','A chore',10,'daily'),
 ('00000000-0000-4000-8000-0000000000d2','00000000-0000-4000-8000-0000000000f2','00000000-0000-4000-8000-0000000000c2','B chore',10,'daily');

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000b2',true);
SET LOCAL ROLE authenticated;

DO $$
DECLARE n integer; _id uuid;
BEGIN
 SELECT count(*) INTO n FROM public.events;
 IF n <> 0 THEN RAISE EXCEPTION 'Tablet could read private events'; END IF;

 SELECT count(*) INTO n FROM public.child_profiles;
 IF n <> 1 THEN RAISE EXCEPTION 'Tablet child-profile family isolation failed'; END IF;
 SELECT count(*) INTO n FROM public.rewards;
 IF n <> 1 THEN RAISE EXCEPTION 'Tablet reward family isolation failed'; END IF;
 SELECT count(*) INTO n FROM public.chore_assignments;
 IF n <> 1 THEN RAISE EXCEPTION 'Tablet chore family isolation failed'; END IF;

 BEGIN
  INSERT INTO public.events(family_id,title,starts_at)
  VALUES ('00000000-0000-4000-8000-0000000000f1','Unauthorized event',now());
  RAISE EXCEPTION 'FAIL: tablet can write events';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
  IF SQLSTATE <> '42501' THEN RAISE; END IF;
 END;

 BEGIN
  INSERT INTO public.rewards(family_id,title,points_cost)
  VALUES ('00000000-0000-4000-8000-0000000000f1','Unauthorized reward',1);
  RAISE EXCEPTION 'FAIL: tablet can create rewards';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
  IF SQLSTATE <> '42501' THEN RAISE; END IF;
 END;

 BEGIN
  _id := public.submit_chore('00000000-0000-4000-8000-0000000000d2'::uuid,1);
  RAISE EXCEPTION 'FAIL: tablet submitted another family chore';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
  IF SQLERRM <> 'Not authorized to submit chores' THEN RAISE; END IF;
 END;

 BEGIN
  _id := public.request_reward('00000000-0000-4000-8000-0000000000e2'::uuid,
    '00000000-0000-4000-8000-0000000000c2'::uuid);
  RAISE EXCEPTION 'FAIL: tablet requested another family reward';
 EXCEPTION WHEN OTHERS THEN
  IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
  IF SQLERRM <> 'Not authorized to request rewards' THEN RAISE; END IF;
 END;
END;
$$;

SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-0000000000b1',true);
DO $$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM public.events;
 IF n <> 1 THEN RAISE EXCEPTION 'Parent could read another family event or not own'; END IF;
 SELECT count(*) INTO n FROM public.rewards;
 IF n <> 1 THEN RAISE EXCEPTION 'Parent reward isolation failed'; END IF;
END;
$$;
SELECT 'PASS: tablet write protections, data visibility, and cross-family RPC isolation' AS result;
ROLLBACK;
