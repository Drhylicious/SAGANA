-- ============================================================================
-- Audit 08 (OPTIONAL): remove old duplicate notifications.
--
-- The duplicate rule (audit 02) only looks at new inserts, so the few duplicates
-- created before it stay in the table. They do not affect anything new; they only
-- appear twice in the list of the person who received them. This removes the
-- extra copies and keeps the earliest of each group (same person, type, title and
-- text in the same minute). Review the count first.
-- ============================================================================

-- 1. How many extra copies would be removed (run this first):
SELECT count(*) AS extra_copies
FROM (
  SELECT row_number() OVER (
           PARTITION BY user_id, type, title, body, date_trunc('minute', created_at)
           ORDER BY created_at, id) AS rn
  FROM notifications
) x
WHERE rn > 1;

-- 2. Remove them (run after reviewing the count):
DELETE FROM notifications n
USING (
  SELECT id FROM (
    SELECT id, row_number() OVER (
             PARTITION BY user_id, type, title, body, date_trunc('minute', created_at)
             ORDER BY created_at, id) AS rn
    FROM notifications
  ) x
  WHERE rn > 1
) d
WHERE n.id = d.id;
