-- Family Hub v3.0 – permission foundation. STAGED IN GITHUB ONLY.
-- Must be applied BEFORE v3-rpc.sql, in a backup-verified maintenance window.
-- Existing v2.1 client stays functional for the two admin users. The dedicated
-- tablet user gets read-only v3 catalog + only specifically granted RPC actions.
BEGIN;

ALTER TABLE public.family_members
  DROP CONSTRAINT family_members_role_check;
ALTER TABLE public.family_members
  ADD CONSTRAINT family_members_role_check
  CHECK (role IN ('admin', 'member', 'tablet'));

-- In v2.1 both parents are admins. Protect existing shared data from a tablet.
-- A tablet cannot read or edit calendars, meals, groceries or legacy chores.
-- Existing RLS policies are replaced; no changes are made to table data.
DROP POLICY IF EXISTS "Members can manage events" ON public.events;
DROP POLICY IF EXISTS "Members can manage chores" ON public.chores;
DROP POLICY IF EXISTS "Members can manage groceries" ON public.groceries;
DROP POLICY IF EXISTS "Members can manage meals" ON public.meals;
REVOKE ALL ON public.events, public.chores, public.groceries, public.meals FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.events, public.chores, public.groceries, public.meals TO authenticated;
CREATE POLICY "Admins manage calendar" ON public.events FOR ALL TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins manage legacy chores" ON public.chores FOR ALL TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins manage groceries" ON public.groceries FOR ALL TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));
CREATE POLICY "Admins manage meals" ON public.meals FOR ALL TO authenticated
  USING (public.is_family_admin(family_id))
  WITH CHECK (public.is_family_admin(family_id));

DROP POLICY IF EXISTS "Members can view family memberships" ON public.family_members;
CREATE POLICY "Only own membership or family admin" ON public.family_members
  FOR SELECT TO authenticated USING (
    user_id = (SELECT auth.uid()) OR public.is_family_admin(family_id)
  );

-- Child profiles may be read by parents and the shared tablet.
-- Existing admin policy remains, if present; it does not grant write access.
REVOKE ALL ON public.child_profiles FROM anon, authenticated;
GRANT SELECT ON public.child_profiles TO authenticated;
CREATE POLICY "Household reads child profiles" ON public.child_profiles
  FOR SELECT TO authenticated USING (public.is_family_member(family_id));

-- Read the v3 data only within the signed-in user's family.
-- All submitted work, reviews, requests and points are mutated through
-- server-side RPCs exclusively, never by direct table writes.
REVOKE ALL ON public.chore_assignments, public.chore_completions,
  public.point_transactions, public.rewards, public.reward_requests
  FROM anon, authenticated;
GRANT SELECT ON public.chore_assignments, public.chore_completions,
  public.point_transactions, public.rewards, public.reward_requests TO authenticated;
GRANT INSERT, UPDATE ON public.chore_assignments, public.rewards TO authenticated;

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

-- Match the points ledger range to the maximum permitted reward cost.
ALTER TABLE public.point_transactions
  DROP CONSTRAINT point_transactions_points_check;
ALTER TABLE public.point_transactions
  ADD CONSTRAINT point_transactions_points_check
  CHECK (points BETWEEN -100000 AND 100000 AND points <> 0);

-- A reward debit must refer to a request for the SAME child and family.
ALTER TABLE public.reward_requests
  ADD CONSTRAINT reward_requests_identity_unique UNIQUE (id, family_id, child_id);
ALTER TABLE public.point_transactions
  ADD CONSTRAINT point_transactions_reward_identity_fk
  FOREIGN KEY (reward_request_id, family_id, child_id)
  REFERENCES public.reward_requests(id, family_id, child_id)
  ON DELETE RESTRICT;

-- Prevent two outstanding identical rewards for the same child.
CREATE UNIQUE INDEX reward_requests_one_pending_per_child_reward
  ON public.reward_requests (child_id, reward_id)
  WHERE status = 'pending';

COMMIT;
