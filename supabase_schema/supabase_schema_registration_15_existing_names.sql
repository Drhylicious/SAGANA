-- ============================================================
-- supabase_schema_registration_15_existing_names.sql
--
-- Moves the names of accounts created BEFORE the separated name fields into
-- surname / first_name / middle_initial / suffix, without guessing.
--
-- Run after script 12. Run each BLOCK on its own (select it, press Run). The
-- editor only shows the last statement's result, so do not run them together.
--
-- WHAT COUNTS AS RELIABLE
--   A name is split automatically ONLY when it is written in the one format the
--   app itself produces:   First [names] M. Surname [Suffix]
--   i.e. it contains exactly ONE middle initial written as a letter and a period,
--   with a real first name before it and a real surname after it
--   ("Jhon Drhy M. Salangsang", "Marc Louie M. Yañez Jr."). The initial marks
--   where the first name ends and the surname begins, so nothing is guessed.
--
--   Every other name ("Ellen Angela Rosal", "Juan Cruz") is AMBIGUOUS: the
--   surname could be one word or two, and the order could even be reversed. Those
--   are NOT touched. Block 3 lists them, each with a ready-to-edit UPDATE that you
--   fill in once you know the real surname and first name.
--
-- NAMES ARE PRESERVED
--   Every update is guarded: the new parts must rebuild EXACTLY the name already
--   stored (compose_full_name(parts) = full_name). If they do not, the row is not
--   updated. Only the four name columns are written; sign-in, roles, statuses and
--   every other table are untouched.
-- ============================================================


-- ─── BLOCK 1 — PREVIEW (read-only). Run first and read the result. ─────────
-- status AUTO    = will be split by Block 2 (shown in the four right-hand columns)
-- status CONFIRM = left alone; handled in Block 3

WITH base AS (
  SELECT ui.user_id,
         (SELECT string_agg(r.role, ', ' ORDER BY r.role)
          FROM public.user_roles r WHERE r.user_id = ui.user_id) AS roles,
         ui.full_name,
         regexp_replace(btrim(ui.full_name), '\s+', ' ', 'g') AS nm
  FROM public.user_information ui
  WHERE ui.surname IS NULL AND ui.first_name IS NULL
), cut AS (
  SELECT *,
         lower((regexp_match(nm, ' (jr|sr|ii|iii|iv|v)\.?$', 'i'))[1]) AS suffix_raw,
         regexp_replace(nm, ' (jr|sr|ii|iii|iv|v)\.?$', '', 'i')        AS core
  FROM base
), parsed AS (
  SELECT *,
         regexp_match(core, '^(.+) ([A-Za-z])\. (.+)$') AS m,
         CASE suffix_raw WHEN 'jr' THEN 'Jr.' WHEN 'sr' THEN 'Sr.' WHEN 'ii' THEN 'II'
                         WHEN 'iii' THEN 'III' WHEN 'iv' THEN 'IV' WHEN 'v' THEN 'V' END AS sfx
  FROM cut
), judged AS (
  SELECT *,
         (m IS NOT NULL
          AND (SELECT count(*) FROM regexp_matches(core, '(^| )[A-Za-z]\.(?= |$)', 'g')) = 1
          AND length(m[1]) BETWEEN 2 AND 60 AND m[1] ~ '^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .''’-]*$' AND m[1] ~ '[A-Za-zÀ-ɏ]{2}'
          AND length(m[3]) BETWEEN 2 AND 60 AND m[3] ~ '^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .''’-]*$' AND m[3] ~ '[A-Za-zÀ-ɏ]{2}'
          AND public.compose_full_name(m[1], upper(m[2]), m[3], sfx) = full_name
         ) AS is_auto
  FROM parsed
)
SELECT user_id, roles, full_name,
       CASE WHEN is_auto THEN 'AUTO' ELSE 'CONFIRM' END AS status,
       CASE WHEN is_auto THEN m[1] END        AS first_name,
       CASE WHEN is_auto THEN upper(m[2]) END AS middle_initial,
       CASE WHEN is_auto THEN m[3] END        AS surname,
       CASE WHEN is_auto THEN sfx END         AS suffix
FROM judged
ORDER BY status, full_name;


-- ─── BLOCK 2 — APPLY the AUTO rows only. Run after you agree with Block 1. ──
-- Writes the four name columns of the AUTO rows. The database rebuilds
-- full_name from them; name_unchanged must be true on every row returned.

