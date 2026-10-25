// Supabase Auth "Send Email" hook: the gate that keeps password-recovery e-mail
// for VERIFIED addresses only.
//
// WHY THIS EXISTS
//   Recovery by e-mail is sent by Supabase Auth itself, straight to the account's
//   sign-in email, when the app (or anyone with the public API key) calls its
//   /recover endpoint. A rule in the app, or in a database function, cannot stop
//   that call. A Send Email hook can: Supabase asks this function to deliver each
//   auth e-mail, so this is where an unverified address is refused.
//
// WHAT IT DOES
//   1. Checks Supabase's signature (standard webhooks); anything else gets 401.
//   2. recovery e-mail: asks the database (may_receive_recovery_email) whether the
//      address is a VERIFIED sign-in email. If not, it does NOT send, and answers
//      success anyway, exactly as Supabase answers for an address it does not know,
//      so nobody can use this to find out which accounts exist or which are
//      verified. If the database cannot be asked, it does NOT send (fails closed).
//   3. verified: sends the reset code by SMTP.
//   Any other kind of auth e-mail is refused: SAGANA uses none (accounts are
//   created already confirmed and sign-in is by password).
//
// SETUP (full steps in README.md)
//   - supabase functions deploy auth-send-email --no-verify-jwt
//     (Supabase calls it without a user JWT; the signature is the proof)
//   - supabase secrets set SEND_EMAIL_HOOK_SECRET="v1,whsec_..."  (from the dashboard)
//   - the SMTP secrets listed in ../_shared/smtp.ts
//   - Dashboard -> Authentication -> Hooks -> Send Email: enable, HTTPS, this URL.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
import { sendMail } from "../_shared/smtp.ts";
import { maskEmail } from "../_shared/util.ts";
import { buildRecoveryMail, classify } from "./logic.ts";

interface HookEvent {
  user?: { email?: string };
  email_data?: { token?: string; email_action_type?: string };
}

function ok(): Response {
  return new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } });
}

function hookError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: { http_code: status, message } }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return hookError(405, "POST only");

  // 1. Only Supabase Auth may call this.
  const body = await req.text();
  const secret = (Deno.env.get("SEND_EMAIL_HOOK_SECRET") ?? "").replace("v1,whsec_", "");
  let event: HookEvent;
  try {
    event = new Webhook(secret).verify(body, Object.fromEntries(req.headers)) as HookEvent;
  } catch (_) {
    return hookError(401, "Invalid signature");
  }

  const email = event.user?.email;
  const token = event.email_data?.token;
  if (!email || !token) return hookError(400, "Missing address or code");

  if (classify(event.email_data?.email_action_type) !== "recovery") {
    return hookError(400, "SAGANA does not send this kind of email.");
  }

  // 2. Verified addresses only.
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
  const { data: allowed, error } = await admin.rpc("may_receive_recovery_email", { p_email: email });
  if (error) {
    console.error("may_receive_recovery_email failed", error.message);
    return hookError(500, "Could not check this account.");
  }
  if (allowed !== true) {
    console.warn("recovery email not sent: address is not verified", maskEmail(email));
    return ok();
  }

  // 3. Send the code.
  try {
    const mail = buildRecoveryMail(token);
    await sendMail({ to: email, subject: mail.subject, text: mail.text, html: mail.html });
  } catch (e) {
    console.error("recovery email failed for", maskEmail(email), (e as Error).message);
    return hookError(500, "Could not send the email.");
  }
  return ok();
});
