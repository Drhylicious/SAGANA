-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_notifications.sql
-- Run after supabase_schema_auth.sql (depends on user_roles)
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null check (type in ('order','listing','loan','price','sync','system')),
  title       text not null,
  body        text not null,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);

-- Index for fast per-user unread queries
create index if not exists notifications_user_unread_idx
  on notifications(user_id, is_read, created_at desc);

-- Updated-at trigger (consistent with all other tables in SAGANA)
create or replace function handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- RLS
alter table notifications enable row level security;

-- Farmers/buyers: read and update own notifications only
create policy "Users read own notifications"
  on notifications for select
  using (auth.uid() = user_id);

create policy "Users update own notifications"
  on notifications for update
  using (auth.uid() = user_id);

create policy "Users delete own notifications"
  on notifications for delete
  using (auth.uid() = user_id);

-- Admin: insert notifications for any user (for sending alerts)
create policy "Admin insert notifications"
  on notifications for insert
  with check (
    exists (
      select 1 from admin_profiles where user_id = auth.uid()
    )
  );

-- System/service role can also insert (for automated triggers)
-- This is handled by the Supabase service role key, not via RLS.
