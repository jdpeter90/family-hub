
-- Fresh STAGING ONLY. Recreates just the tables v3 uses, not live data.
CREATE TABLE public.families (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL,
 created_at timestamptz DEFAULT now()
);
CREATE TABLE public.family_members (
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 role text NOT NULL DEFAULT 'member' CHECK(role IN ('admin','member')),
 PRIMARY KEY(family_id,user_id)
);
CREATE OR REPLACE FUNCTION public.is_family_member(target_family_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT EXISTS (SELECT 1 FROM public.family_members
 WHERE family_id=target_family_id AND user_id=(SELECT auth.uid())) $$;
CREATE OR REPLACE FUNCTION public.is_family_admin(target_family_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT EXISTS (SELECT 1 FROM public.family_members
 WHERE family_id=target_family_id AND user_id=(SELECT auth.uid()) AND role='admin') $$;
REVOKE ALL ON FUNCTION public.is_family_member(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.is_family_admin(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.is_family_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_family_admin(uuid) TO authenticated;

CREATE TABLE public.events(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 title text NOT NULL,description text,starts_at timestamptz NOT NULL,
 assigned_to text,color text,created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.chores(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 title text NOT NULL,assigned_to text,due_date date,completed boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.groceries(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 item_name text NOT NULL,completed boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.meals(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 day_of_week integer NOT NULL CHECK(day_of_week BETWEEN 0 AND 6),
 meal_name text NOT NULL, UNIQUE(family_id,day_of_week)
);
CREATE TABLE public.child_profiles(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 name text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(family_id,name),UNIQUE(id,family_id)
);
CREATE TABLE public.chore_assignments(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 child_id uuid NOT NULL,
 title text NOT NULL CHECK(length(trim(title))>0),
 points integer NOT NULL CHECK(points BETWEEN 0 AND 10000),
 frequency text NOT NULL CHECK(frequency IN('daily','weekly','once')),
 times_per_day integer NOT NULL DEFAULT 1 CHECK(times_per_day BETWEEN 1 AND 5),
 day_of_week integer CHECK(day_of_week BETWEEN 0 AND 6),
 due_date date,
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT chore_assignments_child_family_fk FOREIGN KEY(child_id,family_id)
 REFERENCES public.child_profiles(id,family_id) ON DELETE RESTRICT,
 CONSTRAINT chore_assignments_schedule_check CHECK(
  (frequency='daily' AND day_of_week IS NULL AND due_date IS NULL)
  OR(frequency='weekly' AND day_of_week IS NOT NULL AND due_date IS NULL AND times_per_day=1)
  OR(frequency='once' AND due_date IS NOT NULL AND day_of_week IS NULL AND times_per_day=1)),
 CONSTRAINT chore_assignments_identity_unique UNIQUE(id,family_id,child_id)
);
CREATE TABLE public.chore_completions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 assignment_id uuid NOT NULL REFERENCES public.chore_assignments(id) ON DELETE RESTRICT,
 occurrence_date date NOT NULL,
 occurrence_number integer NOT NULL DEFAULT 1 CHECK(occurrence_number BETWEEN 1 AND 5),
 status text NOT NULL DEFAULT 'todo' CHECK(status IN('todo','pending','approved','needs_work')),
 points_snapshot integer NOT NULL CHECK(points_snapshot BETWEEN 0 AND 10000),
 submitted_at timestamptz,reviewed_at timestamptz,
 reviewed_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 family_id uuid NOT NULL,
 child_id uuid NOT NULL,
 CONSTRAINT chore_completion_unique_occurrence UNIQUE(assignment_id,occurrence_date,occurrence_number),
 CONSTRAINT chore_completions_assignment_identity_fk FOREIGN KEY(assignment_id,family_id,child_id)
 REFERENCES public.chore_assignments(id,family_id,child_id) ON DELETE RESTRICT,
 CONSTRAINT chore_completions_identity_unique UNIQUE(id,family_id,child_id)
);
CREATE TABLE public.rewards(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 title text NOT NULL CHECK(length(trim(title))>0),
 description text,
 points_cost integer NOT NULL CHECK(points_cost BETWEEN 1 AND 100000),
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT rewards_id_family_unique UNIQUE(id,family_id)
);
CREATE TABLE public.reward_requests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 child_id uuid NOT NULL,
 reward_id uuid NOT NULL,
 reward_title_snapshot text NOT NULL CHECK(length(trim(reward_title_snapshot))>0),
 points_cost_snapshot integer NOT NULL CHECK(points_cost_snapshot BETWEEN 1 AND 100000),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','approved','declined')),
 requested_at timestamptz NOT NULL DEFAULT now(),
 reviewed_at timestamptz,reviewed_by uuid REFERENCES auth.users(id),
 CONSTRAINT reward_requests_child_family_fk FOREIGN KEY(child_id,family_id)
 REFERENCES public.child_profiles(id,family_id) ON DELETE RESTRICT,
 CONSTRAINT reward_requests_reward_family_fk FOREIGN KEY(reward_id,family_id)
 REFERENCES public.rewards(id,family_id) ON DELETE RESTRICT
);
CREATE TABLE public.point_transactions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
 child_id uuid NOT NULL,
 points integer NOT NULL CHECK(points BETWEEN -10000 AND 10000 AND points<>0),
 transaction_type text NOT NULL CHECK(transaction_type IN('chore_approved','reward_redeemed','parent_adjustment')),
 chore_completion_id uuid REFERENCES public.chore_completions(id) ON DELETE RESTRICT,
 reward_request_id uuid REFERENCES public.reward_requests(id) ON DELETE RESTRICT,
 description text NOT NULL CHECK(length(trim(description))>0),
 created_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT point_transactions_child_family_fk FOREIGN KEY(child_id,family_id)
 REFERENCES public.child_profiles(id,family_id) ON DELETE RESTRICT,
 CONSTRAINT point_transactions_completion_identity_fk FOREIGN KEY(chore_completion_id,family_id,child_id)
 REFERENCES public.chore_completions(id,family_id,child_id) ON DELETE RESTRICT,
 CONSTRAINT point_transactions_unique_chore UNIQUE(chore_completion_id),
 CONSTRAINT point_transactions_unique_reward_request UNIQUE(reward_request_id),
 CONSTRAINT point_transactions_chore_type_check CHECK (
 (transaction_type='chore_approved' AND chore_completion_id IS NOT NULL AND reward_request_id IS NULL AND points>0)
 OR(transaction_type='reward_redeemed' AND chore_completion_id IS NULL AND reward_request_id IS NOT NULL AND points<0)
 OR(transaction_type='parent_adjustment' AND chore_completion_id IS NULL AND reward_request_id IS NULL))
);
-- Existing v2.1 read-only family references. No legacy data in staging.
ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groceries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.child_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chore_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chore_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reward_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.point_transactions ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.families,public.family_members TO authenticated;
CREATE POLICY "Members can view their family" ON public.families FOR SELECT TO authenticated
 USING(public.is_family_member(id));
CREATE POLICY "Members can view family memberships" ON public.family_members FOR SELECT TO authenticated
 USING(public.is_family_member(family_id));
CREATE POLICY "Parents see children" ON public.child_profiles FOR SELECT TO authenticated
 USING(public.is_family_admin(family_id));
