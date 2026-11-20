-- FAMILY HUB V3 STAGING SEED ONLY.
-- Do not execute on production. Sample records are non-sensitive fixtures.
BEGIN;
DO $$
DECLARE fid uuid; carson uuid; adalee uuid;
BEGIN
 SELECT id INTO fid FROM public.families WHERE name='Family Hub v3 - STAGING ONLY' LIMIT 1;
 IF fid IS NULL THEN
   INSERT INTO public.families(name) VALUES('Family Hub v3 - STAGING ONLY') RETURNING id INTO fid;
 END IF;

 INSERT INTO public.child_profiles(family_id,name)
 SELECT fid,'Carson (TEST)'
 WHERE NOT EXISTS (SELECT 1 FROM public.child_profiles WHERE family_id=fid AND name='Carson (TEST)');
 INSERT INTO public.child_profiles(family_id,name)
 SELECT fid,'Adalee (TEST)'
 WHERE NOT EXISTS (SELECT 1 FROM public.child_profiles WHERE family_id=fid AND name='Adalee (TEST)');

 SELECT id INTO carson FROM public.child_profiles WHERE family_id=fid AND name='Carson (TEST)';
 SELECT id INTO adalee FROM public.child_profiles WHERE family_id=fid AND name='Adalee (TEST)';

 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,times_per_day)
 SELECT fid,carson,'TEST - Make bed',10,'daily',1
 WHERE NOT EXISTS (SELECT 1 FROM public.chore_assignments WHERE family_id=fid AND child_id=carson AND title='TEST - Make bed');
 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,times_per_day)
 SELECT fid,adalee,'TEST - Make bed',10,'daily',1
 WHERE NOT EXISTS (SELECT 1 FROM public.chore_assignments WHERE family_id=fid AND child_id=adalee AND title='TEST - Make bed');
 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,day_of_week)
 SELECT fid,carson,'TEST - Tidy bedroom',20,'weekly',6
 WHERE NOT EXISTS (SELECT 1 FROM public.chore_assignments WHERE family_id=fid AND child_id=carson AND title='TEST - Tidy bedroom');
 INSERT INTO public.chore_assignments(family_id,child_id,title,points,frequency,day_of_week)
 SELECT fid,adalee,'TEST - Tidy bedroom',20,'weekly',6
 WHERE NOT EXISTS (SELECT 1 FROM public.chore_assignments WHERE family_id=fid AND child_id=adalee AND title='TEST - Tidy bedroom');

 INSERT INTO public.rewards(family_id,title,description,points_cost)
 SELECT fid,'TEST - Choose family movie','A parent approves before points are spent',30
 WHERE NOT EXISTS (SELECT 1 FROM public.rewards WHERE family_id=fid AND title='TEST - Choose family movie');
 INSERT INTO public.rewards(family_id,title,description,points_cost)
 SELECT fid,'TEST - Choose a snack','A parent approves the request',15
 WHERE NOT EXISTS (SELECT 1 FROM public.rewards WHERE family_id=fid AND title='TEST - Choose a snack');
END;
$$;
COMMIT;
SELECT f.name AS family_name,
  (SELECT count(*) FROM public.child_profiles WHERE family_id=f.id) AS test_children,
  (SELECT count(*) FROM public.chore_assignments WHERE family_id=f.id) AS test_assignments,
  (SELECT count(*) FROM public.rewards WHERE family_id=f.id) AS test_rewards,
  (SELECT count(*) FROM public.family_members WHERE family_id=f.id) AS login_accounts
FROM public.families f WHERE f.name='Family Hub v3 - STAGING ONLY';
