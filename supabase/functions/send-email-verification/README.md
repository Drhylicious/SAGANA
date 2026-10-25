# send-email-verification

E-mails the 6-digit code that proves a person owns their contact email
(Edit Profile → Verify Email, all four roles). Design and security notes are in
`supabase_schema/supabase_schema_registration_18_contact_email_verification.sql`
and at the top of `index.ts`.

## One-time setup

1. **Database.** Run script 18 in the Supabase SQL editor (after script 12).
   Then run its BLOCK 1; every row must say PASS.

2. **A mail account the function can send from.** Any SMTP account works: the same
   one you set under Supabase Dashboard → Authentication → SMTP Settings is fine.
   (Supabase's built-in mailer is not used by this function.)

3. **Secrets** (values are examples; use your own):

   ```
   supabase secrets set SMTP_HOST=smtp.example.com
   supabase secrets set SMTP_PORT=465            # 465 = TLS, 587 = STARTTLS
   supabase secrets set SMTP_USER=no-reply@your-domain.ph
   supabase secrets set SMTP_PASS=********
   supabase secrets set "SMTP_FROM=SAGANA <no-reply@your-domain.ph>"
   ```

4. **Deploy:**

   ```
   supabase functions deploy send-email-verification
   ```

   Leave "Verify JWT" on (the default). The function also checks the user itself.

## Try it

Sign in as any user with an email, open Edit Profile → Verify Email. A mail with a
6-digit code should arrive within a minute. Check:

- a wrong code is refused and counts down the tries (5), the right one shows
  Verified;
- asking again within a minute is refused ("Please wait N seconds");
- the Function logs (Dashboard → Edge Functions → Logs) never show the code.

If the mail does not arrive, look at the function logs: `SMTP is not configured`
means a secret is missing; a connection error means host/port/credentials.
The app shows "We couldn't send the email" and the person is not charged a try.
