// Supabase Edge Function: scan-invoice
// Uses Gemini 2.5 Flash to extract handwritten Egyptian plumbing/sanitary ware items
// and match them against the shop's catalog + learned technician aliases.

// TODO(security): Add distributed rate limiting (e.g. Upstash Redis or Postgres rate_limits table) before production rollout.

const MAX_IMAGES = 5;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024; // 5 MB
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOCAL_DEV_ORIGIN_REGEX =
  /^https?:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/i;

type MimeType = "image/jpeg" | "image/png" | "image/webp";

interface ScanRequestBody {
  images: string[];
  preferred_brand_id?: string | null;
}

interface ParsedAiItem {
  raw_ocr_text: string;
  item_template_id: string | null;
  brand_id: string | null;
  item_name: string;
  size: string | null;
  unit: string;
  quantity: number;
  confidence: "high" | "medium" | "low";
  notes?: string | null;
}

function getSecurityHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };

  if (origin && isAllowedOrigin(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    headers["Access-Control-Allow-Headers"] =
      "authorization, x-client-info, apikey, content-type";
  }
  return headers;
}

function isAllowedOrigin(origin: string): boolean {
  const configured = Deno.env.get("ALLOWED_ORIGINS") ?? "";
  const allowedList = configured
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && s !== "*");

  if (allowedList.length > 0) {
    return allowedList.includes(origin);
  }
  // Safe fallback for local development only (never wildcard '*').
  return LOCAL_DEV_ORIGIN_REGEX.test(origin);
}

function jsonResponse(
  status: number,
  payload: unknown,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: getSecurityHeaders(origin),
  });
}

function decodeBase64Image(raw: string): {
  base64Data: string;
  mimeType: MimeType;
} {
  let clean = raw.trim();
  const dataUriPrefix = /^data:image\/[a-zA-Z0-9+.-]+;base64,/;
  if (dataUriPrefix.test(clean)) {
    clean = clean.replace(dataUriPrefix, "");
  }
  clean = clean.replace(/\s+/g, "");

  if (clean.length === 0 || clean.length > 7_500_000) {
    throw new Error("Invalid image size");
  }

  const binary = atob(clean);
  if (binary.length === 0 || binary.length > MAX_IMAGE_BYTES) {
    throw new Error("Image exceeds 5MB limit");
  }

  const b = new Uint8Array(Math.min(binary.length, 16));
  for (let i = 0; i < b.length; i++) {
    b[i] = binary.charCodeAt(i);
  }

  // Magic bytes verification
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
    return { base64Data: clean, mimeType: "image/jpeg" };
  }
  if (
    b.length >= 8 &&
    b[0] === 0x89 &&
    b[1] === 0x50 &&
    b[2] === 0x4e &&
    b[3] === 0x47 &&
    b[4] === 0x0d &&
    b[5] === 0x0a &&
    b[6] === 0x1a &&
    b[7] === 0x0a
  ) {
    return { base64Data: clean, mimeType: "image/png" };
  }
  if (
    b.length >= 12 &&
    b[0] === 0x52 &&
    b[1] === 0x49 &&
    b[2] === 0x46 &&
    b[3] === 0x46 &&
    b[8] === 0x57 &&
    b[9] === 0x45 &&
    b[10] === 0x42 &&
    b[11] === 0x50
  ) {
    return { base64Data: clean, mimeType: "image/webp" };
  }

  throw new Error("Unsupported image format");
}

