// The one place the Edge Functions send e-mail from. Plain SMTP, so any provider
// works; the account is set with secrets (supabase secrets set ...):
//   SMTP_HOST   SMTP_PORT (465 = TLS, 587 = STARTTLS)   SMTP_USER   SMTP_PASS
//   SMTP_FROM   e.g.  SAGANA <no-reply@your-domain.ph>
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

export interface OutgoingMail {
  to: string;
  subject: string;
  text: string;
  html: string;
}

/** Why a send failed, in words that are safe to show or log (never a secret). */
export type SmtpFailure =
  | "smtp_not_configured" // a secret is missing
  | "smtp_auth" //            the mail server refused the login
  | "smtp_connect" //         could not reach / secure a connection to the server
  | "smtp_rejected" //        the server accepted the login but refused the message
  | "smtp_error"; //          anything else

export class SmtpError extends Error {
  readonly reason: SmtpFailure;
  constructor(reason: SmtpFailure, message: string) {
    super(message);
    this.reason = reason;
  }
}

/** Sorts a raw mail-library error into one of the reasons above. */
export function classifySmtpError(e: unknown): SmtpError {
  if (e instanceof SmtpError) return e;
  const message = String((e as Error)?.message ?? e).slice(0, 300);
  let reason: SmtpFailure = "smtp_error";
  if (/not configured/i.test(message)) {
    reason = "smtp_not_configured";
  } else if (/\b53[45]\b|username and password|authenticat|credential|auth(orization)? failed|invalid login/i.test(message)) {
    reason = "smtp_auth";
  } else if (/connect|econn|refused|timed? ?out|timeout|resolve|dns|tls|ssl|handshake|certificate|unreachable|network|closed|eof|starttls/i.test(message)) {
    reason = "smtp_connect";
  } else if (/\b55\d\b|\b5\.\d\.\d\b|reject|recipient|mailbox|relay|denied|policy/i.test(message)) {
    reason = "smtp_rejected";
  }
  return new SmtpError(reason, message);
}

/**
 * A secret as it was meant to be: without the line break or spaces that pasting
 * into a secrets box often adds at either end (an address followed by a line
 * break is not a valid address to a mail server). Quotes pasted around a value are removed too,
 * except for the password, where a quote could be part of the real value.
 */
export function cleanSecret(name: string, { stripQuotes = true } = {}): string {
  let v = (Deno.env.get(name) ?? "").trim();
  if (stripQuotes) v = v.replace(/^["'`]+|["'`]+$/g, "").trim();
  return v;
}

/** Sends one message. Throws an SmtpError (with a safe `reason`) on any failure. */
export async function sendMail(mail: OutgoingMail): Promise<void> {
  const host = cleanSecret("SMTP_HOST");
  const port = Number(cleanSecret("SMTP_PORT") || "465");
  const username = cleanSecret("SMTP_USER");
  const password = cleanSecret("SMTP_PASS", { stripQuotes: false });
  const from = cleanSecret("SMTP_FROM");
  if (!host || !username || !password || !from) {
    throw new SmtpError("smtp_not_configured", "SMTP is not configured");
  }
  try {
    const client = new SMTPClient({
      connection: {
        hostname: host,
        port,
        tls: port === 465,
        auth: { username, password },
      },
    });
    try {
      await client.send({
        from,
        to: mail.to,
        subject: mail.subject,
        content: mail.text,
        html: mail.html,
      });
    } finally {
      try {
        await client.close();
      } catch (_) {
        // closing is best effort
      }
    }
  } catch (e) {
    throw classifySmtpError(e);
  }
}
