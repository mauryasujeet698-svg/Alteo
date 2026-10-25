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

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userResult, error: userError } = await userClient.auth.getUser();
  if (userError || !userResult.user) return json({ error: "Valid Google sign-in is required." }, 401);

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: adminRole, error: roleError } = await serviceClient
    .from("user_roles")
    .select("role")
    .eq("user_id", userResult.user.id)
    .eq("role", "admin")
    .maybeSingle();

  if (roleError || !adminRole) return json({ error: "Only an approved Alteo Admin can upload banner images." }, 403);

  // Fixed folder and narrowly scoped fields: clients cannot request arbitrary signed Cloudinary operations.
  const folder = "alteo/banners";
  const timestamp = Math.floor(Date.now() / 1000);
  const canonicalParams = "folder=" + folder + "&timestamp=" + timestamp;
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(canonicalParams + cloudApiSecret),
  );
  const signature = toHex(digest);

  return json({
    cloud_name: cloudName,
    api_key: cloudApiKey,
    timestamp,
    folder,
    signature,
  });
});
