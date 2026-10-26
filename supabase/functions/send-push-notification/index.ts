import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

const allowedApps = new Set([
  "customer", "admin", "seller", "driver_partner", "delivery_partner", "dark_store",
]);

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

const GCP_PROJECT_ID = "alteo-512709";
const GCP_PROJECT_NUMBER = "718705771727";
const WIF_POOL_ID = "alteo-supabase-pool";
const WIF_PROVIDER_ID = "supabase-edge-oidc";
const SERVICE_ACCOUNT_EMAIL = "alteo-fcm-sender@alteo-512709.iam.gserviceaccount.com";
const WIF_ISSUER =
  "https://nkerkoptbrcadlpxffkn.supabase.co/functions/v1/send-push-notification";
const WIF_SUBJECT = "alteo-supabase-edge-fcm";
const WIF_PROVIDER_RESOURCE =
  "//iam.googleapis.com/projects/" + GCP_PROJECT_NUMBER +
  "/locations/global/workloadIdentityPools/" + WIF_POOL_ID +
  "/providers/" + WIF_PROVIDER_ID;

const encoder = new TextEncoder();
let cachedFcmAccessToken: { token: string; expiresAt: number } | null = null;

function makeJwtPart(value: Record<string, unknown>): string {
  return base64Url(encoder.encode(JSON.stringify(value)));
}

async function signWorkloadAssertion(privateJwkJson: string): Promise<string> {
  let jwk: JsonWebKey & { kid?: string; alg?: string };
  try {
    jwk = JSON.parse(privateJwkJson) as JsonWebKey & { kid?: string; alg?: string };
  } catch {
    throw new Error("GCP_WIF_PRIVATE_JWK is not valid JSON.");
  }

  if (jwk.kty !== "RSA" || !jwk.d || !jwk.n || !jwk.e || !jwk.kid) {
    throw new Error("GCP_WIF_PRIVATE_JWK must be the private RSA JWK with its matching kid.");
  }

  const now = Math.floor(Date.now() / 1000);
  const unsigned = makeJwtPart({
    alg: "RS256",
    typ: "JWT",
    kid: jwk.kid,
  }) + "." + makeJwtPart({
    iss: WIF_ISSUER,
    sub: WIF_SUBJECT,
    aud: WIF_PROVIDER_RESOURCE,
    iat: now,
    exp: now + 300,
  });

  const signingKey = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    signingKey,
    encoder.encode(unsigned),
  ));
  return unsigned + "." + base64Url(signature);
}

