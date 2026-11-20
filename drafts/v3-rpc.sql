-- Family Hub v3.0 – server-side chore/points/reward workflows.
-- STAGED IN GITHUB ONLY. Apply AFTER v3-security-foundation.sql.
-- All SECURITY DEFINER functions check membership/role based on auth.uid().
-- No service_role credential is required or shipped to clients.
BEGIN;

CREATE OR REPLACE FUNCTION public.submit_chore(
  target_assignment_id uuid,
  occurrence_no integer DEFAULT 1
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  assignment_record public.chore_assignments%ROWTYPE;
  completion_record public.chore_completions%ROWTYPE;
  local_today date := (now() AT TIME ZONE 'America/Chicago')::date;
  target_day date;
  submitted_id uuid;
BEGIN
  SELECT * INTO assignment_record
  FROM public.chore_assignments WHERE id = target_assignment_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'Chore not found'; END IF;
  IF auth.uid() IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.family_members fm
    WHERE fm.user_id = auth.uid()
      AND fm.family_id = assignment_record.family_id
      AND fm.role IN ('admin', 'tablet')
  ) THEN
    RAISE EXCEPTION 'Not authorized to submit chores';
  END IF;
  IF NOT assignment_record.active THEN
    RAISE EXCEPTION 'This chore is disabled';
  END IF;

  IF occurrence_no IS NULL OR occurrence_no < 1 OR occurrence_no > assignment_record.times_per_day THEN
    RAISE EXCEPTION 'Invalid chore occurrence';
  END IF;

  IF assignment_record.frequency = 'weekly' THEN
    IF EXTRACT(DOW FROM local_today)::integer <> assignment_record.day_of_week THEN
      RAISE EXCEPTION 'Chore is not scheduled for today';
    END IF;
    target_day := local_today;
  ELSIF assignment_record.frequency = 'once' THEN
    IF assignment_record.due_date > local_today THEN
      RAISE EXCEPTION 'Chore is not due yet';
    END IF;
    target_day := assignment_record.due_date;
  ELSE
    target_day := local_today;
  END IF;

  SELECT * INTO completion_record
  FROM public.chore_completions
  WHERE assignment_id = target_assignment_id
    AND occurrence_date = target_day
    AND occurrence_number = occurrence_no
  FOR UPDATE;

  IF FOUND THEN
    IF completion_record.status NOT IN ('needs_work', 'todo') THEN
      RAISE EXCEPTION 'Chore already submitted or approved';
    END IF;
    UPDATE public.chore_completions
    SET status = 'pending',
        submitted_at = now(),
        points_snapshot = assignment_record.points,
        reviewed_at = NULL,
        reviewed_by = NULL
    WHERE id = completion_record.id
    RETURNING id INTO submitted_id;
  ELSE
    INSERT INTO public.chore_completions (
      assignment_id, family_id, child_id, occurrence_date,
      occurrence_number, status, points_snapshot, submitted_at
    )
    VALUES (
      assignment_record.id, assignment_record.family_id,
      assignment_record.child_id, target_day,
      occurrence_no, 'pending', assignment_record.points, now()
    )
    RETURNING id INTO submitted_id;
  END IF;
  RETURN submitted_id;
END;
$$;

