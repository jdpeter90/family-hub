-- STAGING ONLY: make the v2.1 test tables match production's columns.
-- The actual production database already has these fields. Do not run this
-- migration there. No existing rows are modified.
BEGIN;
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS ends_at timestamptz;
ALTER TABLE public.events ALTER COLUMN created_at DROP NOT NULL;
ALTER TABLE public.chores ALTER COLUMN created_at DROP NOT NULL;
ALTER TABLE public.groceries ADD COLUMN IF NOT EXISTS quantity text;
ALTER TABLE public.groceries ALTER COLUMN created_at DROP NOT NULL;
ALTER TABLE public.meals ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();
COMMIT;