async function getGoogleFcmAccessToken(): Promise<string> {
  const nowMs = Date.now();
  if (cachedFcmAccessToken && cachedFcmAccessToken.expiresAt > nowMs + 60_000) {
    return cachedFcmAccessToken.token;
  }

  const privateJwkJson = Deno.env.get("GCP_WIF_PRIVATE_JWK");
  if (!privateJwkJson) {
    throw new Error("Missing GCP_WIF_PRIVATE_JWK Edge Function secret.");
  }

  const assertion = await signWorkloadAssertion(privateJwkJson);
  const stsResponse = await fetch("https://sts.googleapis.com/v1/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:token-exchange",
      audience: WIF_PROVIDER_RESOURCE,
      scope: "https://www.googleapis.com/auth/cloud-platform",
      requested_token_type: "urn:ietf:params:oauth:token-type:access_token",
      subject_token_type: "urn:ietf:params:oauth:token-type:jwt",
      subject_token: assertion,
    }),
  });

  const stsData = await stsResponse.json().catch(() => ({}));
  if (!stsResponse.ok || typeof stsData.access_token !== "string") {
    console.error("Google STS token exchange failed", {
      status: stsResponse.status,
      error: typeof stsData.error === "string" ? stsData.error : "unknown_error",
    });
    throw new Error("Google STS token exchange failed.");
  }

  const impersonationUrl =
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/" +
    encodeURIComponent(SERVICE_ACCOUNT_EMAIL) + ":generateAccessToken";
  const impersonationResponse = await fetch(impersonationUrl, {
    method: "POST",
    headers: {
      Authorization: "Bearer " + stsData.access_token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      scope: ["https://www.googleapis.com/auth/firebase.messaging"],
      lifetime: "3600s",
    }),
  });

  const impersonationData = await impersonationResponse.json().catch(() => ({}));
  if (
    !impersonationResponse.ok ||
    typeof impersonationData.accessToken !== "string"
  ) {
    console.error("Google service-account impersonation failed", {
      status: impersonationResponse.status,
      error: impersonationData.error?.status ?? "unknown_error",
    });
    throw new Error("Google service-account impersonation failed.");
  }

  const expiry = typeof impersonationData.expireTime === "string"
    ? Date.parse(impersonationData.expireTime)
    : nowMs + 50 * 60 * 1000;
  cachedFcmAccessToken = {
    token: impersonationData.accessToken,
    expiresAt: Number.isFinite(expiry) ? expiry : nowMs + 50 * 60 * 1000,
  };
  return cachedFcmAccessToken.token;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "POST required." }, 405);

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Sign-in required." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Supabase function environment is incomplete." }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userResult, error: userError } = await userClient.auth.getUser();
  if (userError || !userResult.user) return json({ error: "Valid sign-in is required." }, 401);

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: roles, error: roleError } = await serviceClient
    .from("user_roles")
    .select("role")
    .eq("user_id", userResult.user.id)
    .eq("role", "admin")
    .limit(1);
  if (roleError || !roles || roles.length === 0) {
    return json({ error: "Administrator role is required to send a test notification." }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: "A JSON request body is required." }, 400);
  }

  const audience = typeof body.audience === "string" ? body.audience : "specific_user";
  const targetUserId = typeof body.user_id === "string" ? body.user_id.trim() : "";
  const appId = typeof body.app_id === "string" ? body.app_id : "";
  const title = typeof body.title === "string" ? body.title.trim() : "";
  const messageBody = typeof body.body === "string" ? body.body.trim() : "";
  if (!allowedApps.has(appId)) return json({ error: "Unsupported app_id." }, 400);
  if (!["all_customers", "specific_user"].includes(audience)) {
    return json({ error: "Unsupported notification audience." }, 400);
  }
  if (audience === "all_customers" && appId !== "customer") {
    return json({ error: "Broadcast notifications are currently limited to customer apps." }, 400);
  }
  if (audience === "specific_user" && !/^[0-9a-fA-F-]{36}$/.test(targetUserId)) {
    return json({ error: "A valid target user_id is required." }, 400);
  }
  if (!title || title.length > 100 || !messageBody || messageBody.length > 1000) {
    return json({ error: "Title (max 100 chars) and body (max 1000 chars) are required." }, 400);
  }

  const dataPayload: Record<string, string> = {};
  if (body.data && typeof body.data === "object" && !Array.isArray(body.data)) {
    for (const [key, value] of Object.entries(body.data as Record<string, unknown>).slice(0, 30)) {
      if (/^[a-zA-Z][a-zA-Z0-9_]{0,39}$/.test(key) && !["from", "message_type", "google"].includes(key)) {
        dataPayload[key] = String(value).slice(0, 500);
      }
    }
  }

  let tokens: string[] = [];
  if (audience === "specific_user") {
    const { data: rows, error: tokenError } = await serviceClient
      .from("user_device_tokens")
      .select("token")
      .eq("user_id", targetUserId)
      .eq("app_id", appId);
    if (tokenError) return json({ error: "Could not find registered devices for this account." }, 500);
    tokens = (rows ?? []).map((row) => String(row.token ?? "")).filter(Boolean);
    if (tokens.length === 0) {
      return json({ sent: 0, attempted: 0, message: "No registered devices for this user and app yet. Open the app, sign in and allow notifications first." }, 200);
    }
  }

  try {
    const accessToken = await getGoogleFcmAccessToken();
    const projectId = GCP_PROJECT_ID;
    let sent = 0;
    const failures: string[] = [];
    // A notification payload is shown by Android's FCM SDK in the system tray
    // when the app is backgrounded or terminated (unless force-stopped/blocked).
    const destinations: Array<{ token?: string; topic?: string }> =
      audience === "all_customers"
        ? [{ topic: "alteo_customers" }]
        : tokens.map((token) => ({ token }));

    for (let offset = 0; offset < destinations.length; offset += 20) {
      const batch = destinations.slice(offset, offset + 20);
      const results = await Promise.all(batch.map(async (destination) => {
        const response = await fetch(
          `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
          {
            method: "POST",
            headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              message: {
                ...destination,
                notification: { title, body: messageBody },
                data: dataPayload,
                android: { priority: "HIGH", notification: { channel_id: "alteo_updates" } },
              },
            }),
          },
        );
        if (response.ok) return true;
        const fcmResponse = await response.text();
        failures.push(`FCM delivery failed (HTTP ${response.status}).`);
        console.error("FCM send failed:", response.status, fcmResponse.slice(0, 1000));
        return false;
      }));
      sent += results.filter(Boolean).length;
    }
    return json({
      sent,
      attempted: destinations.length,
      audience,
      app_id: appId,
      delivery: audience === "all_customers" ? "submitted_to_customer_topic" : "submitted_to_registered_devices",
      failures,
    });
  } catch (error) {
    console.error("Push notification send failed:", error);
    return json({ error: "Could not send push notification. Verify the Workload Identity provider, impersonation grant, and Firebase Messaging permissions." }, 502);
  }
});
