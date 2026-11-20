-- Family Hub v3: test immutable earned points after editing a chore.
-- Run only on v3 staging; all changes roll back.
BEGIN;
DO $setup$
DECLARE fid uuid; choreid uuid; parent_id uuid; childid uuid; balance bigint;
BEGIN
 SELECT id INTO STRICT fid FROM public.families WHERE name='Family Hub v3 - STAGING ONLY';
 SELECT id INTO STRICT childid FROM public.child_profiles WHERE family_id=fid AND name='Adalee (TEST)';
 SELECT id INTO STRICT parent_id FROM auth.users WHERE email='daniel+fhv3parent@gmail.com';
 SELECT id INTO STRICT choreid FROM public.chore_assignments
 WHERE family_id=fid AND child_id=childid AND title='Test- daily chore twice';
 SELECT COALESCE(SUM(points),0) INTO balance FROM public.point_transactions
 WHERE family_id=fid AND child_id=childid;
 IF balance<>20 THEN RAISE EXCEPTION 'Unexpected initial test balance: %',balance; END IF;
 PERFORM set_config('test.fid',fid::text,true);
 PERFORM set_config('test.chore',choreid::text,true);
 PERFORM set_config('test.child',childid::text,true);
 PERFORM set_config('request.jwt.claim.sub',parent_id::text,true);
END;
$setup$;
SET LOCAL ROLE authenticated;
UPDATE public.chore_assignments SET points=50,active=false
WHERE id=current_setting('test.chore')::uuid AND family_id=current_setting('test.fid')::uuid;
DO $check$
DECLARE awards bigint; snapshots int; balance bigint; completions int; p int; enabled boolean;
BEGIN
 SELECT COUNT(*),COALESCE(SUM(points_snapshot),0) INTO completions,snapshots
 FROM public.chore_completions
 WHERE assignment_id=current_setting('test.chore')::uuid AND status='approved';
 SELECT COALESCE(SUM(pt.points),0) INTO awards FROM public.point_transactions pt
 JOIN public.chore_completions cc ON cc.id=pt.chore_completion_id
 WHERE cc.assignment_id=current_setting('test.chore')::uuid;
 SELECT COALESCE(SUM(points),0) INTO balance FROM public.point_transactions
 WHERE child_id=current_setting('test.child')::uuid;
 SELECT points,active INTO p,enabled FROM public.chore_assignments
 WHERE id=current_setting('test.chore')::uuid;
 IF completions<>2 OR snapshots<>10 OR awards<>10 OR balance<>20 OR p<>50 OR enabled THEN
   RAISE EXCEPTION 'Historical points changed: completions %, snapshots %, awards %, balance %, new points %, active %',
     completions,snapshots,awards,balance,p,enabled;
 END IF;
END;
$check$;
SELECT 'PASS: updating chore points and disabling does not alter existing awards or balance' AS result;
ROLLBACK;