-- ============================================================
-- SAGANA — Enrollment records audit (READ-ONLY: changes nothing)
--
-- Run each query by itself in the Supabase SQL editor and send me the results.
-- The Enrolled list in Enrollment Requests now shows every ACTIVE program member,
-- so no data change is needed for those members to appear. These queries only
-- check the records for inconsistencies, so anything that really is wrong can be
-- corrected on purpose, with your approval, and never by guesswork.
--
-- Definitions used by the app:
--   Enrolled            = program_members.status = 'active'   (the Program Management
--                         count and the Enrolled list both use exactly this)
--   Enrollment request  = program_enrollment_requests (pending / approved / rejected)
-- ============================================================

-- A1  Enrolled members per program (these add up to the Program Management "Enrolled" figure):
SELECT cp.program_name, cp.program_purpose, count(*) AS enrolled
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
 WHERE pm.status = 'active'
 GROUP BY cp.program_name, cp.program_purpose
 ORDER BY cp.program_name;

-- A2  The total (should equal the KPI card, e.g. 6):
SELECT count(*) AS enrolled_total FROM program_members WHERE status = 'active';

-- A3  Enrolled members with NO approved request on record. These are valid members
--     (enrolled directly or before requests existed). They were missing from the old
--     Enrolled list and appear now, marked "Enrolled by the cooperative".
SELECT cp.program_name, ui.full_name, pm.enrolled_at
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
  LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
 WHERE pm.status = 'active'
   AND NOT EXISTS (SELECT 1 FROM program_enrollment_requests r
                    WHERE r.program_id = pm.program_id AND r.farmer_id = pm.farmer_id AND r.status = 'approved')
 ORDER BY cp.program_name, pm.enrolled_at;

-- A4  APPROVED requests whose farmer is NOT enrolled (withdrawn, or no member row at all).
--     The old Enrolled list wrongly counted these; the new one does not. A row here with
--     member_status NULL would be a genuine inconsistency (approved but never enrolled):
--     tell me and we will decide, per person, what to do.
SELECT cp.program_name, ui.full_name, r.reviewed_at, pm.status AS member_status
  FROM program_enrollment_requests r
  JOIN cooperative_programs cp ON cp.id = r.program_id
  LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
  LEFT JOIN program_members pm ON pm.program_id = r.program_id AND pm.farmer_id = r.farmer_id
 WHERE r.status = 'approved'
   AND (pm.id IS NULL OR pm.status <> 'active')
 ORDER BY cp.program_name, r.reviewed_at;

-- A5  A farmer who still has a PENDING request for a program they are already enrolled in:
SELECT cp.program_name, ui.full_name, r.submitted_at
  FROM program_enrollment_requests r
  JOIN cooperative_programs cp ON cp.id = r.program_id
  LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
  JOIN program_members pm ON pm.program_id = r.program_id AND pm.farmer_id = r.farmer_id AND pm.status = 'active'
 WHERE r.status = 'pending';

-- A6  Duplicate member rows (the table should allow one row per farmer and program; expect 0 rows):
SELECT program_id, farmer_id, count(*) FROM program_members GROUP BY 1, 2 HAVING count(*) > 1;
