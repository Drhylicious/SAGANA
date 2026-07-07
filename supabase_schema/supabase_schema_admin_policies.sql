DROP POLICY IF EXISTS "user_roles: admin reads all" ON public.user_roles;
DROP POLICY IF EXISTS "user_roles: admin updates status" ON public.user_roles;

CREATE POLICY "user_roles: admin reads all"
  ON public.user_roles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );

CREATE POLICY "user_roles: admin updates status"
  ON public.user_roles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.admin_profiles ap
      WHERE ap.user_id = auth.uid()
    )
  );