-- Family Hub v3 — EMERGENCY DISABLE / v2.1 RESTORE (NOT APPLIED)
-- Use ONLY if a production v3 rollout fails, after explicit owner approval.
-- This is a NON-DESTRUCTIVE data rollback: v3 rows/point history stay intact.
-- The companion GitHub release must also be reverted to main's prior index.html.
BEGIN;

DO $preflight$
BEGIN
  IF (SELECT COUNT(*) FROM public.family_members WHERE role='admin')<>2 THEN
    RAISE EXCEPTION 'Expected two parent admins; stop and investigate';
  END IF;
  IF (SELECT COUNT(*) FROM public.family_members WHERE role NOT IN ('admin','tablet'))<>0 THEN
    RAISE EXCEPTION 'Unexpected family member roles; rollback needs review';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies
    WHERE schemaname='public' AND tablename='events'
      AND policyname='Admins manage calendar'
  ) THEN
    RAISE EXCEPTION 'v3 policy is not installed; stop without changing anything';
  END IF;
END;
$preflight$;

-- First revoke the children's tablet FAMILY membership. Merely hiding a UI
-- does not revoke access tokens; RLS and RPCs check current membership.
DELETE FROM public.family_members WHERE role='tablet';

-- Re-enable legacy v2.1 household management after tablet isolation.
DROP POLICY IF EXISTS "Admins manage calendar" ON public.events;
DROP POLICY IF EXISTS "Admins manage legacy chores" ON public.chores;
DROP POLICY IF EXISTS "Admins manage groceries" ON public.groceries;
DROP POLICY IF EXISTS "Admins manage meals" ON public.meals;
CREATE POLICY "Members can manage events" ON public.events FOR ALL TO authenticated
 USING (public.is_family_member(family_id)) WITH CHECK (public.is_family_member(family_id));
CREATE POLICY "Members can manage chores" ON public.chores FOR ALL TO authenticated
 USING (public.is_family_member(family_id)) WITH CHECK (public.is_family_member(family_id));
CREATE POLICY "Members can manage groceries" ON public.groceries FOR ALL TO authenticated
 USING (public.is_family_member(family_id)) WITH CHECK (public.is_family_member(family_id));
CREATE POLICY "Members can manage meals" ON public.meals FOR ALL TO authenticated
 USING (public.is_family_member(family_id)) WITH CHECK (public.is_family_member(family_id));

DROP POLICY IF EXISTS "Only own membership or family admin" ON public.family_members;
CREATE POLICY "Members can view family memberships"
 ON public.family_members FOR SELECT TO authenticated
 USING (public.is_family_member(family_id));

DROP POLICY IF EXISTS "Household reads child profiles" ON public.child_profiles;

-- Hide new v3 tables and revoke v3 privileged API actions.
-- DO NOT delete them: their data may be needed for recovery/redeployment.
REVOKE ALL ON public.chore_assignments,public.chore_completions,
 public.point_transactions,public.rewards,public.reward_requests
 FROM anon,authenticated;
REVOKE ALL ON FUNCTION public.submit_chore(uuid,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.approve_chore(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.request_chore_revision(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.request_reward(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.approve_reward_request(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.decline_reward_request(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.adjust_child_points(uuid,integer,text) FROM PUBLIC,anon,authenticated;

-- Keep the v3 table structures, one-time reward column, schedule guard,
-- helper functions, and ledger history so data can be recovered later.
-- Do not relax any other RLS permissions or expose secret keys.
COMMIT;