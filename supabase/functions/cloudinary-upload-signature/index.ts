import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
const toHex = (bytes: Uint8Array) =>
  Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "Authentication required" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
  const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
  const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
  if (!url || !anonKey || !cloudName || !apiKey || !apiSecret) {
    return json({ error: "Server media configuration is incomplete" }, 500);
  }

  const supabase = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) return json({ error: "Invalid session" }, 401);

  let body: { folder?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const requested = typeof body.folder === "string" ? body.folder : "profile";
  const safe = requested.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 32) || "profile";
  const folder = `alteo/users/${user.id}/${safe}`;
  const timestamp = Math.floor(Date.now() / 1000);
  const params = `folder=${folder}&timestamp=${timestamp}`;
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(params + apiSecret),
  );

  return json({
    apiKey,
    timestamp,
    folder,
    signature: toHex(new Uint8Array(digest)),
  });
});
