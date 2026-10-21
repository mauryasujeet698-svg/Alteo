import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const toHex = (bytes: Uint8Array) => Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "Authentication required" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
  const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
  const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
  if (!url || !publicKey || !serviceRoleKey || !cloudName || !apiKey || !apiSecret) {
    return json({ error: "Server media configuration is incomplete" }, 503);
  }

  const caller = createClient(url, publicKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: "Invalid session" }, 401);

  let body: { assetKind?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const assetKind = body.assetKind;
  if (assetKind !== "profile" && assetKind !== "product" && assetKind !== "food_listing") {
    return json({ error: "Unsupported asset type" }, 400);
  }

  let folder: string;
  if (assetKind === "profile") {
    folder = "alteo/users/" + user.id + "/profile";
  } else {
    const { data: roles, error: rolesError } = await caller.from("user_roles")
      .select("role").eq("user_id", user.id).eq("role", "seller").limit(1);
    if (rolesError) return json({ error: "Unable to verify upload permission" }, 503);
    if (!roles || roles.length === 0) return json({ error: "Verified seller access is required" }, 403);
    const { data: sellers, error: sellerError } = await caller.from("sellers")
      .select("id").eq("owner_id", user.id).eq("status", "approved").limit(1);
    if (sellerError) return json({ error: "Unable to verify seller account" }, 503);
    if (!sellers || sellers.length === 0) return json({ error: "Seller approval is required before catalogue uploads" }, 403);
    folder = "alteo/sellers/" + sellers[0].id + "/catalogue";
  }

  // Atomic per-user quotas are enforced by a server-only RPC and a private table.
  const server = createClient(url, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: allowed, error: quotaError } = await server.rpc("consume_media_upload_quota", {
    p_user_id: user.id, p_max_hour: 20, p_max_day: 100,
  });
  if (quotaError) return json({ error: "Upload quota check is unavailable" }, 503);
  if (allowed !== true) return json({ error: "Upload limit reached. Try again later." }, 429);

  const timestamp = Math.floor(Date.now() / 1000);
  const allowedFormats = "jpg,png,webp";
  const params = "allowed_formats=" + allowedFormats + "&folder=" + folder + "&timestamp=" + timestamp;
  const digest = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(params + apiSecret));
  return json({ apiKey, timestamp, folder, assetKind, allowedFormats, signature: toHex(new Uint8Array(digest)) });
});