-- Override the tested prototype to recheck authorization before row locking,
-- and award points only once for an actually submitted pending chore.
CREATE OR REPLACE FUNCTION public.approve_chore(target_completion_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  family_to_check uuid;
  c record;
BEGIN
  SELECT family_id INTO family_to_check
  FROM public.chore_completions WHERE id = target_completion_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chore completion not found'; END IF;
  IF auth.uid() IS NULL OR NOT public.is_family_admin(family_to_check) THEN
    RAISE EXCEPTION 'Not authorized to approve chores';
  END IF;

  SELECT cc.id, cc.family_id, cc.child_id, cc.status,
         cc.points_snapshot, cc.submitted_at, ca.title
  INTO c
  FROM public.chore_completions cc
  JOIN public.chore_assignments ca ON ca.id = cc.assignment_id
  WHERE cc.id = target_completion_id
  FOR UPDATE OF cc;

  IF c.status <> 'pending' OR c.submitted_at IS NULL THEN
    RAISE EXCEPTION 'Chore is not a submitted pending completion';
  END IF;

  UPDATE public.chore_completions
  SET status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = c.id;

  IF c.points_snapshot > 0 THEN
    INSERT INTO public.point_transactions (
      family_id, child_id, points, transaction_type,
      chore_completion_id, description, created_by
    )
    VALUES (
      c.family_id, c.child_id, c.points_snapshot, 'chore_approved',
      c.id, 'Approved chore: ' || c.title, auth.uid()
    );
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_chore_revision(target_completion_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  family_to_check uuid;
  completion_status text;
BEGIN
  SELECT family_id INTO family_to_check FROM public.chore_completions
  WHERE id = target_completion_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Chore completion not found'; END IF;
  IF auth.uid() IS NULL OR NOT public.is_family_admin(family_to_check) THEN
    RAISE EXCEPTION 'Not authorized to review chores';
  END IF;
  SELECT status INTO completion_status FROM public.chore_completions
  WHERE id = target_completion_id FOR UPDATE;
  IF completion_status <> 'pending' THEN
    RAISE EXCEPTION 'Only pending chores can be sent back';
  END IF;
  UPDATE public.chore_completions
  SET status = 'needs_work', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = target_completion_id;
END;
$$;

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

CREATE OR REPLACE FUNCTION public.decline_reward_request(target_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  family_to_check uuid;
  request_status text;
BEGIN
  SELECT family_id INTO family_to_check FROM public.reward_requests
  WHERE id = target_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Reward request not found'; END IF;
  IF auth.uid() IS NULL OR NOT public.is_family_admin(family_to_check) THEN
    RAISE EXCEPTION 'Not authorized to decline rewards';
  END IF;
  SELECT status INTO request_status FROM public.reward_requests
  WHERE id = target_request_id FOR UPDATE;
  IF request_status <> 'pending' THEN
    RAISE EXCEPTION 'Reward request was already reviewed';
  END IF;
  UPDATE public.reward_requests
  SET status = 'declined', reviewed_at = now(), reviewed_by = auth.uid()
  WHERE id = target_request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.adjust_child_points(
  target_child_id uuid, delta_points integer, reason text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  family_to_check uuid;
  available_points bigint;
BEGIN
  SELECT family_id INTO family_to_check FROM public.child_profiles
  WHERE id = target_child_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Child not found'; END IF;
  IF auth.uid() IS NULL OR NOT public.is_family_admin(family_to_check) THEN
    RAISE EXCEPTION 'Not authorized to adjust points';
  END IF;
  IF delta_points IS NULL OR delta_points = 0 OR abs(delta_points::bigint) > 100000 THEN
    RAISE EXCEPTION 'Point adjustment must be between -100000 and 100000, excluding zero';
  END IF;
  IF reason IS NULL OR length(trim(reason)) < 3 OR length(reason) > 240 THEN
    RAISE EXCEPTION 'Provide a reason of 3 to 240 characters';
  END IF;

  PERFORM 1 FROM public.child_profiles
  WHERE id = target_child_id AND family_id = family_to_check FOR UPDATE;
  SELECT COALESCE(SUM(points), 0) INTO available_points
  FROM public.point_transactions
  WHERE family_id = family_to_check AND child_id = target_child_id;
  IF available_points + delta_points < 0 THEN
    RAISE EXCEPTION 'Point adjustment would create a negative balance';
  END IF;

  INSERT INTO public.point_transactions (
    family_id, child_id, points, transaction_type, description, created_by
  )
  VALUES (
    family_to_check, target_child_id, delta_points,
    'parent_adjustment', trim(reason), auth.uid()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.submit_chore(uuid,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_chore(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.request_chore_revision(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.request_reward(uuid,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.approve_reward_request(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.decline_reward_request(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.adjust_child_points(uuid,integer,text) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.submit_chore(uuid,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_chore(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_chore_revision(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.request_reward(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_reward_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decline_reward_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adjust_child_points(uuid,integer,text) TO authenticated;

COMMIT;
