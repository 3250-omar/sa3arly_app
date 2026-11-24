declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const MAX_IMAGES = 5;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

const GEMINI_MODELS = [
  "gemini-3.8-flash",
  "gemini-3.5-flash",
  "gemini-3.5-flash-lite",
];
const GITHUB_WAVE_1 = ["openai/gpt-4.1-mini"];
const GITHUB_WAVE_2 = ["openai/gpt-4o-mini"];
const OPENROUTER_FALLBACK_MODELS = [
  "google/gemma-4-31b-it:free",
  "nvidia/nemotron-3.5-super-vl:free",
  "openrouter/free",
];

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOCAL_ORIGIN_RE =
  /^https?:\/\/(localhost|127\.0\.0\.1|192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(:\d{1,5})?$/i;

interface BrandRow {
  id: string;
  name: string;
  tier?: string;
  is_default?: boolean;
}

interface TemplateRow {
  id: string;
  name: string;
  size: string | null;
  unit: string | null;
}

interface AliasRow {
  alias_text: string;
  item_template_id: string;
}

interface ParsedAiResult {
  detected_brand_text?: unknown;
  detected_brand_id?: unknown;
  bid?: unknown;
  items?: Array<Record<string, unknown>>;
}

interface WaveResult {
  parsed: ParsedAiResult;
  modelUsed: string;
}

function isAllowedOrigin(origin: string): boolean {
  const raw = Deno.env.get("ALLOWED_ORIGINS") ?? "";
  const list = raw
    .split(",")
    .map((s) => s.trim())
    .filter((s) => s.length > 0 && s !== "*");
  return list.length > 0 ? list.includes(origin) : LOCAL_ORIGIN_RE.test(origin);
}

function secHeaders(origin: string | null): Record<string, string> {
  const h: Record<string, string> = {
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Cache-Control": "no-store",
    Vary: "Origin",
  };
  if (origin && isAllowedOrigin(origin)) {
    h["Access-Control-Allow-Origin"] = origin;
    h["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    h["Access-Control-Allow-Headers"] =
      "authorization, x-client-info, apikey, content-type";
  }
  return h;
}

function jsonRes(
  status: number,
  body: unknown,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: secHeaders(origin),
  });
}

function toWesternDigits(value: string): string {
  return value.replace(/[٠-٩]/g, (d) => String("٠١٢٣٤٥٦٧٨٩".indexOf(d)));
}

