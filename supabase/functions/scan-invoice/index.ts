declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const MAX_IMAGES = 5;
const MAX_IMAGE_BYTES = 5 * 1024 * 1024;

const GEMINI_PRIMARY_MODEL = "gemini-3.8-flash";
const GEMINI_FALLBACK_MODEL = "gemini-3.5-flash-lite";
const OPENROUTER_FALLBACK_MODEL = "google/gemma-4-31b-it:free";
const GITHUB_FALLBACK_MODEL = "openai/gpt-4.1-mini";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOCAL_ORIGIN_RE =
  /^https?:\/\/(localhost|127\.0\.0\.1|192\.168\.\d{1,3}\.\d{1,3}|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(:\d{1,5})?$/i;
const TUNNEL_ORIGIN_RE = /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/i;

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
  categories?: { name?: string } | null;
}

const SPECIALIZED_QUALIFIERS = [
  "مقاوم",
  "اسود",
  "مجلفن",
  "بالباب",
  "مسلوب",
  "لاكور",
  "اختبار",
  "تسليك",
  "بصاموله",
  "بدون صاموله",
  "pin16",
];

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
  return list.length > 0
    ? list.includes(origin)
    : LOCAL_ORIGIN_RE.test(origin) || TUNNEL_ORIGIN_RE.test(origin);
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
    .replace(/\brak\b|راك\s*(?:ثيرم|تيرم|بيرم|ثرم|ترم)?|راكثيرم/g, "راك")
    .replace(/اكواثيرم|اكوا\s*ثيرم|aquatherm/g, "اكواثيرم")
    .replace(/بي\s*ار|بى\s*ار/g, "br")
    .replace(/(?:^|\s)(?:تيه|تي|ت|مشترك|قسام)(?=\s|$)/g, " t ")
    .replace(/\b(?:واى|مشطوف)\b/g, "واي")
    .replace(/\b(?:معزول|معزوله|للشمس|فايبر)\b/g, "ماسوره مقاوم")
    .replace(/كوع\s*(?:مفتوح|45)/g, "كوع فاتح")
    .replace(/كوع\s*(?:قفل|مقفول)/g, "كوع عادي")
    .replace(/كوع\s*(?:ب?باب|كشف|تسليك)/g, "كوع بالباب")
    .replace(/(?:^|\s)t\s*(?:ب?باب|كشف|تسليك)/g, " t بالباب")
    .replace(/\b(?:بيبه|بالوعه|سيفون\s*ارضيه)\b/g, "بلاعه")
    .replace(/\bطربوش(?:\s*تهويه|\s*صرف)?\b/g, "هوايه")
    .replace(/\b(?:عدايه|مطب|كرانك)\b/g, "كرنك")
    .replace(/\b(?:سده|سداده)\b/g, "طبه")
    .replace(/\b(?:كليبس|مشبك|حزام\s*ماسوره)\b/g, "قفيز")
    .replace(/\b(?:يونيون|لاكر)\b/g, "لاكور")
    .replace(/\b(?:بوش|رديوسر|تخفيض)\b/g, "نقاص")
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
    .replace(/-\s*سمك\s*[\d.]+\s*(?:مم|mm)?/g, " ")
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
    .replace(/160\s*(?:مم|mm)?/g, " 6 ")
    .replace(/110\s*(?:مم|mm)?/g, " 4 ")
    .replace(/(?:75|90)\s*(?:مم|mm)?/g, " 3 ")
    .replace(/63\s*(?:مم|mm)?/g, " 2 ")
    .replace(/50\s*(?:مم|mm)?/g, " 1.5 ")
    .replace(/40\s*(?:مم|mm)?/g, " 1.25 ")
    .replace(/32\s*(?:مم|mm)?/g, " 1 ")
    .replace(/×|\*|\bفي\b|\bعلى\b|\bعلي\b/g, " x ")
    .replace(/[~ٓ″]/g, " ")
    .replace(/بوصه|بوصة|inch|in|"|''/g, " ");

  const compound = s.match(
    /(1\/2|3\/4|1\.5|1\.25|1|2|3|4|6)\s*(?:x|\/)\s*(1\/2|3\/4|1\.5|1\.25|1|2|3|4|6)/,
  );
  if (compound) {
    const parts = [compound[1], compound[2]].sort(
      (a, b) => sizePartValue(a) - sizePartValue(b),
    );
    return `${parts[0]}x${parts[1]}`;
  }

  const single = s.match(/(?:^|\s)(1\/2|3\/4|1\.5|1\.25|1|2|3|4|6)(?=\s|$)/);
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

function cleanNullableText(raw: unknown): string {
  if (raw === null || raw === undefined) return "";
  const trimmed = String(raw).trim();
  const lower = trimmed.toLowerCase();
  if (
    !trimmed ||
    lower === "null" ||
    lower === "undefined" ||
    lower === "n/a"
  ) {
    return "";
  }
  return trimmed;
}

function extractLeadingQuantity(rawOcr: string): number | null {
  const normalized = toWesternDigits(rawOcr).trim();
  const m = normalized.match(
    /^\s*(\d+(?:\.\d+)?)(?!\s*\/)(?=\s*(?:[x×*]|قطعه|قطعة|متر|عود|حبه|حبة|عدد|\s+[^\d\s.]))/iu,
  );
  if (!m) return null;
  const n = Number(m[1]);
  return Number.isFinite(n) && n > 0 ? n : null;
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
      Math.min(timeoutMs, 10000),
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

async function attemptGemini(
  apiKey: string,
  model: string,
  prompt: string,
  ctx: string,
  imgs: Array<{ data: string; mime: string }>,
  timeoutMs: number,
  signal: AbortSignal,
): Promise<WaveResult> {
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const headers = {
    "Content-Type": "application/json",
    "x-goog-api-key": apiKey,
  };
  const baseBody = {
    systemInstruction: { parts: [{ text: prompt }] },
    contents: [
      {
        role: "user",
        parts: [
          {
            text: "كتالوج المحل:\n" + ctx + "\n\nاقرأ الصور واستخرج البنود:",
          },
          ...imgs.map((img) => ({
            inlineData: { mimeType: img.mime, data: img.data },
          })),
        ],
      },
    ],
    generationConfig: {
      temperature: 0.1,
      maxOutputTokens: 4096,
      responseMimeType: "application/json",
    },
  };

  const sendAttempt = async (bodyObj: unknown, reqTimeoutMs: number) =>
    await fetchJsonWithTimeout(
      endpoint,
      { method: "POST", headers, body: JSON.stringify(bodyObj) },
      reqTimeoutMs,
      signal,
    );

  const preferredPayload = {
    ...baseBody,
    generationConfig: {
      ...baseBody.generationConfig,
      mediaResolution: "MEDIA_RESOLUTION_HIGH",
      thinkingConfig: { thinkingLevel: "low" },
    },
  };

  let res = await sendAttempt(preferredPayload, timeoutMs);
  if (res.status === 400) {
    res = await sendAttempt(baseBody, Math.min(timeoutMs, 15000));
  }
  if (!res.ok) {
    const msg = extractErrMsg(res.body, res.status);
    console.error(`Gemini error on ${model}: ${res.status} ${msg}`);
    throw Object.assign(new Error(msg), { status: res.status });
  }
  const data = res.body as {
    candidates?: Array<{
      content?: { parts?: Array<{ text?: string; thought?: boolean }> };
    }>;
  };
  const txt = (data?.candidates?.[0]?.content?.parts ?? [])
    .filter((p) => !p.thought && typeof p.text === "string")
    .map((p) => p.text!)
    .join("")
    .trim();
  if (!txt) {
    throw Object.assign(new Error("Empty Gemini response"), { status: 502 });
  }
  const parsed = parseAiJson(txt);
  if (!parsed) {
    throw Object.assign(new Error("Malformed Gemini JSON"), { status: 502 });
  }
  return { parsed, modelUsed: `google/${model}` };
}

async function runSequentialAttempts(
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
  let lastStatus = 503;
  let lastDetail = "AI service temporarily busy";

  for (const fn of factories) {
    const ctrl = new AbortController();
    try {
      const winner = await fn(ctrl.signal);
      return { winner, lastStatus: 200, lastDetail: "" };
    } catch (err) {
      if (err && typeof err === "object") {
        const st = (err as { status?: unknown }).status;
        const msg = (err as { message?: unknown }).message;
        if (typeof st === "number") lastStatus = st;
        if (typeof msg === "string" && msg.length > 0) lastDetail = msg;
      }
    }
  }

  return { winner: null, lastStatus, lastDetail };
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
    // Include all known plumber slang aliases (up to 500) so the AI sees exact domain vocabulary.
    const pairs: string[] = [];
    for (const a of aliases) {
      const tid = templateIdToIdx.get(a.item_template_id);
      const cleanedAlias = stripLeadingQty(a.alias_text);
      if (tid && cleanedAlias) {
        pairs.push(`${cleanedAlias}=>${tid}`);
        if (pairs.length >= 500) break;
      }
    }
    if (pairs.length > 0) {
      ctxLines.push("قاموس مسميات السباكين (alias=>tid):");
      for (let i = 0; i < pairs.length; i += 10) {
        ctxLines.push(pairs.slice(i, i + 10).join(" | "));
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
  const geminiKey =
    Deno.env.get("GEMINI_API_KEY") ??
    Deno.env.get("GOOGLE_API_KEY") ??
    Deno.env.get("GOOGLE_GEMINI_API_KEY");
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
      sbUrl +
        "/rest/v1/item_templates?select=id,name,size,unit,categories(name)&order=name.asc",
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
    "اقرأ كل سطر في الورقة المكتوبة بخط اليد من أعلى لأسفل دون تخطي أي سطر ودون اختراع بنود غير مكتوبة، وطابق كل بند بدقة مع الكتالوج المرفق باستخدام الأرقام المختصرة (tid للصنف، bid للماركة).",
    "قواعد القراءة والكميات والأرقام:",
    "- الأرقام العربية الشرقية (٠ ١ ٢ ٣ ٤ ٥ ٦ ٧ ٨ ٩) لها الأولوية المطلقة في القراءة (ميز بدقة بين ٥ و٠، و٢ و٣ و٤ و٦ و٧ و٨) ثم حوّلها في الـ JSON إلى 0-9.",
    "- العلامة (~) أو (ٓ) فوق الرقم أو بجانبه تعني «بوصة» (مثال: ٢~ = 2 بوصة، ٤~ = 4 بوصة، ٣/٤~ = 3/4 بوصة).",
    "- استخرج العدد/الكمية بدقة سواء كُتب قبل الصنف أو بعده، ولا تخلط أبداً بين أرقام المقاس (1/2، 3/4، 1، 1.5، 2، 3، 4، 6) وبين الكمية.",
    '- استفد أولاً من «قاموس مسميات السباكين (alias=>tid)» المرفق لمطابقة مصطلحات الفنيين؛ وإذا تعذّر إيجاد البند في الكتالوج، ضع tid: null واكتب اسم الصنف المقروء بالعربي ولا تكتب أبداً كلمة "null" كنص داخل item_name أو size.',
    "قاعدة اختيار الصنف العادي (مهم جداً):",
    "- إذا لم يُذكر صراحةً في السطر وصف مميّز مثل (مقاوم، معزول، أسود، مجلفن، بالباب، مسلوب، لاكور، بصامولة، اختبار، تسليك، PIN16)، اختر الصنف «العادي» المطابق فقط (مثل ماسورة عادي PIN20، كوع لحام، T لحام، جلبة لحام، طبة لحام) ولا تخترع أو تختار أي صنف مخصص لم يُذكر في الورقة.",
    "قواعد الوحدات للمواسير:",
    "- احتفظ بالوحدة المكتوبة في الورقة في حقل requested_unit و unit: إذا كتب 'متر' (مثل: 2 متر ماسورة 4 وايتكس أو 10 متر ماسورة 3/4) ضع requested_unit: 'متر'، وإذا كتب 'عود' أو لم يذكر 'متر' مع ماسورة صرف/عود ضع requested_unit: 'عود'، وللقطع ضع 'قطعة'.",
    "قواعد الماركة وعلامات التكرار والثنائيات:",
    "- لو ذُكرت شركة واحدة في أول الصفحة أو في أول سطر بدون ذكر شركات أخرى في الأسطر التالية، فهي تنطبق على باقي بنود نفس النوع.",
    "- علامات التكرار مثل (\" \") أو (//) أو (،،) أو ('') معناها نفس الشركة المكتوبة في السطر السابق.",
    "- مراعاة الثنائيات المعتادة ما لم يُذكر خلاف ذلك صراحة: بنود التغذية/البولي للشركات مثل 'راك' يكون الصرف والمواسير المقابل لها في الغالب 'وايتكس' (مثلاً لو الكشف بدأ بـ راك ثم ظهرت بنود صرف/مواسير صرف بدون شركة فهي وايتكس، والعكس لو وايتكس وظهرت بنود بولي/تغذية فهي راك).",
    "- ممنوع اختيار 'شعبي' إلا إذا كُتبت كلمة 'شعبي' أو 'اقتصادي' صراحة في الورقة، وإلا ضع bid: null.",
    "قواعد المقاسات والسباكة المصرية:",
    "- التغذية: 'نص'/'1/2'/'20مم' => '1/2 بوصة' | 'تلات ارباع'/'3/4'/'25مم' => '3/4 بوصة' | '1'/'بوصة'/'32مم' => '1 بوصة' | 'بوصة ونص'/'1.5'/'50مم' => '1.5 بوصة' | '2'/'63مم' => '2 بوصة'.",
    "- الصرف والمواسير: '1.5 بوصة'، '2 بوصة'، '3 بوصة'، '4 بوصة'، '6 بوصة' (لا يوجد مقاس 3/2 بوصة؛ تحقق هل يقصد 3/4 أو 1/2 أو 1.5 بوصة).",
    "- مصطلحات السباكين: معزول / شمس / فايبر = ماسورة مقاوم، ماسورة عادية / بولي بدون ذكر معزول = ماسورة عادي PIN20، بيبة=بلاعة، مشترك/قسام=T، مشطوف=واي، كوع مفتوح/45=كوع فاتح، كوع قفل=كوع عادي، كوع باب/كشف=كوع بالباب، عداية/مطب=كرنك، طربوش=هواية، سدة=طبة، كليبس=قفيز، يونيون=لاكور، بوش/رديوسر=نقاص، نتاية=داخلي، دكر=ذكر.",
    "أعد JSON فقط بدون أي نص إضافي:",
    '{"detected_brand_text":"نص الشركة أو null","bid":1,"items":[{"raw_ocr_text":"النص الأصلي للسطر","tid":12,"bid":1,"item_name":"اسم الصنف العربي","size":"المقاس أو null","unit":"قطعة أو متر أو عود","requested_unit":"متر أو عود أو قطعة","quantity":1,"confidence":"high أو medium أو low","notes":"ملاحظة أو null"}]}',
    "الثقة: high عند تطابق الصنف والمقاس والكمية تماماً، medium عند الحاجة لتأكيد ماركة أو مقاس، low إذا كان غير واضح أو غير موجود بالكتالوج.",
  ].join("\n");

  // Strict sequential 1-request-at-a-time execution:
  // 1. Gemini 3.8 Flash (primary — 1 request in normal cases)
  // 2. Gemini 3.5 Flash Lite (fallback 1 — only if primary fails)
  // 3. OpenRouter Gemma 4 31B -> GitHub GPT-4.1-mini (fallback 2 — only if Gemini fails or key is absent)
  const attempts: Array<(sig: AbortSignal) => Promise<WaveResult>> = [];
  if (geminiKey) {
    attempts.push((sig) =>
      attemptGemini(
        geminiKey,
        GEMINI_PRIMARY_MODEL,
        prompt,
        catalog.ctx,
        imgs,
        22000,
        sig,
      ),
    );
    attempts.push((sig) =>
      attemptGemini(
        geminiKey,
        GEMINI_FALLBACK_MODEL,
        prompt,
        catalog.ctx,
        imgs,
        18000,
        sig,
      ),
    );
  }
  if (openRouterKey) {
    attempts.push((sig) =>
      attemptOpenAiCompatible(
        "OpenRouter",
        "https://openrouter.ai/api/v1/chat/completions",
        openRouterKey,
        OPENROUTER_FALLBACK_MODEL,
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
  if (githubToken) {
    attempts.push((sig) =>
      attemptOpenAiCompatible(
        "GitHub",
        "https://models.github.ai/inference/chat/completions",
        githubToken,
        GITHUB_FALLBACK_MODEL,
        prompt,
        catalog.ctx,
        imgs,
        15000,
        sig,
        { includeDetailHigh: true },
      ),
    );
  }

  const { winner, lastStatus, lastDetail } =
    await runSequentialAttempts(attempts);

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

  const rakBrandId =
    brands.find((b) => normalizeAr(b.name) === "راك")?.id ?? null;
  const whitexBrandId =
    brands.find((b) => normalizeAr(b.name) === "وايتكس")?.id ?? null;
  const templateCategoryMap = new Map<string, string>();
  for (const t of templates) {
    const catName = t.categories?.name ? String(t.categories.name) : "";
    if (catName) templateCategoryMap.set(t.id, catName);
  }

  const templateMeta = templates.map((t) => ({
    template: t,
    normName: normalizeAr(t.name),
    tokens: normalizeAr(t.name)
      .split(" ")
      .filter((w) => w.length > 0),
    normSize: normalizeSize(t.size),
    normCategory: normalizeAr(t.categories?.name ?? ""),
  }));
  const templateUuidSet = new Set(templates.map((t) => t.id));

  const items = rawItems.map((it) => {
    const rawOcr = cleanNullableText(it.raw_ocr_text);
    const rawName = cleanNullableText(it.item_name);
    const rawSize = cleanNullableText(it.size);
    const cleanUnit = cleanNullableText(it.unit);
    const rawRequestedUnit = cleanNullableText(it.requested_unit);
    const cleanNotes = cleanNullableText(it.notes);

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

    // 2. Resolve ItemTemplate (AI ID -> Alias -> Qualifier/Size verification -> Fuzzy fallback)
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

    const queryNormAll = normalizeAr(`${rawOcr} ${rawName}`);
    const extractedSize =
      normalizeSize(rawSize) ||
      normalizeSize(strippedRaw) ||
      normalizeSize(rawName);

    // Rule 3: Never pick a specialized qualifier (مقاوم, أسود, بالباب, PIN16, etc.) if not mentioned in OCR
    if (templateId) {
      const chosen = catalog.templateById.get(templateId);
      if (chosen) {
        const chosenNorm = normalizeAr(chosen.name);
        const hasUnmentionedQualifier = SPECIALIZED_QUALIFIERS.some(
          (q) => chosenNorm.includes(q) && !queryNormAll.includes(q),
        );
        if (hasUnmentionedQualifier) {
          const targetSize = extractedSize || normalizeSize(chosen.size);
          let bestPlainId: string | null = null;
          let bestPlainScore = 0;
          for (const meta of templateMeta) {
            const metaHasUnmentioned = SPECIALIZED_QUALIFIERS.some(
              (q) =>
                (meta.normName.includes(q) || meta.normSize.includes(q)) &&
                !queryNormAll.includes(q),
            );
            if (metaHasUnmentioned) continue;
            if (targetSize && meta.normSize !== targetSize) continue;
            let overlap = 0;
            for (const tok of meta.tokens) {
              if (queryNormAll.includes(tok)) overlap++;
            }
            if (overlap === 0) continue;
            let score = overlap * 2 + overlap / meta.tokens.length;
            if (
              queryNormAll.includes("ماسور") &&
              meta.normName.includes("عادي pin20")
            ) {
              score += 2;
            }
            if (score > bestPlainScore) {
              bestPlainScore = score;
              bestPlainId = meta.template.id;
            }
          }
          if (bestPlainId) {
            templateId = bestPlainId;
          }
        }
      }
    }

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
        for (const q of SPECIALIZED_QUALIFIERS) {
          if (
            (meta.normName.includes(q) || meta.normSize.includes(q)) &&
            !queryNorm.includes(q)
          ) {
            score -= 3.5;
          }
        }
        if (
          queryNorm.includes("ماسور") &&
          !queryNorm.includes("مقاوم") &&
          !queryNorm.includes("pin16") &&
          meta.normName.includes("عادي pin20")
        ) {
          score += 1.5;
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

    // Rule 5: Enforce brand pairing when no explicit brand was written on this line
    if (!matchedItemBrand && matchedTemplate) {
      const normCat = normalizeAr(
        templateCategoryMap.get(matchedTemplate.id) ?? "",
      );
      if (
        whitexBrandId &&
        itemBrandId === rakBrandId &&
        (normCat.includes("صرف") || normCat.includes("مواسير"))
      ) {
        itemBrandId = whitexBrandId;
      } else if (
        rakBrandId &&
        itemBrandId === whitexBrandId &&
        normCat.includes("تغذيه")
      ) {
        itemBrandId = rakBrandId;
      }
    }

    // Rule 4: Determine requested_unit cleanly
    let requestedUnit = rawRequestedUnit || cleanUnit;
    if (queryNormAll.includes("متر")) {
      requestedUnit = "متر";
    } else if (queryNormAll.includes("عود")) {
      requestedUnit = "عود";
    } else if (!requestedUnit && matchedTemplate?.unit) {
      requestedUnit = matchedTemplate.unit;
    }

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

    const parsedQty = parseQuantity(it.quantity);
    const extractedQty =
      parsedQty === 1 ? extractLeadingQuantity(rawOcr) : null;
    const finalQty = extractedQty ?? parsedQty;

    return {
      raw_ocr_text: rawOcr,
      item_template_id: matchedTemplate?.id ?? null,
      brand_id: itemBrandId,
      item_name: matchedTemplate?.name ?? (rawName || rawOcr || "صنف غير محدد"),
      size: matchedTemplate?.size ?? (rawSize || null),
      unit: matchedTemplate?.unit ?? (cleanUnit || "قطعة"),
      requested_unit: requestedUnit || null,
      quantity: finalQty,
      confidence,
      notes: cleanNotes || null,
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
