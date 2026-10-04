-- ============================================================
-- SAGANA — Add a "Name" field to Farmer Expenses
-- (Farmer Profile tab investigation — My Expenses revision)
--
-- The Add Expense form previously had only Category + Description; a
-- farmer had no short, distinct label for an expense separate from its
-- longer free-text description. Adds a nullable `name` column — nullable
-- so existing rows (which never had one) keep displaying correctly via
-- ExpenseModel's fallback to `category` when `name` is null — new entries
-- require it at the application layer (validated in the Add Expense
-- dialog, not enforced here as NOT NULL, to avoid breaking historical
-- rows).
-- ============================================================

ALTER TABLE public.farmer_expenses
  ADD COLUMN IF NOT EXISTS name TEXT;

NOTIFY pgrst, 'reload schema';
