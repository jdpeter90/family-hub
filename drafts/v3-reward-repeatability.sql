-- Family Hub v3: parents can offer one-time or repeatable rewards.
-- Existing rewards remain repeatable (the original behaviour).
-- Apply AFTER v3-security-foundation.sql, v3-rpc.sql and
-- v3-integrity-hardening.sql. Staging verified before production use.
BEGIN;

ALTER TABLE public.rewards
  ADD COLUMN IF NOT EXISTS repeatable boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.request_reward(
  target_reward_id uuid, target_child_id uuid
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  reward_record public.rewards%ROWTYPE;
  new_request_id uuid;
BEGIN
  SELECT * INTO reward_record FROM public.rewards WHERE id = target_reward_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reward not found'; END IF;
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.family_members fm
    WHERE fm.user_id = auth.uid()
      AND fm.family_id = reward_record.family_id
      AND fm.role IN ('admin', 'tablet')
  ) THEN
    RAISE EXCEPTION 'Not authorized to request rewards';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.child_profiles cp
    WHERE cp.id = target_child_id AND cp.family_id = reward_record.family_id
  ) THEN
    RAISE EXCEPTION 'Child is not part of this family';
  END IF;
  IF NOT reward_record.active THEN
    RAISE EXCEPTION 'Reward is disabled';
  END IF;
  IF NOT reward_record.repeatable AND EXISTS (
    SELECT 1 FROM public.reward_requests
    WHERE reward_id = target_reward_id AND child_id = target_child_id
      AND status = 'approved'
  ) THEN
    RAISE EXCEPTION 'This one-time reward has already been redeemed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.reward_requests
    WHERE reward_id = target_reward_id AND child_id = target_child_id
      AND status = 'pending'
  ) THEN
    RAISE EXCEPTION 'A request for this reward is already pending';
  END IF;

  INSERT INTO public.reward_requests (
    family_id, child_id, reward_id,
    reward_title_snapshot, points_cost_snapshot, status
  )
  VALUES (
    reward_record.family_id, target_child_id, reward_record.id,
    reward_record.title, reward_record.points_cost, 'pending'
  )
  RETURNING id INTO new_request_id;
  RETURN new_request_id;
END;
$$;


CREATE OR REPLACE FUNCTION public.approve_reward_request(target_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  family_to_check uuid;
  child_to_lock uuid;
  r record;
  available_points bigint;
  can_repeat boolean;
BEGIN
  SELECT family_id, child_id INTO family_to_check, child_to_lock
  FROM public.reward_requests WHERE id = target_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reward request not found'; END IF;
  IF auth.uid() IS NULL OR NOT public.is_family_admin(family_to_check) THEN
    RAISE EXCEPTION 'Not authorized to approve rewards';
  END IF;

  -- All debits/adjustments lock the child before reading its balance.
  -- This prevents two simultaneous approvals from overspending points.
  PERFORM 1 FROM public.child_profiles
  WHERE id = child_to_lock AND family_id = family_to_check FOR UPDATE;

  SELECT * INTO r FROM public.reward_requests
  WHERE id = target_request_id FOR UPDATE;
  IF r.status <> 'pending' THEN
    RAISE EXCEPTION 'Reward request was already reviewed';
  END IF;

  -- This lock serializes changing repeatability against reward approval.
  SELECT rw.repeatable INTO can_repeat
  FROM public.rewards rw WHERE rw.id = r.reward_id FOR SHARE;
  IF NOT can_repeat AND EXISTS (
    SELECT 1 FROM public.reward_requests prev
    WHERE prev.reward_id = r.reward_id
      AND prev.child_id = r.child_id
      AND prev.id <> r.id
      AND prev.status = 'approved'
  ) THEN
    RAISE EXCEPTION 'This one-time reward has already been redeemed';
  END IF;

  SELECT COALESCE(SUM(points), 0) INTO available_points
  FROM public.point_transactions
  WHERE family_id = r.family_id AND child_id = r.child_id;
  IF available_points < r.points_cost_snapshot THEN
    RAISE EXCEPTION 'Insufficient points to redeem this reward';
  END IF;

  UPDATE public.reward_requests
  SET status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = r.id;
  INSERT INTO public.point_transactions (
    family_id, child_id, points, transaction_type,
    reward_request_id, description, created_by
  )
  VALUES (
    r.family_id, r.child_id, -r.points_cost_snapshot, 'reward_redeemed',
    r.id, 'Redeemed reward: ' || r.reward_title_snapshot, auth.uid()
  );
END;
$$;


-- Replaced RPC functions retain exactly their existing EXECUTE grants.
REVOKE ALL ON FUNCTION public.request_reward(uuid,uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.approve_reward_request(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.request_reward(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_reward_request(uuid) TO authenticated;
COMMIT;
