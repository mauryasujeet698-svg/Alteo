import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const escapeXml = (value: string) =>
  value.replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&apos;",
  }[ch] ?? ch));

const palettes: Record<string, [string, string, string]> = {
  "Personal Care": ["#e6f5ee", "#176b57", "#a9dfc7"],
  "Home Cleaning": ["#e8f1fb", "#2563a6", "#a8c9ee"],
  "Stationery": ["#f5edf9", "#8051a7", "#d4b9e8"],
  "Electronics Accessories": ["#edf0f5", "#34445f", "#b9c5d6"],
  "Kitchen & Home": ["#fff2e5", "#a65c2a", "#f0c69f"],
};

function iconFor(category: string, tone: string, accent: string) {
  if (category === "Personal Care") return `
    <rect x="250" y="148" width="140" height="48" rx="18" fill="${tone}"/>
    <path d="M278 196h84v30h24v190q0 35-35 35h-62q-35 0-35-35V226h24z" fill="${tone}" stroke="${accent}" stroke-width="8"/>
    <rect x="270" y="275" width="104" height="105" rx="16" fill="#ffffff" opacity=".92"/>
    <path d="M300 170h40" stroke="#ffffff" stroke-width="10" stroke-linecap="round"/>
    <path d="M322 300c-26 18-28 41 0 58 28-17 26-40 0-58z" fill="${accent}"/>
  `;
  if (category === "Home Cleaning") return `
    <path d="M275 190h92v42h-92z" fill="${tone}"/>
    <path d="M300 190v-42h60l35 30-17 25" fill="${accent}" stroke="${tone}" stroke-width="8" stroke-linejoin="round"/>
    <path d="M270 230h102v198q0 28-28 28h-46q-28 0-28-28z" fill="${tone}" stroke="${accent}" stroke-width="8"/>
    <path d="M290 278h62v95h-62z" fill="#ffffff" opacity=".92"/>
    <path d="M315 300l-12 24h16l-7 27 26-35h-17l9-16z" fill="${accent}"/>
  `;
  if (category === "Stationery") return `
    <rect x="230" y="155" width="180" height="285" rx="20" fill="${tone}" stroke="${accent}" stroke-width="8"/>
    <path d="M272 155v285" stroke="${accent}" stroke-width="8"/>
    <path d="M292 220h94M292 258h94M292 296h94M292 334h72" stroke="#ffffff" stroke-width="10" stroke-linecap="round"/>
    <circle cx="250" cy="210" r="6" fill="#ffffff"/><circle cx="250" cy="250" r="6" fill="#ffffff"/><circle cx="250" cy="290" r="6" fill="#ffffff"/>
  `;
  if (category === "Electronics Accessories") return `
    <rect x="245" y="150" width="150" height="278" rx="28" fill="${tone}" stroke="${accent}" stroke-width="8"/>
    <rect x="270" y="190" width="100" height="145" rx="14" fill="#ffffff" opacity=".94"/>
    <path d="M292 365h56" stroke="${accent}" stroke-width="10" stroke-linecap="round"/>
    <path d="M295 125v25m50-25v25" stroke="${tone}" stroke-width="12" stroke-linecap="round"/>
    <path d="M315 245l-15 28h20l-8 26 30-38h-20l9-16z" fill="${accent}"/>
  `;
  return `
    <path d="M240 225q0-30 30-30h120q30 0 30 30v175q0 30-30 30H270q-30 0-30-30z" fill="${tone}" stroke="${accent}" stroke-width="8"/>
    <path d="M258 248h144v115H258z" fill="#ffffff" opacity=".9"/>
    <path d="M285 195v-34h90v34" fill="none" stroke="${accent}" stroke-width="12" stroke-linecap="round"/>
    <path d="M280 300h100M280 330h72" stroke="${tone}" stroke-width="9" stroke-linecap="round"/>
  `;
}

Deno.serve((req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", { status: 405, headers: { "Allow": "GET, HEAD" } });
  }
  const url = new URL(req.url);
  const name = escapeXml((url.searchParams.get("name") ?? "Alteo essential").slice(0, 90));
  const category = url.searchParams.get("category") ?? "Kitchen & Home";
  const sku = escapeXml((url.searchParams.get("sku") ?? "ALT").slice(0, 32));
  const [background, tone, accent] = palettes[category] ?? palettes["Kitchen & Home"];
  const icon = iconFor(category, tone, accent);
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="640" viewBox="0 0 640 640" role="img" aria-label="${name}">
    <defs>
      <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#ffffff"/><stop offset="1" stop-color="${background}"/></linearGradient>
      <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="18" stdDeviation="18" flood-color="#18382d" flood-opacity=".13"/></filter>
    </defs>
    <rect width="640" height="640" fill="url(#bg)"/>
    <circle cx="320" cy="285" r="205" fill="#ffffff" opacity=".65"/>
    <g filter="url(#shadow)"><ellipse cx="320" cy="470" rx="152" ry="22" fill="#123d30" opacity=".12"/>${icon}</g>
    <text x="320" y="530" text-anchor="middle" font-family="Arial, sans-serif" font-size="26" font-weight="700" fill="#173d31">${name}</text>
    <text x="320" y="570" text-anchor="middle" font-family="Arial, sans-serif" font-size="15" letter-spacing="2" fill="#63776d">${escapeXml(category.toUpperCase())}</text>
    <text x="320" y="606" text-anchor="middle" font-family="Arial, sans-serif" font-size="13" fill="#809087">${sku}</text>
  </svg>`;
  return new Response(req.method === "HEAD" ? null : svg, {
    status: 200,
    headers: {
      "Content-Type": "image/svg+xml; charset=utf-8",
      "Cache-Control": "public, max-age=86400, stale-while-revalidate=604800",
      "Access-Control-Allow-Origin": "*",
      "X-Content-Type-Options": "nosniff",
    },
  });
});