WITH base AS (
  SELECT ui.user_id, ui.full_name,
         regexp_replace(btrim(ui.full_name), '\s+', ' ', 'g') AS nm
  FROM public.user_information ui
  WHERE ui.surname IS NULL AND ui.first_name IS NULL
), cut AS (
  SELECT *,
         lower((regexp_match(nm, ' (jr|sr|ii|iii|iv|v)\.?$', 'i'))[1]) AS suffix_raw,
         regexp_replace(nm, ' (jr|sr|ii|iii|iv|v)\.?$', '', 'i')        AS core
  FROM base
), parsed AS (
  SELECT *,
         regexp_match(core, '^(.+) ([A-Za-z])\. (.+)$') AS m,
         CASE suffix_raw WHEN 'jr' THEN 'Jr.' WHEN 'sr' THEN 'Sr.' WHEN 'ii' THEN 'II'
                         WHEN 'iii' THEN 'III' WHEN 'iv' THEN 'IV' WHEN 'v' THEN 'V' END AS sfx
  FROM cut
), auto AS (
  SELECT user_id, full_name, m[1] AS first_name, upper(m[2]) AS middle_initial,
         m[3] AS surname, sfx AS suffix
  FROM parsed
  WHERE m IS NOT NULL
    AND (SELECT count(*) FROM regexp_matches(core, '(^| )[A-Za-z]\.(?= |$)', 'g')) = 1
    AND length(m[1]) BETWEEN 2 AND 60 AND m[1] ~ '^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .''’-]*$' AND m[1] ~ '[A-Za-zÀ-ɏ]{2}'
    AND length(m[3]) BETWEEN 2 AND 60 AND m[3] ~ '^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .''’-]*$' AND m[3] ~ '[A-Za-zÀ-ɏ]{2}'
    AND public.compose_full_name(m[1], upper(m[2]), m[3], sfx) = full_name
)
UPDATE public.user_information ui
SET surname = a.surname,
    first_name = a.first_name,
    middle_initial = a.middle_initial,
    suffix = a.suffix
FROM auto a
WHERE ui.user_id = a.user_id
  AND ui.surname IS NULL AND ui.first_name IS NULL
RETURNING ui.user_id,
          a.full_name  AS name_before,
          ui.full_name AS name_after,
          (ui.full_name = a.full_name) AS name_unchanged,
          ui.surname, ui.first_name, ui.middle_initial, ui.suffix;


-- ─── BLOCK 3 — the names that need YOUR confirmation (read-only). ──────────
-- One row per account that Block 1 marked CONFIRM. The last column is an UPDATE
-- ready to edit: replace <FIRST NAME(S)> and <SURNAME> with the person's real
-- first name(s) and surname (and fill the middle initial / suffix if there is
-- one), then run that single statement.
--   * It only works if the parts rebuild the stored name exactly, so a typo
--     updates nothing (0 rows returned) instead of changing the name.
--   * Left as it is (still containing the < > placeholders) it changes nothing
--     and returns 0 rows, so it cannot be run by accident.

WITH base AS (
  SELECT ui.user_id,
         (SELECT string_agg(r.role, ', ' ORDER BY r.role)
          FROM public.user_roles r WHERE r.user_id = ui.user_id) AS roles,
         ui.full_name,
         regexp_replace(btrim(ui.full_name), '\s+', ' ', 'g') AS nm
  FROM public.user_information ui
  WHERE ui.surname IS NULL AND ui.first_name IS NULL
), cut AS (
  SELECT *,
         lower((regexp_match(nm, ' (jr|sr|ii|iii|iv|v)\.?$', 'i'))[1]) AS suffix_raw,
         regexp_replace(nm, ' (jr|sr|ii|iii|iv|v)\.?$', '', 'i')        AS core
  FROM base
), parsed AS (
  SELECT *,
         regexp_match(core, '^(.+) ([A-Za-z])\. (.+)$') AS m,
         CASE suffix_raw WHEN 'jr' THEN 'Jr.' WHEN 'sr' THEN 'Sr.' WHEN 'ii' THEN 'II'
                         WHEN 'iii' THEN 'III' WHEN 'iv' THEN 'IV' WHEN 'v' THEN 'V' END AS sfx
  FROM cut
)
SELECT user_id, roles, full_name,
       array_length(regexp_split_to_array(nm, ' '), 1) AS words,
       format(
         $f$WITH v(first_name, middle_initial, surname, suffix) AS (VALUES ('<FIRST NAME(S)>', NULL::text, '<SURNAME>', NULL::text)) UPDATE public.user_information ui SET surname = v.surname, first_name = v.first_name, middle_initial = v.middle_initial, suffix = v.suffix FROM v WHERE ui.user_id = %L AND ui.surname IS NULL AND ui.full_name = public.compose_full_name(v.first_name, v.middle_initial, v.surname, v.suffix) RETURNING ui.full_name, ui.surname, ui.first_name, ui.middle_initial, ui.suffix;$f$,
         user_id) AS statement_to_edit
FROM parsed
WHERE NOT (
  m IS NOT NULL
  AND (SELECT count(*) FROM regexp_matches(core, '(^| )[A-Za-z]\.(?= |$)', 'g')) = 1
  AND length(m[1]) BETWEEN 2 AND 60 AND m[1] ~ '^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .''’-]*$' AND m[1] ~ '[A-Za-zÀ-ɏ]{2}'
  AND length(m[3]) BETWEEN 2 AND 60 AND m[3] ~ '^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .''’-]*$' AND m[3] ~ '[A-Za-zÀ-ɏ]{2}'
  AND public.compose_full_name(m[1], upper(m[2]), m[3], sfx) = full_name
)
ORDER BY full_name;


-- ─── BLOCK 4 — check the result. Run script 14, Block B, afterwards. ───────
-- It reports structured vs one-line accounts and fails if any structured
-- account's full_name does not match its parts.
