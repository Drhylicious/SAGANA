// The e-mail that carries the code. No imports, so it can be read and tested on
// its own; index.ts does the sending.

export const CODE_MINUTES = 10;

export interface VerificationMail {
  subject: string;
  text: string;
  html: string;
}

export function buildVerificationMail(code: string): VerificationMail {
  const subject = `Your SAGANA verification code: ${code}`;
  const text =
    `Your SAGANA email verification code is ${code}\n\n` +
    `Enter it in the app within ${CODE_MINUTES} minutes to verify this email address.\n\n` +
    `If you did not ask for this, you can ignore this message. Nobody can use ` +
    `your account with this code, and your email will stay unverified.\n\n` +
    `SP3 Cooperative - SAGANA`;
  const html =
    `<div style="font-family:Arial,Helvetica,sans-serif;max-width:420px;margin:auto;padding:24px;color:#1b1f23">` +
    `<h2 style="margin:0 0 12px;color:#00450f">SAGANA</h2>` +
    `<p style="margin:0 0 16px">Use this code to verify your email address:</p>` +
    `<p style="font-size:32px;letter-spacing:8px;font-weight:700;margin:0 0 16px;color:#00450f">${code}</p>` +
    `<p style="margin:0 0 12px;font-size:14px">It expires in ${CODE_MINUTES} minutes.</p>` +
    `<p style="margin:0;font-size:12px;color:#5f6b76">If you did not ask for this, ignore this message. ` +
    `Your email will stay unverified and nobody can use your account with this code.</p></div>`;
  return { subject, text, html };
}

export { maskEmail } from "../_shared/util.ts";
