/** "ana.reyes@gmail.com" -> "a********@gmail.com" (for messages and logs). */
export function maskEmail(email: string): string {
  const at = email.indexOf("@");
  if (at < 1) return "***";
  return email[0] + "*".repeat(Math.max(at - 1, 1)) + email.slice(at);
}
