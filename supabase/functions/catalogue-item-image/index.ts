import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const escapeText = (value: string) => value.replace(/[&<>"']/g, " ").trim();

Deno.serve((req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { "Allow": "GET, HEAD" } });
  }
  const url = new URL(req.url);
  const name = escapeText((url.searchParams.get("name") ?? "Alteo essential").slice(0, 90));
  const category = escapeText((url.searchParams.get("category") ?? "Kitchen and Home").slice(0, 48));
  const sku = escapeText((url.searchParams.get("sku") ?? "ALT").slice(0, 24));
  const text = encodeURIComponent(name + "\\n" + category + "\\n" + sku);
  // Flutter Image.network supports PNG/JPEG, so use a cached PNG placeholder
  // with the product name and category rather than returning SVG bytes.
  const target = "https://placehold.co/640x640/F1F6F2/176B57.png?text=" + text;
  return new Response(null, {
    status: 302,
    headers: {
      "Location": target,
      "Cache-Control": "public, max-age=86400, stale-while-revalidate=604800",
    },
  });
});