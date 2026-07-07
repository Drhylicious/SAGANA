-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_broadcast_logs.sql
-- Records all admin notification broadcasts for history and audit.
-- Run in Supabase SQL Editor.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS broadcast_logs (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title            TEXT NOT NULL,
  body             TEXT NOT NULL,
  category         TEXT NOT NULL DEFAULT 'general'
                     CHECK (category IN ('meeting','financial','harvest','update','general')),
  recipient_type   TEXT NOT NULL DEFAULT 'all_members'
                     CHECK (recipient_type IN (
                       'all_members',
                       'outstanding_loans',
                       'specific_crop',
                       'specific_farmer'
                     )),
  recipient_filter TEXT,        -- crop name or farmer_id when applicable
  recipient_count  INT NOT NULL DEFAULT 0,
  scheduled_at     TIMESTAMPTZ, -- NULL = sent immediately
  sent_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS broadcast_logs_sent_at_idx
  ON broadcast_logs(sent_at DESC);

CREATE INDEX IF NOT EXISTS broadcast_logs_created_by_idx
  ON broadcast_logs(created_by);

-- RLS
ALTER TABLE broadcast_logs ENABLE ROW LEVEL SECURITY;

-- Admin: full access
CREATE POLICY "Admin full access to broadcast_logs"
  ON broadcast_logs FOR ALL
  USING (
    EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())
  );

-- No farmer/buyer access — this is an internal admin log
