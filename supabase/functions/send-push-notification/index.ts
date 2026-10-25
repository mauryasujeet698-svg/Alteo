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

function pemToDer(pem: string): ArrayBuffer {
  const normalized = pem.replace(/\\n/g, "\n");
  const base64 = normalized.replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function getGoogleAccessToken(serviceAccount: Record<string, unknown>): Promise<string> {
  const clientEmail = String(serviceAccount.client_email ?? "");
  const projectId = String(serviceAccount.project_id ?? "");
  const privateKey = String(serviceAccount.private_key ?? "");
  const tokenUri = String(serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token");
  if (!clientEmail || !projectId || !privateKey) {
    throw new Error("Firebase service-account JSON is missing required fields.");
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = base64Url(new TextEncoder().encode(JSON.stringify({
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: tokenUri,
    iat: now,
    exp: now + 3600,
  })));
  const unsigned = header + "." + claims;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  ));
  const assertion = unsigned + "." + base64Url(signature);

  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenData = await response.json();
  if (!response.ok || typeof tokenData.access_token !== "string") {
    throw new Error("Could not obtain a Firebase messaging access token.");
  }
  return tokenData.access_token;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "POST required." }, 405);

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Sign-in required." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Supabase function environment is incomplete." }, 500);
  }
  if (!serviceAccountJson) {
    return json({ error: "Firebase server credentials are not configured yet." }, 503);
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

  const targetUserId = typeof body.user_id === "string" ? body.user_id.trim() : "";
  const appId = typeof body.app_id === "string" ? body.app_id : "";
  const title = typeof body.title === "string" ? body.title.trim() : "";
  const messageBody = typeof body.body === "string" ? body.body.trim() : "";
  if (!/^[0-9a-fA-F-]{36}$/.test(targetUserId)) return json({ error: "A valid target user_id is required." }, 400);
  if (!allowedApps.has(appId)) return json({ error: "Unsupported app_id." }, 400);
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

  const { data: rows, error: tokenError } = await serviceClient
    .from("user_device_tokens")
    .select("token")
    .eq("user_id", targetUserId)
    .eq("app_id", appId);
  if (tokenError) return json({ error: "Could not find registered devices for this account." }, 500);
  if (!rows || rows.length === 0) return json({ sent: 0, message: "No registered devices for this user and app yet." }, 200);

  let account: Record<string, unknown>;
  try {
    account = JSON.parse(serviceAccountJson);
  } catch (_) {
    return json({ error: "FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON." }, 503);
  }

  try {
    const accessToken = await getGoogleAccessToken(account);
    const projectId = String(account.project_id ?? "");
    if (!projectId) throw new Error("Firebase project_id is missing.");
    let sent = 0;
    const failures: string[] = [];
    for (const row of rows) {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            message: {
              token: row.token,
              notification: { title, body: messageBody },
              data: dataPayload,
              android: { priority: "HIGH", notification: { channel_id: "alteo_updates" } },
            },
          }),
        },
      );
      if (response.ok) {
        sent++;
      } else {
        const fcmResponse = await response.text();
        failures.push(`FCM delivery failed (HTTP ${response.status}).`);
        console.error("FCM send failed:", response.status, fcmResponse.slice(0, 1000));
      }
    }
    return json({ sent, attempted: rows.length, failures });
  } catch (error) {
    console.error("Push notification send failed:", error);
    return json({ error: "Could not send push notification. Verify Firebase service-account permissions and project configuration." }, 502);
  }
});