function normalizeAr(value: string): string {
  return toWesternDigits(value)
    .toLowerCase()
    .replace(/[أإآ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/ة/g, "ه")
    .replace(/[\u064B-\u065F\u0670]/g, "")
    .replace(/\brak\b/g, "راك")
    .replace(/راكثيرم/g, "راك ثيرم")
    .replace(/اكواثيرم|اكوا\s*ثيرم|aquatherm/g, "اكواثيرم")
    .replace(/بي\s*ار|بى\s*ار/g, "br")
    .replace(/(?:^|\s)(?:تيه|تي|ت)(?=\s|$)/g, " t ")
    .replace(/\b(?:انثي|نتايه)\b/g, "داخلي")
    .replace(/\b(?:دكر|خارجي)\b/g, "ذكر")
    .replace(/[^\p{L}\p{N}/×*.\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function stripLeadingQty(value: string): string {
  return toWesternDigits(value)
    .replace(
      /^\s*\d+(?:[.,]\d+)?(?!\s*\/)\s*(?:[x×*]|قطعه|قطعة|متر|عود|حبه|حبة|عدد)?\s*[-–:]?\s*/iu,
      "",
    )
    .trim();
}

function sizePartValue(part: string): number {
  if (part === "1/2") return 0.5;
  if (part === "3/4") return 0.75;
  const n = Number(part);
  return Number.isFinite(n) ? n : 999;
}

function normalizeSize(value: string | null | undefined): string {
  if (!value) return "";
  let s = toWesternDigits(value)
    .toLowerCase()
    .replace(/\([^)]*\)/g, " ")
    .replace(/[أإآ]/g, "ا")
    .replace(/ى/g, "ي")
    .replace(/ة/g, "ه")
    .replace(/[\u064B-\u065F\u0670]/g, "");

  s = s
    .replace(/بوصه\s*ونص|بوصة\s*ونص|1\s*و\s*1\/2|1\.5|1,5/g, " 1.5 ")
    .replace(
      /تلات\s*ت?ارباع|تلت\s*ارباع|ثلاث[هة]?\s*ارباع|25\s*(?:مم|mm)?/g,
      " 3/4 ",
    )
    .replace(/نص\s*بوصه|نصف\s*بوصه|\bنص\b|20\s*(?:مم|mm)?/g, " 1/2 ")
    .replace(/63\s*(?:مم|mm)?/g, " 2 ")
    .replace(/50\s*(?:مم|mm)?/g, " 1.5 ")
    .replace(/40\s*(?:مم|mm)?/g, " 1.25 ")
    .replace(/32\s*(?:مم|mm)?/g, " 1 ")
    .replace(/×|\*|\bفي\b/g, " x ")
    .replace(/بوصه|بوصة|inch|in|"|''/g, " ");

  const compound = s.match(
    /(1\/2|3\/4|1\.5|1\.25|1|2)\s*x\s*(1\/2|3\/4|1\.5|1\.25|1|2)/,
  );
  if (compound) {
    const parts = [compound[1], compound[2]].sort(
      (a, b) => sizePartValue(a) - sizePartValue(b),
    );
    return `${parts[0]}x${parts[1]}`;
  }

  const single = s.match(/(?:^|\s)(1\/2|3\/4|1\.5|1\.25|1|2)(?=\s|$)/);
  if (single) return single[1];
  if (/\bبوصه\b|\bبوصة\b/.test(value)) return "1";
  return "";
}

function matchBrandFromText(
  text: string | null | undefined,
  brands: BrandRow[],
): string | null {
  if (!text || !text.trim() || brands.length === 0) return null;
  const normText = normalizeAr(text);
  if (!normText) return null;
  const compactText = normText.replace(/\s+/g, "");

  let bestId: string | null = null;
  let bestLen = 0;
  for (const b of brands) {
    if (!UUID_RE.test(b.id) || !b.name) continue;
    const normBrand = normalizeAr(b.name);
    if (!normBrand) continue;
    const compactBrand = normBrand.replace(/\s+/g, "");
    if (
      normText.includes(normBrand) ||
      compactText.includes(compactBrand) ||
      (compactText.length >= 2 && compactBrand.includes(compactText))
    ) {
      if (compactBrand.length > bestLen) {
        bestId = b.id;
        bestLen = compactBrand.length;
      }
    }
  }
  return bestId;
}

function parseQuantity(raw: unknown): number {
  if (typeof raw === "number" && Number.isFinite(raw) && raw > 0) return raw;
  if (typeof raw === "string") {
    const n = Number(toWesternDigits(raw).replace(/[^\d.]/g, ""));
    if (Number.isFinite(n) && n > 0) return n;
  }
  return 1;
}

function parseImage(raw: string): { data: string; mime: string } {
  const clean = raw
    .trim()
    .replace(/^data:image\/[a-zA-Z0-9+.-]+;base64,/, "")
    .replace(/\s+/g, "");
  if (!clean || clean.length > 7500000) throw new Error("size");
  const bin = atob(clean);
  if (!bin.length || bin.length > MAX_IMAGE_BYTES) throw new Error("size");
  const b = new Uint8Array(Math.min(bin.length, 16));
  for (let i = 0; i < b.length; i++) b[i] = bin.charCodeAt(i);
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) {
    return { data: clean, mime: "image/jpeg" };
  }
  if (
    b.length >= 8 &&
    b[0] === 0x89 &&
    b[1] === 0x50 &&
    b[2] === 0x4e &&
    b[3] === 0x47
  ) {
    return { data: clean, mime: "image/png" };
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
    return { data: clean, mime: "image/webp" };
  }
  throw new Error("mime");
}

function sbGet(url: string, key: string, token: string): Promise<Response> {
  return fetch(url, {
    headers: {
      apikey: key,
      Authorization: "Bearer " + token,
      Accept: "application/json",
    },
  });
}

function parseAiJson(rawText: string): ParsedAiResult | null {
  const cleaned = rawText
    .trim()
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/```$/i, "")
    .trim();
  const tryParse = (s: string): ParsedAiResult | null => {
    try {
      const obj = JSON.parse(s) as ParsedAiResult;
      if (obj && typeof obj === "object" && Array.isArray(obj.items)) {
        return obj;
      }
    } catch {
      // Ignore parse error
    }
    return null;
  };
  const direct = tryParse(cleaned);
  if (direct) return direct;
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return tryParse(cleaned.slice(start, end + 1));
  }
  return null;
}

async function fetchJsonWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
  externalSignal?: AbortSignal,
): Promise<{ status: number; ok: boolean; body: unknown }> {
  const ctrl = new AbortController();
  const onExternalAbort = () => ctrl.abort();
  if (externalSignal) {
    if (externalSignal.aborted) {
      ctrl.abort();
    } else {
      externalSignal.addEventListener("abort", onExternalAbort, { once: true });
    }
  }
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { ...init, signal: ctrl.signal });
    const text = await res.text();
    let body: unknown = null;
    if (text.length > 0) {
      try {
        body = JSON.parse(text);
      } catch {
        body = { rawText: text };
      }
    }
    return { status: res.status, ok: res.ok, body };
  } finally {
    clearTimeout(timer);
    externalSignal?.removeEventListener("abort", onExternalAbort);
  }
}

function extractErrMsg(body: unknown, status: number): string {
  if (body && typeof body === "object") {
    const err = (body as { error?: { message?: unknown } }).error;
    if (typeof err?.message === "string" && err.message.length > 0) {
      return err.message.slice(0, 200);
    }
  }
  return "HTTP " + status;
}

async function attemptGemini(
  model: string,
  geminiKey: string,
  gemPayload: Record<string, unknown>,
  gemPayloadNoThinking: Record<string, unknown>,
  timeoutMs: number,
  signal: AbortSignal,
): Promise<WaveResult> {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;
  const headers = {
    "Content-Type": "application/json",
    "x-goog-api-key": geminiKey,
  };
  let res = await fetchJsonWithTimeout(
    url,
    { method: "POST", headers, body: JSON.stringify(gemPayload) },
    timeoutMs,
    signal,
  );
  if (res.status === 400) {
    res = await fetchJsonWithTimeout(
      url,
      { method: "POST", headers, body: JSON.stringify(gemPayloadNoThinking) },
      timeoutMs,
      signal,
    );
  }
  if (!res.ok) {
    const msg = extractErrMsg(res.body, res.status);
    console.error(`Gemini error on ${model}: ${res.status} ${msg}`);
    throw Object.assign(new Error(msg), { status: res.status });
  }
  const data = res.body as {
    candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
  };
  const txt = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof txt !== "string" || !txt.trim()) {
    throw Object.assign(new Error("Empty Gemini response"), { status: 502 });
  }
  const parsed = parseAiJson(txt);
  if (!parsed) {
    throw Object.assign(new Error("Malformed Gemini JSON"), { status: 502 });
  }
  return { parsed, modelUsed: model };
}

async function attemptOpenAiCompatible(
  providerName: string,
  endpoint: string,
  apiKey: string,
  model: string,
  prompt: string,
  ctx: string,
  imgs: Array<{ data: string; mime: string }>,
  timeoutMs: number,
  signal: AbortSignal,
  opts?: {
    includeDetailHigh?: boolean;
    extraBody?: Record<string, unknown>;
    extraHeaders?: Record<string, string>;
  },
): Promise<WaveResult> {
  const userContent: Array<Record<string, unknown>> = [
    {
      type: "text",
      text: "كتالوج المحل:\n" + ctx + "\n\nاقرأ الصور واستخرج البنود:",
    },
    ...imgs.map((img) => ({
      type: "image_url",
      image_url: opts?.includeDetailHigh
        ? { url: `data:${img.mime};base64,${img.data}`, detail: "high" }
        : { url: `data:${img.mime};base64,${img.data}` },
    })),
  ];

  const basePayload: Record<string, unknown> = {
    model,
    temperature: 0.1,
    max_tokens: 2048,
    messages: [
      { role: "system", content: prompt },
      { role: "user", content: userContent },
    ],
  };
  const headers = {
    "Content-Type": "application/json",
    Authorization: "Bearer " + apiKey,
    ...(opts?.extraHeaders ?? {}),
  };

  let res = await fetchJsonWithTimeout(
    endpoint,
    {
      method: "POST",
      headers,
      body: JSON.stringify({
        ...basePayload,
        response_format: { type: "json_object" },
        ...(opts?.extraBody ?? {}),
      }),
    },
    timeoutMs,
    signal,
  );
  if (res.status === 400) {
    res = await fetchJsonWithTimeout(
      endpoint,
      { method: "POST", headers, body: JSON.stringify(basePayload) },
      timeoutMs,
      signal,
    );
  }
  if (!res.ok) {
    const msg = extractErrMsg(res.body, res.status);
    console.error(`${providerName} error on ${model}: ${res.status} ${msg}`);
    throw Object.assign(new Error(msg), { status: res.status });
  }
  const data = res.body as {
    choices?: Array<{ message?: { content?: string } }>;
  };
  const txt = data?.choices?.[0]?.message?.content;
  if (typeof txt !== "string" || !txt.trim()) {
    throw Object.assign(new Error(`Empty ${providerName} response`), {
      status: 502,
    });
  }
  const parsed = parseAiJson(txt);
  if (!parsed) {
    throw Object.assign(new Error(`Malformed ${providerName} JSON`), {
      status: 502,
    });
  }
  return { parsed, modelUsed: model };
}

async function raceAttempts(
  factories: Array<(signal: AbortSignal) => Promise<WaveResult>>,
): Promise<{
  winner: WaveResult | null;
  lastStatus: number;
  lastDetail: string;
}> {
  if (factories.length === 0) {
    return {
      winner: null,
      lastStatus: 503,
      lastDetail: "No models configured",
    };
  }
  const ctrl = new AbortController();
  let lastStatus = 503;
  let lastDetail = "AI service temporarily busy";

  try {
    const winner = await Promise.any(
      factories.map((fn) =>
        fn(ctrl.signal).catch((err) => {
          if (err && typeof err === "object") {
            const st = (err as { status?: unknown }).status;
            const msg = (err as { message?: unknown }).message;
            if (typeof st === "number") lastStatus = st;
            if (typeof msg === "string" && msg.length > 0) lastDetail = msg;
          }
          throw err;
        }),
      ),
    );
    ctrl.abort();
    return { winner, lastStatus: 200, lastDetail: "" };
  } catch {
    ctrl.abort();
    return { winner: null, lastStatus, lastDetail };
  }
}

function buildCompactCatalog(
  brands: BrandRow[],
  templates: TemplateRow[],
  aliases: AliasRow[],
  preferredBrandId: string | null,
) {
  const idxToBrandId = new Map<number, string>();
  const brandIdSet = new Set<string>();
  const ctxLines: string[] = [];

  if (preferredBrandId) {
    const idx = brands.findIndex((b) => b.id === preferredBrandId);
    ctxLines.push(
      idx >= 0
        ? `الماركة المفضلة: ${idx + 1}`
        : `الماركة المفضلة: ${preferredBrandId}`,
    );
  }

  if (brands.length > 0) {
    ctxLines.push("الماركات (bid|name):");
    brands.forEach((b, i) => {
      const bid = i + 1;
      idxToBrandId.set(bid, b.id);
      brandIdSet.add(b.id);
      ctxLines.push(`${bid}|${b.name}${b.is_default ? "|default" : ""}`);
    });
  }

  const idxToTemplateId = new Map<number, string>();
  const templateById = new Map<string, TemplateRow>();
  const templatesByName = new Map<string, TemplateRow[]>();
  const templateIdToIdx = new Map<string, number>();

  if (templates.length > 0) {
    ctxLines.push("الأصناف مجمعة (tid=المقاس):");
    templates.forEach((t, i) => {
      const tid = i + 1;
      idxToTemplateId.set(tid, t.id);
      templateIdToIdx.set(t.id, tid);
      templateById.set(t.id, t);
      const list = templatesByName.get(t.name) ?? [];
      list.push(t);
      templatesByName.set(t.name, list);
    });

    for (const [name, group] of templatesByName.entries()) {
      const parts = group.map((t) => {
        const tid = templateIdToIdx.get(t.id)!;
        const unitSuffix = t.unit && t.unit !== "قطعة" ? `(${t.unit})` : "";
        return `${tid}=${t.size ?? "عادي"}${unitSuffix}`;
      });
      ctxLines.push(`${name}: ${parts.join(" | ")}`);
    }
  }

  if (aliases.length > 0) {
    ctxLines.push("المسميات (alias=>tid):");
    for (const a of aliases) {
      const tid = templateIdToIdx.get(a.item_template_id);
      const cleanedAlias = stripLeadingQty(a.alias_text);
      if (tid && cleanedAlias) {
        ctxLines.push(`${cleanedAlias}=>${tid}`);
      }
    }
  }

  return {
    ctx: ctxLines.join("\n"),
    idxToBrandId,
    brandIdSet,
    idxToTemplateId,
    templateById,
    templatesByName,
  };
}

function resolveIntOrUuid(
  val: unknown,
  idxMap: Map<number, string>,
  validUuidSet: Set<string>,
): string | null {
  if (typeof val === "number" && Number.isInteger(val)) {
    return idxMap.get(val) ?? null;
  }
  if (typeof val === "string") {
    const trimmed = val.trim();
    if (/^\d+$/.test(trimmed)) {
      return idxMap.get(Number(trimmed)) ?? null;
    }
    if (UUID_RE.test(trimmed) && validUuidSet.has(trimmed)) {
      return trimmed;
    }
  }
  return null;
}

Deno.serve(async (req: Request): Promise<Response> => {
  const startedAt = Date.now();
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") {
    if (origin && !isAllowedOrigin(origin)) {
      return new Response(null, { status: 403 });
    }
    return new Response(null, { status: 204, headers: secHeaders(origin) });
  }
  if (req.method !== "POST") {
    return jsonRes(405, { error: "Method not allowed" }, origin);
  }
  if (origin && !isAllowedOrigin(origin)) {
    return jsonRes(403, { error: "Origin not allowed" }, origin);
  }

  const sbUrl = Deno.env.get("SUPABASE_URL");
  const sbKey = Deno.env.get("SUPABASE_ANON_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  const githubToken = Deno.env.get("GITHUB_TOKEN");
  const openRouterKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!sbUrl || !sbKey || (!geminiKey && !githubToken && !openRouterKey)) {
    console.error("Missing required env vars");
    return jsonRes(500, { error: "Server configuration error" }, origin);
  }

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return jsonRes(401, { error: "Unauthorized" }, origin);
  }
  const token = auth.slice(7).trim();
  if (!token) return jsonRes(401, { error: "Unauthorized" }, origin);

  const [bodyRaw, userRes, tplR, brR, alR] = await Promise.all([
    req.json().catch(() => null),
    fetch(sbUrl + "/auth/v1/user", {
      headers: { apikey: sbKey, Authorization: "Bearer " + token },
    }),
    sbGet(
      sbUrl + "/rest/v1/item_templates?select=id,name,size,unit&order=name.asc",
      sbKey,
      token,
    ),
    sbGet(
      sbUrl + "/rest/v1/brands?select=id,name,tier,is_default&order=name.asc",
      sbKey,
      token,
    ),
    sbGet(
      sbUrl + "/rest/v1/item_aliases?select=alias_text,item_template_id",
      sbKey,
      token,
    ),
  ]);

  if (!userRes.ok) return jsonRes(401, { error: "Unauthorized" }, origin);
  const userJson = await userRes.json();
  const userId = typeof userJson?.id === "string" ? userJson.id : "";
  if (!UUID_RE.test(userId)) {
    return jsonRes(401, { error: "Unauthorized" }, origin);
  }

  const profRes = await sbGet(
    sbUrl +
      "/rest/v1/profiles?id=eq." +
      encodeURIComponent(userId) +
      "&select=id,is_active",
    sbKey,
    token,
  );
  if (!profRes.ok) return jsonRes(403, { error: "Access denied" }, origin);
  const profiles = await profRes.json();
  if (!Array.isArray(profiles) || !profiles[0]?.is_active) {
    return jsonRes(403, { error: "Account is inactive" }, origin);
  }

  const body = bodyRaw as {
    images?: unknown;
    preferred_brand_id?: unknown;
  } | null;
  if (!body) return jsonRes(400, { error: "Invalid JSON" }, origin);
  if (
    !Array.isArray(body.images) ||
    body.images.length === 0 ||
    body.images.length > MAX_IMAGES
  ) {
    return jsonRes(400, { error: "Provide 1 to 5 images" }, origin);
  }

  const preferredBrandId =
    typeof body.preferred_brand_id === "string" &&
    UUID_RE.test(body.preferred_brand_id)
      ? body.preferred_brand_id
      : null;

  const imgs: Array<{ data: string; mime: string }> = [];
  try {
    for (const raw of body.images) {
      if (typeof raw !== "string") throw new Error("type");
      imgs.push(parseImage(raw));
    }
  } catch {
    return jsonRes(
      400,
      { error: "Invalid image format or size (JPEG/PNG/WEBP <= 5MB)" },
      origin,
    );
  }

  if (!tplR.ok || !brR.ok || !alR.ok) {
    return jsonRes(500, { error: "Failed to load catalog" }, origin);
  }
  const [templatesRaw, brandsRaw, aliasesRaw] = await Promise.all([
    tplR.json(),
    brR.json(),
    alR.json(),
  ]);

  const brands = Array.isArray(brandsRaw) ? (brandsRaw as BrandRow[]) : [];
  const templates = Array.isArray(templatesRaw)
    ? (templatesRaw as TemplateRow[])
    : [];
  const aliases = Array.isArray(aliasesRaw) ? (aliasesRaw as AliasRow[]) : [];

  const catalog = buildCompactCatalog(
    brands,
    templates,
    aliases,
    preferredBrandId,
  );

  const prompt = [
    "أنت خبير تسعير أدوات صحية وسباكة في مصر.",
    "اقرأ الورقة المكتوبة بخط اليد في الصور المرفقة وطابق كل بند بدقة مع الكتالوج المرفق باستخدام الأرقام المختصرة (tid للصنف، bid للماركة).",
    "قواعد الماركة:",
    "- اقرأ اسم الشركة من رأس الورقة أو بجانب البنود (راك/RAK/راكثيرم => راك، أكواثيرم => أكواثيرم، الشريف => الشريف، BR/بي ار => BR).",
    "- ممنوع اختيار 'شعبي' إلا إذا كُتبت كلمة 'شعبي' أو 'اقتصادي' صراحة في الورقة، وإلا ضع bid: null.",
    "قواعد المقاسات والسباكة المصرية:",
    "- 'نص' أو '1/2' أو '20مم' => '1/2 بوصة' | 'تلات ارباع' أو '3/4' أو '25مم' => '3/4 بوصة' | '1' أو 'بوصة' أو '32مم' => '1 بوصة' | 'بوصة ونص' أو '1.5' أو '50مم' => '1.5 بوصة' | '2' أو '63مم' => '2 بوصة'.",
    "- فرّق بدقة بين: كوع، تيه (T)، جلبة، لاكور، طبة، نقاص، ماسورة، سن داخلي، سن ذكر، قفيز، صليبة، كرنك، ولا تخترع أصنافاً غير مكتوبة.",
    "أعد JSON فقط بدون أي نص إضافي:",
    '{"detected_brand_text":"نص الشركة أو null","bid":1,"items":[{"raw_ocr_text":"النص الأصلي","tid":12,"bid":1,"item_name":"اسم الصنف","size":"المقاس أو null","unit":"قطعة أو متر أو عود","quantity":1,"confidence":"high أو medium أو low","notes":"ملاحظة أو null"}]}',
    "الثقة: high عند تطابق الصنف والمقاس والكمية تماماً، medium عند الحاجة لتأكيد ماركة أو مقاس، low إذا كان غير واضح أو غير موجود بالكتالوج.",
  ].join("\n");

  const parts: Array<Record<string, unknown>> = [
    {
      text: "كتالوج المحل:\n" + catalog.ctx + "\n\nاقرأ الصور واستخرج البنود:",
    },
    ...imgs.map((img) => ({
      inlineData: { mimeType: img.mime, data: img.data },
    })),
  ];

  const gemPayload = {
    systemInstruction: { parts: [{ text: prompt }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      temperature: 0.1,
      responseMimeType: "application/json",
      thinkingConfig: { thinkingBudget: 0 },
    },
  };
  const gemPayloadNoThinking = {
    systemInstruction: { parts: [{ text: prompt }] },
    contents: [{ role: "user", parts }],
    generationConfig: {
      temperature: 0.1,
      responseMimeType: "application/json",
    },
  };

  let winner: WaveResult | null = null;
  let lastStatus = 503;
  let lastDetail = "AI service temporarily busy";

  // Wave 1: Parallel fast free race — Gemini + GitHub Models gpt-4.1-mini (10s strict end-to-end)
  const wave1Factories: Array<(s: AbortSignal) => Promise<WaveResult>> = [];
  if (geminiKey) {
    for (const m of GEMINI_MODELS) {
      wave1Factories.push((sig) =>
        attemptGemini(
          m,
          geminiKey,
          gemPayload,
          gemPayloadNoThinking,
          10000,
          sig,
        ),
      );
    }
  }
  if (githubToken) {
    for (const m of GITHUB_WAVE_1) {
      wave1Factories.push((sig) =>
        attemptOpenAiCompatible(
          "GitHub",
          "https://models.github.ai/inference/chat/completions",
          githubToken,
          m,
          prompt,
          catalog.ctx,
          imgs,
          10000,
          sig,
          { includeDetailHigh: true },
        ),
      );
    }
  }
  const w1 = await raceAttempts(wave1Factories);
  winner = w1.winner;
  lastStatus = w1.lastStatus;
  lastDetail = w1.lastDetail;

  // Wave 2: Parallel free fallback — GitHub gpt-4o-mini + OpenRouter (18s strict end-to-end)
  if (!winner) {
    const wave2Factories: Array<(s: AbortSignal) => Promise<WaveResult>> = [];
    if (githubToken) {
      for (const m of GITHUB_WAVE_2) {
        wave2Factories.push((sig) =>
          attemptOpenAiCompatible(
            "GitHub",
            "https://models.github.ai/inference/chat/completions",
            githubToken,
            m,
            prompt,
            catalog.ctx,
            imgs,
            18000,
            sig,
            { includeDetailHigh: true },
          ),
        );
      }
    }
    if (openRouterKey) {
      for (const m of OPENROUTER_FALLBACK_MODELS) {
        wave2Factories.push((sig) =>
          attemptOpenAiCompatible(
            "OpenRouter",
            "https://openrouter.ai/api/v1/chat/completions",
            openRouterKey,
            m,
            prompt,
            catalog.ctx,
            imgs,
            18000,
            sig,
            {
              extraBody: { reasoning: { enabled: false } },
              extraHeaders: { "X-Title": "Saarly" },
            },
          ),
        );
      }
    }
    const w2 = await raceAttempts(wave2Factories);
    winner = w2.winner;
    if (!winner) {
      lastStatus = w2.lastStatus;
      lastDetail = w2.lastDetail;
    }
  }

  if (!winner) {
    return jsonRes(
      502,
      { error: "AI analysis failed", status: lastStatus, detail: lastDetail },
      origin,
    );
  }

  const elapsedMs = Date.now() - startedAt;
  console.log(
    `Scan succeeded with model: ${winner.modelUsed} in ${elapsedMs}ms`,
  );

  const parsed = winner.parsed;
  const shabiBrandId =
    brands.find((b) => normalizeAr(b.name) === "شعبي")?.id ?? null;
  const detectedBrandText =
    typeof parsed.detected_brand_text === "string"
      ? parsed.detected_brand_text.trim()
      : "";

  let detectedBrandId =
    resolveIntOrUuid(parsed.bid, catalog.idxToBrandId, catalog.brandIdSet) ??
    resolveIntOrUuid(
      parsed.detected_brand_id,
      catalog.idxToBrandId,
      catalog.brandIdSet,
    );

  const matchedHeaderBrand = matchBrandFromText(detectedBrandText, brands);
  if (matchedHeaderBrand) {
    detectedBrandId = matchedHeaderBrand;
  }
  if (shabiBrandId && detectedBrandId === shabiBrandId) {
    const normHeader = normalizeAr(detectedBrandText);
    if (!normHeader.includes("شعبي") && !normHeader.includes("اقتصادي")) {
      detectedBrandId = null;
    }
  }

  const rawItems = Array.isArray(parsed.items) ? parsed.items : [];
  if (!detectedBrandId && rawItems.length > 0) {
    const combinedRaw = rawItems
      .map((it) => String(it.raw_ocr_text ?? ""))
      .join(" ");
    const fromItems = matchBrandFromText(combinedRaw, brands);
    if (fromItems && fromItems !== shabiBrandId) {
      detectedBrandId = fromItems;
    }
  }

  // Precompute normalized alias map & template metadata for deterministic matching
  const aliasMap = new Map<string, string>();
  for (const a of aliases) {
    const key = normalizeAr(stripLeadingQty(a.alias_text));
    if (key && catalog.templateById.has(a.item_template_id)) {
      aliasMap.set(key, a.item_template_id);
    }
  }

  const templateMeta = templates.map((t) => ({
    template: t,
    normName: normalizeAr(t.name),
    tokens: normalizeAr(t.name)
      .split(" ")
      .filter((w) => w.length > 0),
    normSize: normalizeSize(t.size),
  }));
  const templateUuidSet = new Set(templates.map((t) => t.id));

  const items = rawItems.map((it) => {
    const rawOcr = String(it.raw_ocr_text ?? "").trim();
    const rawName = String(it.item_name ?? "").trim();
    const rawSize = it.size ? String(it.size).trim() : "";

    // 1. Resolve Brand
    const matchedItemBrand = matchBrandFromText(rawOcr, brands);
    let itemBrandId =
      matchedItemBrand ??
      resolveIntOrUuid(it.bid, catalog.idxToBrandId, catalog.brandIdSet) ??
      resolveIntOrUuid(it.brand_id, catalog.idxToBrandId, catalog.brandIdSet);

    if (shabiBrandId && itemBrandId === shabiBrandId) {
      const normRaw = normalizeAr(rawOcr);
      if (!normRaw.includes("شعبي") && !normRaw.includes("اقتصادي")) {
        itemBrandId = null;
      }
    }
    itemBrandId = itemBrandId ?? detectedBrandId ?? preferredBrandId;

    // 2. Resolve ItemTemplate (AI ID -> Alias -> Size verification -> Fuzzy fallback)
    let templateId =
      resolveIntOrUuid(it.tid, catalog.idxToTemplateId, templateUuidSet) ??
      resolveIntOrUuid(
        it.item_template_id,
        catalog.idxToTemplateId,
        templateUuidSet,
      );

    const strippedRaw = stripLeadingQty(rawOcr);
    const aliasKey = normalizeAr(strippedRaw);
    const matchedAliasId = aliasKey ? (aliasMap.get(aliasKey) ?? null) : null;
    if (!templateId && matchedAliasId) {
      templateId = matchedAliasId;
    }

    const extractedSize =
      normalizeSize(rawSize) ||
      normalizeSize(strippedRaw) ||
      normalizeSize(rawName);

    // Verify AI's template size against extractedSize; switch within same item name if mismatched
    if (templateId && extractedSize) {
      const chosen = catalog.templateById.get(templateId);
      if (chosen) {
        const chosenSize = normalizeSize(chosen.size);
        if (chosenSize && chosenSize !== extractedSize) {
          const siblings = catalog.templatesByName.get(chosen.name) ?? [];
          const better = siblings.find(
            (s) => normalizeSize(s.size) === extractedSize,
          );
          if (better) {
            templateId = better.id;
          }
        }
      }
    }

    // Deterministic token + size scorer when AI missed templateId
    let resolvedViaFallback = false;
    if (!templateId && (strippedRaw || rawName)) {
      const queryNorm = normalizeAr(`${rawName} ${strippedRaw}`);
      const queryTokens = new Set(
        queryNorm.split(" ").filter((w) => w.length > 0),
      );
      let bestScore = 0;
      let bestId: string | null = null;

      for (const meta of templateMeta) {
        if (meta.tokens.length === 0) continue;
        let overlap = 0;
        for (const tok of meta.tokens) {
          if (queryTokens.has(tok) || queryNorm.includes(tok)) {
            overlap++;
          }
        }
        if (overlap === 0) continue;
        const ratio = overlap / meta.tokens.length;
        let score = overlap * 2 + ratio * 2;
        if (meta.normName === normalizeAr(rawName)) {
          score += 3;
        }
        if (extractedSize && meta.normSize) {
          score += meta.normSize === extractedSize ? 3 : -2;
        }
        if (score > bestScore) {
          bestScore = score;
          bestId = meta.template.id;
        }
      }

      if (bestId && bestScore >= 3.5) {
        templateId = bestId;
        resolvedViaFallback = true;
      }
    }

    const matchedTemplate = templateId
      ? (catalog.templateById.get(templateId) ?? null)
      : null;

    let confidence =
      it.confidence === "high" ||
      it.confidence === "medium" ||
      it.confidence === "low"
        ? it.confidence
        : "medium";
    if (matchedAliasId && templateId === matchedAliasId) {
      confidence = "high";
    } else if (resolvedViaFallback && confidence === "low") {
      confidence = "medium";
    }

    return {
      raw_ocr_text: rawOcr,
      item_template_id: matchedTemplate?.id ?? null,
      brand_id: itemBrandId,
      item_name: matchedTemplate?.name ?? (rawName || "صنف غير محدد"),
      size: matchedTemplate?.size ?? (rawSize || null),
      unit:
        matchedTemplate?.unit ?? (String(it.unit ?? "قطعة").trim() || "قطعة"),
      quantity: parseQuantity(it.quantity),
      confidence,
      notes: it.notes ? String(it.notes).trim() : null,
    };
  });

  return jsonRes(
    200,
    {
      detected_brand_id: detectedBrandId,
      items,
      model_used: winner.modelUsed,
      elapsed_ms: elapsedMs,
    },
    origin,
  );
});
