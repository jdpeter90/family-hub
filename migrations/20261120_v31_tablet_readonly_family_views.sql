-- Family Hub v3.1 (2026-11-20)
-- A tablet-only family member may SELECT the family calendar, dinner plan
-- and grocery list. Existing admin-only ALL policies still control writes.
-- The tablet membership is checked against the authenticated user ID.
-- Important: this policy intentionally exposes ALL family event details to
-- the family tablet login, by the family's explicit choice.

CREATE POLICY "Tablet read family calendar"
ON public.events FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.family_members AS fm
  WHERE fm.family_id = events.family_id
    AND fm.user_id = (SELECT auth.uid())
    AND fm.role = 'tablet'
));

CREATE POLICY "Tablet read family meals"
ON public.meals FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.family_members AS fm
  WHERE fm.family_id = meals.family_id
    AND fm.user_id = (SELECT auth.uid())
    AND fm.role = 'tablet'
));

CREATE POLICY "Tablet read family groceries"
ON public.groceries FOR SELECT TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.family_members AS fm
  WHERE fm.family_id = groceries.family_id
    AND fm.user_id = (SELECT auth.uid())
    AND fm.role = 'tablet'
));
