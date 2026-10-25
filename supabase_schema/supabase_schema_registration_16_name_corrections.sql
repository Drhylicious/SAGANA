-- ============================================================
-- supabase_schema_registration_16_name_corrections.sql
--
-- Final name corrections for the remaining one-line accounts, and the checks
-- needed before removing the test account.
--
-- Run each BLOCK on its own (select it, press Run). The editor only shows the
-- last statement's result.
--
-- RULES FOLLOWED
--   * First name and surname are written exactly as given. A first name such as
--     "John Harvey" or "Ellen Angela" is ONE first name; it is never split into a
--     first and a middle name.
--   * middle_initial and suffix stay NULL (optional). Nothing here invents a
--     middle initial, or takes one out of a first name.
--   * Every row is guarded by the user_id AND the name stored when it was
--     reviewed. If an account has changed since, it is skipped, not overwritten.
--   * Only the four name columns are written. Sign-in, roles, statuses and every
--     other table are untouched.
-- ============================================================


-- ─── BLOCK 1 — VERIFY (read-only). Run first and read it. ──────────────────
-- Shows every account named Revilloza, John Harvey / John Harold, Ellen Angela or
-- "testing", with its role, status and how many records hang off it.
--
-- To delete a test account safely, ALL of the "records" columns must be 0 and the
-- account must be a Disapproved farmer applicant (role farmer, status rejected).
-- That is exactly what the app's own Delete button requires.

SELECT ui.user_id,
       ui.full_name,
       ui.surname, ui.first_name,
       ui.username,
       (SELECT string_agg(r.role || ':' || r.status, ', ' ORDER BY r.role)
        FROM public.user_roles r WHERE r.user_id = ui.user_id)              AS role_status,
       (SELECT count(*) FROM public.harvest_records            h  WHERE h.farmer_id  = ui.user_id) AS harvests,
       (SELECT count(*) FROM public.orders                     o  WHERE o.farmer_id  = ui.user_id
                                                                     OR o.buyer_id   = ui.user_id) AS orders,
       (SELECT count(*) FROM public.farmer_loans               l  WHERE l.farmer_id  = ui.user_id) AS loans,
       (SELECT count(*) FROM public.member_capital_shares      s  WHERE s.farmer_id  = ui.user_id) AS capital_rows,
       (SELECT count(*) FROM public.member_contributions       c  WHERE c.farmer_id  = ui.user_id) AS contribution_rows,
       (SELECT count(*) FROM public.capital_contribution_events e WHERE e.farmer_id  = ui.user_id) AS capital_events
FROM public.user_information ui
WHERE ui.full_name ILIKE '%Revilloza%'
   OR ui.full_name ILIKE 'John Harvey%'
   OR ui.full_name ILIKE 'John Harold%'
   OR ui.full_name ILIKE 'Ellen Angela%'
   OR ui.full_name ILIKE '%testing%'
ORDER BY ui.full_name;


-- ─── BLOCK 2 — APPLY the name corrections. ─────────────────────────────────
-- Expect 9 rows. name_before / name_after show what changed:
--   * John Harvey  ->  John Harvey Revilloza   (the surname was missing; this is
--     the one intended change of the displayed name)
--   * every other row: name_after is identical to name_before.
-- Fewer than 9 rows means an account no longer matches the name it was reviewed
-- with; nothing was written for it.

WITH v(user_id, expected_name, first_name, middle_initial, surname, suffix) AS (VALUES
  ('ad07f821-f241-493a-bfc2-073f5036852d'::uuid, 'John Harvey',           'John Harvey',  NULL::text, 'Revilloza', NULL::text),
  ('fd0d510a-d380-4819-9c97-1d206ed9dd3d'::uuid, 'John Harold Revilloza', 'John Harold',  NULL::text, 'Revilloza', NULL::text),
  ('8069f0d9-0117-40f3-8c97-def869e8587b'::uuid, 'Ellen Angela Rosal',    'Ellen Angela', NULL::text, 'Rosal',     NULL::text),
  ('533accad-bee5-4a4e-842c-683c9448192a'::uuid, 'Aldrin Requiz',         'Aldrin',       NULL::text, 'Requiz',    NULL::text),
  ('4225b1fa-54c1-4299-b8e2-4d6809b5ccd4'::uuid, 'Genroj Laguna',         'Genroj',       NULL::text, 'Laguna',    NULL::text),
  ('bd116aa0-109b-47ff-a03b-42d3453411cc'::uuid, 'Itsuki Nakano',         'Itsuki',       NULL::text, 'Nakano',    NULL::text),
  ('a5fdf139-9552-4291-aac2-2bb5147bd774'::uuid, 'Kei Amane',             'Kei',          NULL::text, 'Amane',     NULL::text),
  ('32dbca85-d93e-49bc-a468-06d08e70a6ed'::uuid, 'Miku Nakano',           'Miku',         NULL::text, 'Nakano',    NULL::text),
  ('2597cfa0-9889-421b-9dbe-86be2b5bc59d'::uuid, 'testing test',          'testing',      NULL::text, 'test',      NULL::text)
)
UPDATE public.user_information ui
SET surname        = v.surname,
    first_name     = v.first_name,
    middle_initial = v.middle_initial,
    suffix         = v.suffix
FROM v
WHERE ui.user_id = v.user_id
  AND ui.full_name = v.expected_name
  AND ui.surname IS NULL AND ui.first_name IS NULL
RETURNING ui.user_id,
          v.expected_name AS name_before,
          ui.full_name    AS name_after,
          (ui.full_name = v.expected_name) AS name_unchanged,
          ui.first_name, ui.middle_initial, ui.surname, ui.suffix;


-- ─── BLOCK 3 — CHECK the result (read-only). ───────────────────────────────
-- Expect: no account left with a one-line name except any you chose to leave,
-- every full_name equal to the name built from its parts, and no middle initial
-- on any of the accounts corrected above.

SELECT 'Accounts still with a one-line name' AS check_name,
       CASE WHEN n = 0 THEN 'PASS' ELSE 'INFO' END AS result,
       n::text AS detail
FROM (SELECT count(*) AS n FROM public.user_information WHERE surname IS NULL) x
UNION ALL
SELECT 'Every full_name equals the name built from its parts',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END,
       n || ' mismatched'
FROM (SELECT count(*) AS n FROM public.user_information
      WHERE surname IS NOT NULL
        AND full_name IS DISTINCT FROM
            public.compose_full_name(first_name, middle_initial, surname, suffix)) y
UNION ALL
SELECT 'Corrected accounts: no middle initial was invented',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END,
       n || ' with a middle initial'
FROM (SELECT count(*) AS n FROM public.user_information
      WHERE user_id IN ('ad07f821-f241-493a-bfc2-073f5036852d',
                        'fd0d510a-d380-4819-9c97-1d206ed9dd3d',
                        '8069f0d9-0117-40f3-8c97-def869e8587b')
        AND middle_initial IS NOT NULL) z;
