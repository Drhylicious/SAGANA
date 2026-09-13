CREATE OR REPLACE FUNCTION public.resolve_password_reset_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE password_reset_requests
  SET status = 'resolved', resolved_at = NOW(), resolved_by = auth.uid()
  WHERE id = p_request_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.resolve_password_reset_request(UUID) TO authenticated;

GRANT EXECUTE ON FUNCTION public.request_password_assistance(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.request_password_assistance(TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';