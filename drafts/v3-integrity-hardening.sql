-- Family Hub v3: prevent duplicate submissions caused by changing schedules
-- after a chore occurrence has been created.
-- Run AFTER v3-security-foundation.sql and v3-rpc.sql.
-- Safe for existing completed/pending chore rows: this alters no historical data.
BEGIN;

CREATE OR REPLACE FUNCTION public.enforce_chore_history_schedule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
  -- A chore may be edited freely before it has any occurrence history.
  -- Once history exists, editing frequency/day/due date/times per day can
  -- manufacture another distinct occurrence and allow a second award.
  IF ROW(NEW.family_id, NEW.child_id, NEW.frequency, NEW.times_per_day,
         NEW.day_of_week, NEW.due_date)
     IS DISTINCT FROM
     ROW(OLD.family_id, OLD.child_id, OLD.frequency, OLD.times_per_day,
         OLD.day_of_week, OLD.due_date)
     AND EXISTS (
       SELECT 1
       FROM public.chore_completions c
       WHERE c.assignment_id = OLD.id
     ) THEN
    RAISE EXCEPTION 'This chore has submission history. Create a new chore to change its schedule or child.';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS chore_history_schedule_guard ON public.chore_assignments;
CREATE TRIGGER chore_history_schedule_guard
BEFORE UPDATE ON public.chore_assignments
FOR EACH ROW
EXECUTE FUNCTION public.enforce_chore_history_schedule();

-- The trigger is invoked automatically by PostgreSQL; it is not an RPC.
REVOKE ALL ON FUNCTION public.enforce_chore_history_schedule()
FROM PUBLIC, anon, authenticated;

COMMIT;
