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

/** Sends one message. Throws if SMTP is not configured or the server refuses. */
export async function sendMail(mail: OutgoingMail): Promise<void> {
  const host = Deno.env.get("SMTP_HOST");
  const port = Number(Deno.env.get("SMTP_PORT") ?? "465");
  const username = Deno.env.get("SMTP_USER");
  const password = Deno.env.get("SMTP_PASS");
  const from = Deno.env.get("SMTP_FROM");
  if (!host || !username || !password || !from) {
    throw new Error("SMTP is not configured");
  }
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
}
