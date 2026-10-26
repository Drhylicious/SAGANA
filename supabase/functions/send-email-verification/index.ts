// Sends the 6-digit code that proves a person owns their contact email.
//
// WHO MAY CALL IT   Only a signed-in user (their JWT is checked here). It always
//                   acts on the CALLER's own account; there is no user id in the
//                   request, so nobody can ask for a code for someone else.
// WHAT IT DOES      1. identifies the caller from the JWT;
//                   2. a Manager changing their SIGN-IN email must also give their
//                      current password, checked here;
//                   3. asks the database to issue a code (rate limits, expiry and
//                      the hashing all live there: issue_contact_email_code, which
//                      only the service role may run). The code is for the PENDING
//                      address when a change is in progress, else the email in use;
//                   4. e-mails the code to that address;
//                   5. if the e-mail cannot be sent, tells the database to void the
//                      code and give the send back.
//                   THE CODE IS NEVER RETURNED TO THE CALLER OR WRITTEN TO A LOG.
//
// Request:  POST. No body is needed, except that a Manager changing their SIGN-IN
//           email sends { "current_password": "..." } (see step 2 below).
// Response (always HTTP 200 unless the call itself is bad):
//   { status: "sent", email: "a****@gmail.com", resend_after: 60, expires_in: 600 }
//   { status: "cooldown" | "limit", retry_after: <seconds> }
//   { status: "already_verified" | "no_email" }
//   { status: "password_required" | "wrong_password" }   Manager sign-in email change
//   HTTP 401 { status: "unauthorized" }   not signed in
//   HTTP 502 { status: "send_failed", reason }   the mail could not be sent; reason is
//            one of smtp_not_configured | smtp_auth | smtp_connect | smtp_rejected |
//            smtp_error | db_error (never a secret)
//
// SECRETS: the SMTP account used by ../_shared/smtp.ts (SMTP_HOST, SMTP_PORT,
// SMTP_USER, SMTP_PASS, SMTP_FROM). SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by
// Supabase itself.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { classifySmtpError, sendMail } from "../_shared/smtp.ts";
import { buildVerificationMail, maskEmail } from "./mail.ts";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function sendCode(to: string, code: string): Promise<void> {
  const mail = buildVerificationMail(code);
  await sendMail({ to, subject: mail.subject, text: mail.text, html: mail.html });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json(405, { status: "method_not_allowed" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1. Who is asking: the signed-in user behind this JWT, nobody else.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { status: "unauthorized" });
  }
  const asUser = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: who, error: whoErr } = await asUser.auth.getUser();
  if (whoErr || !who?.user) return json(401, { status: "unauthorized" });
  const userId = who.user.id;

  const admin = createClient(url, service, { auth: { persistSession: false } });

  // 2. A Manager who is changing the address they SIGN IN with must also prove
  //    they know their current password, checked here against Supabase Auth, so a
  //    borrowed or stolen session alone cannot redirect the account. The password
  //    is used for this one check and is never stored or logged.
  const { data: needsPassword, error: needsErr } = await admin.rpc("email_change_needs_password", {
    p_user_id: userId,
  });
  // Until the change-email script is applied the check does not exist, which
  // means no change can be in progress: nothing to confirm. Any other failure
  // is not guessed at; it stops here.
  const checkMissing =
    needsErr?.code === "PGRST202" || /could not find the function/i.test(needsErr?.message ?? "");
  if (needsErr && !checkMissing) {
    console.error("email_change_needs_password failed", needsErr.message);
    return json(502, { status: "send_failed", reason: "db_error" });
  }
  if (!needsErr && needsPassword === true) {
    let password = "";
    try {
      const body = await req.json();
      if (typeof body?.current_password === "string") password = body.current_password;
    } catch (_) {
      // no body: handled as "password required"
    }
    if (!password) return json(200, { status: "password_required" });
    const probe = createClient(url, anon, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error: pwErr } = await probe.auth.signInWithPassword({
      email: who.user.email ?? "",
      password,
    });
    if (pwErr) return json(200, { status: "wrong_password" });
  }

  // 3. The database decides whether a code may be sent, and makes it.
  const { data: issued, error: issueErr } = await admin.rpc("issue_contact_email_code", {
    p_user_id: userId,
  });
  if (issueErr || !issued) {
    console.error("issue_contact_email_code failed", issueErr?.message);
    return json(502, { status: "send_failed", reason: "db_error" });
  }
  if (issued.status !== "sent") {
    // cooldown, limit, already_verified, no_email: a normal answer, not an error.
    return json(200, { status: issued.status, retry_after: issued.retry_after ?? null });
  }

  // 4. Send it. The code leaves this function only inside the e-mail.
  try {
    await sendCode(issued.email as string, issued.code as string);
  } catch (e) {
    const failure = classifySmtpError(e);
    // The mail server's wording and a masked address; never the password or the code.
    console.error("send failed for", maskEmail(issued.email as string), failure.reason, failure.message);
    // 5. Give the send back so the person is not penalised for our failure.
    await admin.rpc("release_contact_email_code", { p_user_id: userId });
    return json(502, { status: "send_failed", reason: failure.reason });
  }

  return json(200, {
    status: "sent",
    email: maskEmail(issued.email as string),
    resend_after: issued.resend_after ?? 60,
    expires_in: issued.expires_in ?? 600,
  });
});
