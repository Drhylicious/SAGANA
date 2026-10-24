// Email-domain check for registration.
//
// WHAT THIS PROVES, AND WHAT IT DOES NOT.
//   It asks public DNS whether the part of the address after the @ can receive
//   email at all (it publishes an MX record, or failing that an address
//   record). "someone@gmial.com" or "someone@no-such-domain.example" are caught.
//   It does NOT prove that the mailbox exists, and it cannot prove the address
//   belongs to the person typing it: only sending a code or a link to the
//   mailbox and having the person return it can do that. Registration here has
//   no email confirmation step by design, so a passing result means "this
//   domain can receive mail", nothing more.
//
//   Phone numbers have no equivalent public lookup. Whether a mobile number is
//   active, and whose it is, can only be confirmed by sending an SMS code
//   through a paid SMS provider. That is not part of this function.
//
// Request:  POST { "email": "name@example.com" }
// Response: { "status": "ok" | "no_mail_server" | "unknown", "domain": "example.com" }
//   ok             the domain publishes a mail server
//   no_mail_server the domain does not exist or cannot receive mail
//   unknown        the lookup itself failed; callers must not treat it as a "no"
//
// The lookup goes through Cloudflare's public DNS-over-HTTPS endpoint, so the
// function needs no DNS permission from the runtime.

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DOH = "https://cloudflare-dns.com/dns-query";
const TIMEOUT_MS = 4000;
const CACHE_TTL_MS = 60 * 60 * 1000;
const CACHE_MAX_ENTRIES = 500;

type Status = "ok" | "no_mail_server" | "unknown";
const cache = new Map<string, { status: Status; expires: number }>();

function json(status: number, payload: unknown): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// Letters, digits, hyphens and dots only (internationalised names arrive
// punycode-encoded). Anything else is refused before it reaches DNS.
const DOMAIN_RE = /^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/;

async function dns(name: string, type: "MX" | "A" | "AAAA"): Promise<{ status: number; answers: Array<{ type: number; data: string }> } | null> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(`${DOH}?name=${encodeURIComponent(name)}&type=${type}`, {
      headers: { accept: "application/dns-json" },
      signal: ctrl.signal,
    });
    if (!res.ok) return null;
    const body = await res.json();
    return { status: body.Status as number, answers: (body.Answer ?? []) as Array<{ type: number; data: string }> };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function check(domain: string): Promise<Status> {
  const mx = await dns(domain, "MX");
  if (mx === null) return "unknown";
  if (mx.status === 3) return "no_mail_server"; // NXDOMAIN: the domain does not exist
  if (mx.status !== 0) return "unknown"; // SERVFAIL etc.: not a verdict
  const mxRecords = mx.answers.filter((a) => a.type === 15);
  if (mxRecords.length > 0) {
    // A single "0 ." record is the explicit "this domain accepts no mail" marker.
    const onlyNull = mxRecords.every((a) => /^\s*0\s+\.?\s*$/.test(a.data));
    return onlyNull ? "no_mail_server" : "ok";
  }
  // No MX: mail can still be delivered to the domain's own address record.
  const a = await dns(domain, "A");
  const aaaa = await dns(domain, "AAAA");
  if (a === null && aaaa === null) return "unknown";
  const hasAddress = [a, aaaa].some((r) => r !== null && r.answers.some((x) => x.type === 1 || x.type === 28));
  return hasAddress ? "ok" : "no_mail_server";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  let email = "";
  try {
    const body = await req.json();
    email = String(body?.email ?? "").trim().toLowerCase();
  } catch {
    return json(400, { error: "Invalid request" });
  }

  const at = email.lastIndexOf("@");
  const domain = at > 0 ? email.slice(at + 1) : "";
  if (!DOMAIN_RE.test(domain)) return json(200, { status: "no_mail_server", domain });

  const hit = cache.get(domain);
  if (hit && hit.expires > Date.now()) return json(200, { status: hit.status, domain });

  const status = await check(domain);
  if (status !== "unknown") {
    if (cache.size >= CACHE_MAX_ENTRIES) cache.delete(cache.keys().next().value as string);
    cache.set(domain, { status, expires: Date.now() + CACHE_TTL_MS });
  }
  return json(200, { status, domain });
});
