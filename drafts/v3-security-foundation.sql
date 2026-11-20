-- Family Hub v3: security foundation (DRAFT, NOT APPLIED)
-- Reviewed against the v2.1 live schema on 2026-11-20.
-- Apply only after an isolated staging test and explicit production approval.
-- Existing parents must retain role = 'admin' before applying.
BEGIN;

-- A dedicated tablet login must not inherit the permissions of a parent.
ALTER TABLE public.family_members
  DROP CONSTRAINT family_members_role_check;
ALTER TABLE public.family_members
  ADD CONSTRAINT family_members_role_check
  CHECK (role IN ('admin', 'member', 'tablet'));

-- Retain read access to the existing dashboard for authenticated household
-- members, but restrict writes to actual admins. Never rely on UI-only controls.
REVOKE ALL ON public.events, public.chores, public.groceries, public.meals
  FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.events, public.chores, public.groceries, public.meals
  TO authenticated;

DROP POLICY IF EXISTS "Members can manage events" ON public.events;
CREATE POLICY "Household reads events"
  ON public.events FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));
CREATE POLICY "Admins add events"
  ON public.events FOR INSERT TO authenticated
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins change events"
  ON public.events FOR UPDATE TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins delete events"
  ON public.events FOR DELETE TO authenticated
  USING (public.is_family_admin(family_id));

DROP POLICY IF EXISTS "Members can manage chores" ON public.chores;
CREATE POLICY "Household reads legacy chores"
  ON public.chores FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));
CREATE POLICY "Admins add legacy chores"
  ON public.chores FOR INSERT TO authenticated
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins change legacy chores"
  ON public.chores FOR UPDATE TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins delete legacy chores"
  ON public.chores FOR DELETE TO authenticated
  USING (public.is_family_admin(family_id));

DROP POLICY IF EXISTS "Members can manage groceries" ON public.groceries;
CREATE POLICY "Household reads groceries"
  ON public.groceries FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));
CREATE POLICY "Admins add groceries"
  ON public.groceries FOR INSERT TO authenticated
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins change groceries"
  ON public.groceries FOR UPDATE TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins delete groceries"
  ON public.groceries FOR DELETE TO authenticated
  USING (public.is_family_admin(family_id));

DROP POLICY IF EXISTS "Members can manage meals" ON public.meals;
CREATE POLICY "Household reads meals"
  ON public.meals FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));
CREATE POLICY "Admins add meals"
  ON public.meals FOR INSERT TO authenticated
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins change meals"
  ON public.meals FOR UPDATE TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins delete meals"
  ON public.meals FOR DELETE TO authenticated
  USING (public.is_family_admin(family_id));

-- The existing admin-only profile SELECT policy can remain: permissive RLS
-- policies combine with OR. Tablet and parents both need profile names.
REVOKE ALL ON public.child_profiles FROM anon, authenticated;
GRANT SELECT ON public.child_profiles TO authenticated;
CREATE POLICY "Household reads child profiles"
  ON public.child_profiles FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));

-- Chore/reward tables are read-only through the Data API, except for the
-- admin-managed assignment and reward catalogs. Submissions, decisions and
-- the points ledger will be changed only through separately reviewed RPCs.
REVOKE ALL ON public.chore_assignments, public.chore_completions,
  public.point_transactions, public.rewards, public.reward_requests
  FROM anon, authenticated;
GRANT SELECT ON public.chore_assignments, public.chore_completions,
  public.point_transactions, public.rewards, public.reward_requests
  TO authenticated;
GRANT INSERT, UPDATE ON public.chore_assignments, public.rewards
  TO authenticated;

CREATE POLICY "Household reads chore assignments"
  ON public.chore_assignments FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));
CREATE POLICY "Admins create chore assignments"
  ON public.chore_assignments FOR INSERT TO authenticated
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins update chore assignments"
  ON public.chore_assignments FOR UPDATE TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));

CREATE POLICY "Household reads chore completions"
  ON public.chore_completions FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));
CREATE POLICY "Household reads point transactions"
  ON public.point_transactions FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));

CREATE POLICY "Household reads rewards"
  ON public.rewards FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));
CREATE POLICY "Admins create rewards"
  ON public.rewards FOR INSERT TO authenticated
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins update rewards"
  ON public.rewards FOR UPDATE TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));

CREATE POLICY "Household reads reward requests"
  ON public.reward_requests FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));

-- A reward can cost 100,000 points, so the ledger must support the same range.
ALTER TABLE public.point_transactions
  DROP CONSTRAINT point_transactions_points_check;
ALTER TABLE public.point_transactions
  ADD CONSTRAINT point_transactions_points_check
  CHECK (points BETWEEN -100000 AND 100000 AND points <> 0);

-- Ledger reward IDs must reference the same family and child; a bare UUID
-- foreign key does not guarantee this.
ALTER TABLE public.reward_requests
  ADD CONSTRAINT reward_requests_identity_unique UNIQUE (id, family_id, child_id);
ALTER TABLE public.point_transactions
  ADD CONSTRAINT point_transactions_reward_identity_fk
  FOREIGN KEY (reward_request_id, family_id, child_id)
  REFERENCES public.reward_requests(id, family_id, child_id)
  ON DELETE RESTRICT;

COMMIT;
