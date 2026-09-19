// Supabase Edge Function — scheduled Broadcast trigger.
//
// Mirrors daily-loan-maintenance/index.ts. Replaces (or backstops)
// pg_cron as the scheduled trigger for process_scheduled_broadcasts(),
// which resolves recipients and inserts notifications for any
// broadcast_logs row whose scheduled_at has passed but hasn't been
// sent yet (sent_at IS NULL). See
// supabase_schema_broadcast_scheduled_send.sql for the function this
// calls and why a real send-later mechanism was needed (Compose's
// "Schedule" toggle previously sent immediately regardless of the
// picked time).
//
// Protected by a shared secret so this can't be triggered by anyone
// who finds the URL — only the external scheduler that knows
// BROADCAST_SCHEDULER_SECRET.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const expectedSecret = Deno.env.get("BROADCAST_SCHEDULER_SECRET");
  const providedSecret = req.headers.get("x-scheduler-secret");

  if (!expectedSecret || providedSecret !== expectedSecret) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data, error } = await supabase.rpc("process_scheduled_broadcasts");

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({ success: true, processed: data, ranAt: new Date().toISOString() }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
