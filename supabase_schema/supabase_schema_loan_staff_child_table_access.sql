-- ============================================================
-- SAGANA — Staff read-only access to Loan child tables
-- supabase_schema_staff_dashboard_read_access.sql granted Staff
-- SELECT on farmer_loans, but not on farmer_loan_items or
-- farmer_loan_payments. Every Loan screen that shows loan detail
-- nests both child tables in the same query (e.g. AdminLoanRepository
-- '*, farmer_loan_items(*), farmer_loan_payments(*)'), so a Staff
-- session currently sees the parent loan row but an RLS-empty item
-- list and payment history. This grants Staff the same SELECT-only
-- visibility already granted on farmer_loans, mirroring that
-- migration's exact pattern. No existing policy is modified — Staff
-- gains visibility only, no write access.
-- ============================================================

CREATE POLICY "farmer_loan_items: staff reads all"
  ON public.farmer_loan_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

CREATE POLICY "farmer_loan_payments: staff reads all"
  ON public.farmer_loan_payments FOR SELECT
  USING (EXISTS (SELECT 1 FROM staff_profiles WHERE user_id = auth.uid()));

NOTIFY pgrst, 'reload schema';