async function fetchSupabaseJson(
  url: string,
  anonKey: string,
  bearerToken: string,
): Promise<Response> {
  return await fetch(url, {
    method: "GET",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${bearerToken}`,
      Accept: "application/json",
    },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") {
    if (origin && !isAllowedOrigin(origin)) {
      return new Response(null, { status: 403 });
    }
    return new Response(null, {
      status: 204,
      headers: getSecurityHeaders(origin),
    });
  }

  if (req.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" }, origin);
  }

  if (origin && !isAllowedOrigin(origin)) {
    return jsonResponse(403, { error: "Origin not allowed" }, origin);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");

  if (!supabaseUrl || !supabaseAnonKey || !geminiApiKey) {
    console.error("Missing required server configuration");
    return jsonResponse(500, { error: "Server configuration error" }, origin);
  }

  // 1. Authenticate caller via Supabase Auth JWT
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "Unauthorized" }, origin);
  }
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) {
    return jsonResponse(401, { error: "Unauthorized" }, origin);
  }

  const userRes = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: {
      apikey: supabaseAnonKey,
      Authorization: `Bearer ${token}`,
    },
  });

  if (!userRes.ok) {
    return jsonResponse(401, { error: "Unauthorized" }, origin);
  }
  const userJson = await userRes.json();
  const userId = typeof userJson?.id === "string" ? userJson.id : "";
  if (!UUID_REGEX.test(userId)) {
    return jsonResponse(401, { error: "Unauthorized" }, origin);
  }

  // Verify active profile (fail-closed)
  const profileRes = await fetchSupabaseJson(
    `${supabaseUrl}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=id,is_active`,
    supabaseAnonKey,
    token,
  );
  if (!profileRes.ok) {
    return jsonResponse(403, { error: "Access denied" }, origin);
  }
  const profiles = await profileRes.json();
  if (!Array.isArray(profiles) || profiles.length === 0 || profiles[0]?.is_active !== true) {
    return jsonResponse(403, { error: "Account is inactive" }, origin);
  }

  // 2. Parse & validate request body
  let body: ScanRequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: "Invalid JSON payload" }, origin);
  }

  if (!Array.isArray(body?.images) || body.images.length === 0 || body.images.length > MAX_IMAGES) {
    return jsonResponse(
      400,
      { error: `Provide between 1 and ${MAX_IMAGES} images` },
      origin,
    );
  }

  const preferredBrandId =
    typeof body.preferred_brand_id === "string" && UUID_REGEX.test(body.preferred_brand_id)
      ? body.preferred_brand_id
      : null;

  const validatedImages: Array<{ base64Data: string; mimeType: MimeType }> = [];
  try {
    for (const img of body.images) {
      if (typeof img !== "string") {
        throw new Error("Invalid image entry");
      }
      validatedImages.push(decodeBase64Image(img));
    }
  } catch {
    return jsonResponse(
      400,
      { error: "Invalid image format or size (JPEG/PNG/WEBP up to 5MB)" },
      origin,
    );
  }

  // 3. Load shop catalog (protected by caller's RLS)
  const [templatesRes, brandsRes, aliasesRes] = await Promise.all([
    fetchSupabaseJson(
      `${supabaseUrl}/rest/v1/item_templates?select=id,name,size,unit,categories(name)`,
      supabaseAnonKey,
      token,
    ),
    fetchSupabaseJson(
      `${supabaseUrl}/rest/v1/brands?select=id,name,tier,is_default`,
      supabaseAnonKey,
      token,
    ),
    fetchSupabaseJson(
      `${supabaseUrl}/rest/v1/item_aliases?select=alias_text,item_template_id`,
      supabaseAnonKey,
      token,
    ),
  ]);

  if (!templatesRes.ok || !brandsRes.ok || !aliasesRes.ok) {
    console.error("Failed loading catalog tables for scan");
    return jsonResponse(500, { error: "Failed to load shop catalog" }, origin);
  }

  const [templates, brands, aliases] = await Promise.all([
    templatesRes.json(),
    brandsRes.json(),
    aliasesRes.json(),
  ]);

  // 4. Call Gemini 2.5 Flash via header auth (key never placed in URL)
  const systemInstruction = `أنت خبير تسعير أدوات صحية وسباكة في مصر.
مهمتك قراءة الكشف المكتوب بخط اليد (عربي أو إنجليزي أو خليط وأرقام عربية/إنجليزية) من الصور المرفقة، واستخراج كل بند ومطابقته مع كتالوج المحل وقاموس المسميات.
قواعد مهمة:
1. استخرج كل سطر كعنصر مستقل مع الكمية (quantity)، والاسم (item_name)، والمقاس (size) إن وُجد (مثل 1/2 بوصة، 3/4 بوصة، 4 بوصة).
2. إذا تطابق البند مع أحد أصناف الكتالوج أو قاموس المسميات (aliases)، ضع item_template_id الصحيح.
3. إذا ذُكرت الشركة/الماركة في الورقة، ضع brand_id المناسب من قائمة الشركات، وإلا اتركه null (أو استخدم preferred_brand_id إذا كان منطقياً).
4. حدد مستوى الثقة (confidence):
   - "high": الخط واضح والكمية والبند متطابقان تماماً مع الكتالوج.
   - "medium": البند مقروء لكنه غير محدد الماركة أو يوجد أكثر من احتمال أو المقاس غير مؤكد.
   - "low": الخط غير واضح أو الصنف غير موجود في الكتالوج.
أعد النتيجة بصيغة JSON فقط بدون أي نص إضافي.`;

  const catalogContext = JSON.stringify({
    preferred_brand_id: preferredBrandId,
    brands,
    item_templates: templates,
    aliases,
  });

  const parts: Array<Record<string, unknown>> = [
    {
      text: `كتالوج المحل وقاموس المسميات:\n${catalogContext}\n\nاقرأ الصور التالية واستخرج البنود:`,
    },
  ];
  for (const img of validatedImages) {
    parts.push({
      inlineData: {
        mimeType: img.mimeType,
        data: img.base64Data,
      },
    });
  }

  const geminiPayload = {
    systemInstruction: { parts: [{ text: systemInstruction }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      temperature: 0.1,
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          items: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                raw_ocr_text: { type: "STRING" },
                item_template_id: { type: "STRING", nullable: true },
                brand_id: { type: "STRING", nullable: true },
                item_name: { type: "STRING" },
                size: { type: "STRING", nullable: true },
                unit: { type: "STRING" },
                quantity: { type: "NUMBER" },
                confidence: {
                  type: "STRING",
                  enum: ["high", "medium", "low"],
                },
                notes: { type: "STRING", nullable: true },
              },
              required: [
                "raw_ocr_text",
                "item_name",
                "unit",
                "quantity",
                "confidence",
              ],
            },
          },
        },
        required: ["items"],
      },
    },
  };

  let geminiRes: Response;
  try {
    geminiRes = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": geminiApiKey,
        },
        body: JSON.stringify(geminiPayload),
      },
    );
  } catch {
    return jsonResponse(502, { error: "AI service unavailable" }, origin);
  }

  if (!geminiRes.ok) {
    console.error("Gemini API error status:", geminiRes.status);
    return jsonResponse(502, { error: "AI analysis failed" }, origin);
  }

  const geminiData = await geminiRes.json();
  const rawText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof rawText !== "string") {
    return jsonResponse(502, { error: "Empty AI response" }, origin);
  }

  let parsed: { items?: ParsedAiItem[] };
  try {
    parsed = JSON.parse(rawText);
  } catch {
    return jsonResponse(502, { error: "Malformed AI response" }, origin);
  }

  const safeItems = Array.isArray(parsed.items)
    ? parsed.items.map((item) => ({
      raw_ocr_text: String(item.raw_ocr_text ?? ""),
      item_template_id:
        typeof item.item_template_id === "string" &&
          UUID_REGEX.test(item.item_template_id)
          ? item.item_template_id
          : null,
      brand_id:
        typeof item.brand_id === "string" && UUID_REGEX.test(item.brand_id)
          ? item.brand_id
          : preferredBrandId,
      item_name: String(item.item_name ?? "").trim() || "صنف غير محدد",
      size: item.size ? String(item.size).trim() : null,
      unit: String(item.unit ?? "قطعة").trim() || "قطعة",
      quantity:
        typeof item.quantity === "number" && item.quantity > 0
          ? item.quantity
          : 1,
      confidence:
        item.confidence === "high" ||
          item.confidence === "medium" ||
          item.confidence === "low"
          ? item.confidence
          : "medium",
      notes: item.notes ? String(item.notes).trim() : null,
    }))
    : [];

  return jsonResponse(200, { items: safeItems }, origin);
});
