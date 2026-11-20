-- Family Hub v3.2 (2026-11-20)
-- Grant tablet accounts INSERT-only access to grocery lists within their own family.
-- Existing SELECT policy permits viewing; existing parent admin ALL policy remains unchanged.
-- Do not grant tablet UPDATE or DELETE.
CREATE POLICY "Tablet add family groceries"
ON public.groceries
FOR INSERT TO authenticated
WITH CHECK (
  completed = false
  AND item_name = btrim(item_name)
  AND length(item_name) BETWEEN 1 AND 160
  AND (quantity IS NULL OR length(quantity) <= 80)
  AND EXISTS (
    SELECT 1 FROM public.family_members fm
    WHERE fm.family_id = groceries.family_id
      AND fm.user_id = (SELECT auth.uid())
      AND fm.role = 'tablet'
  )
);
