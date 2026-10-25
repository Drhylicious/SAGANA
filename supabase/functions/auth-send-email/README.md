# auth-send-email (Supabase Auth "Send Email" hook)

Keeps **password-recovery e-mail for verified addresses only.**

Why a hook: recovery e-mail is sent by Supabase Auth itself, straight to an
account's sign-in email, whenever the app (or anyone holding the public API key)
asks it to. A check in the app or in a database function cannot stop that call.
With this hook switched on, Supabase asks this function to deliver the message,
and the function refuses unless the database says the address is verified
(`may_receive_recovery_email`, script 19).

A refused request looks exactly like a request for an address Supabase does not
know (it answers success and sends nothing), so nobody can use it to find out
which accounts exist or which are verified. If the database cannot be reached,
nothing is sent.

The other recovery method, **Request Password Assistance** (the Manager sets a
temporary password), does not use e-mail and is not affected.

## Before you turn it on

1. Run `supabase_schema_registration_19_recovery_verified_email_only.sql`.
2. **Verify the Manager's own email first** (Edit Profile → Verify Email). Until
   an address is verified it cannot receive a reset code, and nobody else can use
   Password Assistance for the Manager's account.
3. Have the SMTP secrets set (same ones as `send-email-verification`, see
   `../_shared/smtp.ts`).

## Turn it on

```
supabase functions deploy auth-send-email --no-verify-jwt
```

`--no-verify-jwt` is required: Supabase calls a hook without a user token; the
webhook signature is what proves the call is genuine.

Then in the Supabase Dashboard: **Authentication → Hooks → Send Email**

- Enable it, choose **HTTPS**, URL
  `https://<your-project-ref>.supabase.co/functions/v1/auth-send-email`.
- Click **Generate secret**, copy it (`v1,whsec_…`), save the hook, then:

```
supabase secrets set SEND_EMAIL_HOOK_SECRET="v1,whsec_..."
```

While the hook is on, **every** Supabase Auth e-mail goes through this function.
It sends only password-reset codes; SAGANA uses no other auth e-mail (accounts are
created already confirmed and sign in with a password).

## Prove it works

1. A **verified** address (Edit Profile shows Verified): Login → type the email →
   Forgot Password → Send Reset Link. A code arrives; enter it and set a password.
2. An **unverified** address: Login → type the email → Forgot Password. The app
   explains that a verified email is needed and offers the Manager route.
3. The same unverified address, bypassing the app (this is the test that matters):

   ```
   curl -i -X POST "https://<ref>.supabase.co/auth/v1/recover" \
     -H "apikey: <your anon key>" -H "Content-Type: application/json" \
     -d '{"email":"the.unverified@address.com"}'
   ```

   It answers `200`, **no e-mail arrives**, and the function log (Dashboard → Edge
   Functions → auth-send-email → Logs) shows
   `recovery email not sent: address is not verified`. If an e-mail DOES arrive,
   the hook is not enabled yet.
4. Password Assistance for that same account (username on the Login screen →
   Forgot Password → Request Temporary Password) still reaches the Manager.

## Turning it off

Disable the hook in the dashboard. Supabase's built-in mailer takes over again,
and e-mail recovery is then limited only by the Login screen's check (a direct
call to Supabase Auth would again reach any address).
