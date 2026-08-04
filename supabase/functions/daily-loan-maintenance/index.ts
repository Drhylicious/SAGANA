// Supabase Edge Function â€” daily loan maintenance trigger.
//
// Replaces pg_cron (unavailable on the Free tier) as the scheduled trigger
// for run_daily_loan_maintenance(), which transitions active loans to
// overdue past their grace period and notifies farmers whose loans just
// went overdue. See supabase_schema_loan_overdue_automation.sql for the
// function this calls and why the app-side reconcileOverdueLoans() fallback
// alone isn't sufficient (it only transitions status, never notifies).
//
// Protected by a shared secret so this can't be triggered by anyone who
// finds the URL â€” only the external scheduler that knows LOAN_MAINTENANCE_SECRET.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const expectedSecret = Deno.env.get("LOAN_MAINTENANCE_SECRET");
  const providedSecret = req.headers.get("x-maintenance-secret");

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

    const { error } = await supabase.rpc("run_daily_loan_maintenance");

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(
      JSON.stringify({ success: true, ranAt: new Date().toISOString() }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

