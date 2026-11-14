// Sends a phone (FCM) push for one new row of the `notifications` table.
//
// WHO CALLS IT   The database trigger push_new_notification() on every notification
//                insert, with the shared secret in the x-push-secret header. Nobody
//                else: no JWT is involved, so deploy with --no-verify-jwt.
// WHAT IT DOES   Looks up the recipient's phones in device_push_tokens and sends
//                each one the notification through Firebase Cloud Messaging (HTTP
//                v1). The message carries notification_id and route so a tap opens
//                the same screen as the in-app list. Tokens FCM reports as dead are
//                deleted.
//
// Request body: { notification_id, user_id, title, body, route, route_extra }
//
// SECRETS (supabase secrets set ...):
//   PUSH_WEBHOOK_SECRET   same value as push_config.webhook_secret in the database
//   FCM_SERVICE_ACCOUNT   the whole Firebase service-account JSON (Firebase console >
//                         Project settings > Service accounts > Generate new key)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase itself.
//
// Deploy: supabase functions deploy send-push-notification --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const ANDROID_CHANNEL_ID = "sagana_notifications"; // created in MainActivity.kt

function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function b64url(input: ArrayBuffer | string): string {
  const bytes = typeof input === "string"
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let bin = "";
  bytes.forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

// Exchanges the service account for a short-lived OAuth token for FCM.
async function fcmAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const assertion = `${header}.${claims}.${b64url(signature)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`oauth_failed_${res.status}`);
  return (await res.json()).access_token as string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { status: "method_not_allowed" });

  const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-push-secret") !== secret) {
    return json(401, { status: "unauthorized" });
  }

  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!saJson) return json(500, { status: "fcm_not_configured" });

  let payload: Record<string, string | null>;
  try {
    payload = await req.json();
  } catch {
    return json(400, { status: "bad_request" });
  }
  const userId = payload.user_id;
  if (!userId) return json(400, { status: "bad_request" });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const { data: tokens, error } = await admin
    .from("device_push_tokens")
    .select("token")
    .eq("user_id", userId);
  if (error) return json(500, { status: "db_error" });
  if (!tokens || tokens.length === 0) return json(200, { status: "no_devices" });

  const sa = JSON.parse(saJson);
  let accessToken: string;
  try {
    accessToken = await fcmAccessToken(sa);
  } catch (e) {
    return json(502, { status: "fcm_auth_failed", reason: String(e) });
  }

  // FCM data values must all be strings.
  const data: Record<string, string> = {
    notification_id: payload.notification_id ?? "",
    route: payload.route ?? "",
    route_extra: payload.route_extra ?? "",
  };

  const dead: string[] = [];
  let sent = 0;
  await Promise.all(tokens.map(async ({ token }) => {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: payload.title ?? "SAGANA", body: payload.body ?? "" },
            data,
            android: {
              priority: "HIGH",
              notification: { channel_id: ANDROID_CHANNEL_ID },
            },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      },
    );
    if (res.ok) {
      sent++;
    } else if (res.status === 404 || res.status === 400) {
      // UNREGISTERED / INVALID_ARGUMENT: the app was removed or the token expired.
      dead.push(token);
    }
  }));

  if (dead.length > 0) {
    await admin.from("device_push_tokens").delete().in("token", dead);
  }
  return json(200, { status: "ok", sent, removed: dead.length });
});
