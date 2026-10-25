// Sends the 6-digit code that proves a person owns their contact email.
//
// WHO MAY CALL IT   Only a signed-in user (their JWT is checked here). It always
//                   acts on the CALLER's own account; there is no user id in the
//                   request, so nobody can ask for a code for someone else.
// WHAT IT DOES      1. identifies the caller from the JWT;
//                   2. asks the database to issue a code (rate limits, expiry and
//                      the hashing all live there: issue_contact_email_code, which
//                      only the service role may run);
//                   3. e-mails the code to the account's email address;
//                   4. if the e-mail cannot be sent, tells the database to void the
//                      code and give the send back.
//                   THE CODE IS NEVER RETURNED TO THE CALLER OR WRITTEN TO A LOG.
//
// Request:  POST (no body needed)
// Response (always HTTP 200 unless the call itself is bad):
//   { status: "sent", email: "a****@gmail.com", resend_after: 60, expires_in: 600 }
//   { status: "cooldown" | "limit", retry_after: <seconds> }
//   { status: "already_verified" | "no_email" }
//   HTTP 401 { status: "unauthorized" }   not signed in
//   HTTP 502 { status: "send_failed" }    the mail server refused or timed out
//
// SECRETS: the SMTP account used by ../_shared/smtp.ts (SMTP_HOST, SMTP_PORT,
// SMTP_USER, SMTP_PASS, SMTP_FROM). SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided by
// Supabase itself.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { sendMail } from "../_shared/smtp.ts";
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

  // 2. The database decides whether a code may be sent, and makes it.
  const admin = createClient(url, service, { auth: { persistSession: false } });
  const { data: issued, error: issueErr } = await admin.rpc("issue_contact_email_code", {
    p_user_id: userId,
  });
  if (issueErr || !issued) {
    console.error("issue_contact_email_code failed", issueErr?.message);
    return json(502, { status: "send_failed" });
  }
  if (issued.status !== "sent") {
    // cooldown, limit, already_verified, no_email: a normal answer, not an error.
    return json(200, { status: issued.status, retry_after: issued.retry_after ?? null });
  }

  // 3. Send it. The code leaves this function only inside the e-mail.
  try {
    await sendCode(issued.email as string, issued.code as string);
  } catch (e) {
    console.error("send failed for", maskEmail(issued.email as string), (e as Error).message);
    // 4. Give the send back so the person is not penalised for our failure.
    await admin.rpc("release_contact_email_code", { p_user_id: userId });
    return json(502, { status: "send_failed" });
  }

  return json(200, {
    status: "sent",
    email: maskEmail(issued.email as string),
    resend_after: issued.resend_after ?? 60,
    expires_in: issued.expires_in ?? 600,
  });
});
