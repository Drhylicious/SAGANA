-- ============================================================
-- SAGANA — Dead Column Cleanup: farmer_loans.loan_reference
-- Added by supabase_schema_fixes.sql, never read or written by
-- any repository — reference_no is the actual field in use
-- everywhere (LoanModel, AdminLoanSummary, farmer-side screens).
-- Confirmed via grep across every Dart/SQL file in the Reports/
-- Loans surface before removal.
-- ============================================================

ALTER TABLE farmer_loans
  DROP COLUMN IF EXISTS loan_reference;
