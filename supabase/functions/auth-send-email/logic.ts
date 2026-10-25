// What the Send Email hook decides and writes. No Deno or network imports here
// so it can be read and tested on its own; index.ts does the I/O.

export type EmailKind = "recovery" | "other";

/** Supabase names the kind of mail in email_data.email_action_type. */
export function classify(actionType: unknown): EmailKind {
  return actionType === "recovery" ? "recovery" : "other";
}

export interface RecoveryMail {
  subject: string;
  text: string;
  html: string;
}

export function buildRecoveryMail(token: string): RecoveryMail {
  const subject = `Your SAGANA password reset code: ${token}`;
  const text =
    `Your SAGANA password reset code is ${token}\n\n` +
    `Enter it in the app to choose a new password. The code works for a limited time.\n\n` +
    `If you did not ask for this, ignore this message: your password will not change.\n\n` +
    `SP3 Cooperative - SAGANA`;
  const html =
    `<div style="font-family:Arial,Helvetica,sans-serif;max-width:420px;margin:auto;padding:24px;color:#1b1f23">` +
    `<h2 style="margin:0 0 12px;color:#00450f">SAGANA</h2>` +
    `<p style="margin:0 0 16px">Use this code to reset your password:</p>` +
    `<p style="font-size:32px;letter-spacing:8px;font-weight:700;margin:0 0 16px;color:#00450f">${token}</p>` +
    `<p style="margin:0 0 12px;font-size:14px">It works for a limited time.</p>` +
    `<p style="margin:0;font-size:12px;color:#5f6b76">If you did not ask for this, ignore this message. ` +
    `Your password will not change.</p></div>`;
  return { subject, text, html };
}
