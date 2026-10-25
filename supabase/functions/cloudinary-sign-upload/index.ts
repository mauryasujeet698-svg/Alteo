import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function toHex(bytes: ArrayBuffer) {
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "POST required." }, 405);

  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
  const cloudApiKey = Deno.env.get("CLOUDINARY_API_KEY");
  const cloudApiSecret = Deno.env.get("CLOUDINARY_API_SECRET");

  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: "Supabase function environment is incomplete." }, 500);
  }
  if (!cloudName || !cloudApiKey || !cloudApiSecret) {
    return json({ error: "Cloudinary secrets are not configured in Supabase Edge Function secrets." }, 503);
  }

  let body: Record<string, unknown> = {};
  try { body = await request.json() as Record<string, unknown>; } catch (_) {}
  const assetType = typeof body.asset_type === "string" ? body.asset_type : "banner";
  const uploadRules: Record<string, { folder: string; permittedRoles: string[] }> = {
    banner: { folder: "alteo/banners", permittedRoles: ["admin"] },
    product_image: { folder: "alteo/products", permittedRoles: ["admin", "seller"] },
    delivery_proof: { folder: "alteo/delivery-proof", permittedRoles: ["delivery_partner"] },
  };
  const rule = uploadRules[assetType];
  if (!rule) return json({ error: "Unsupported upload type." }, 400);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userResult, error: userError } = await userClient.auth.getUser();
  if (userError || !userResult.user) return json({ error: "Valid Google sign-in is required." }, 401);

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: roleRows, error: roleError } = await serviceClient
    .from("user_roles")
    .select("role")
    .eq("user_id", userResult.user.id)
    .in("role", rule.permittedRoles);

  if (roleError || !roleRows || roleRows.length === 0) {
    return json({ error: "This account is not allowed to upload this type of media." }, 403);
  }

  const timestamp = Math.floor(Date.now() / 1000);
  const mediaType = assetType === "delivery_proof" ? "authenticated" : "upload";
  const signedParams: Record<string, string> = {
    folder: rule.folder,
    timestamp: String(timestamp),
    type: mediaType,
  };

  // Delivery proof upload signatures are tied to one of the current user's in-transit jobs.
  // This prevents a delivery role from obtaining a proof signature for arbitrary media paths/jobs.
  if (assetType === "delivery_proof") {
    const deliveryJobId = typeof body.delivery_job_id === "string" ? body.delivery_job_id : "";
    if (!/^[0-9a-fA-F-]{36}$/.test(deliveryJobId)) {
      return json({ error: "A valid delivery_job_id is required for proof uploads." }, 400);
    }
    const { data: job, error: jobError } = await serviceClient
      .from("delivery_jobs")
      .select("id")
      .eq("id", deliveryJobId)
      .eq("delivery_partner_id", userResult.user.id)
      .eq("status", "in_transit")
      .maybeSingle();
    if (jobError || !job) {
      return json({ error: "Proof can only be uploaded for your own delivery that is currently in transit." }, 403);
    }
    signedParams.public_id = "alteo/delivery-proof/" + deliveryJobId + "_" + crypto.randomUUID();
  }

  // Cloudinary requires alphabetically sorted upload parameters with the API secret appended.
  const canonicalParams = Object.entries(signedParams)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => key + "=" + value)
    .join("&");
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(canonicalParams + cloudApiSecret),
  );
  const signature = toHex(digest);

  return json({
    cloud_name: cloudName,
    api_key: cloudApiKey,
    timestamp,
    folder: rule.folder,
    type: mediaType,
    ...(signedParams.public_id ? { public_id: signedParams.public_id } : {}),
    signature,
    asset_type: assetType,
  });
});
