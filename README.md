# Saarly (سعرلي) — AI-Powered Pricing & Billing Platform for Sanitary Ware & Plumbing Merchants

**Saarly (سعرلي)** is an Arabic-first (RTL) business application designed for sanitary ware and plumbing supply shops in Egypt. It converts handwritten plumber supply lists (*كشوف السباكة*) into accurately priced quotes and invoices in seconds using Vision AI, a customizable Egyptian plumbing slang dictionary, multi-brand price comparison, bulk Excel/CSV pricing tools, PDF/WhatsApp customer sharing, and deferred payment collection tracking.

---

## 1. Business Problem & Value Proposition

### The Problem
In Egyptian plumbing and sanitary ware retail:
- Plumbers bring **handwritten paper lists** with informal Egyptian trade slang (e.g., *بيبة، طربوش، مشطوف، عداية، سدة، معزول، تيه بباب*), Eastern Arabic numerals (`٠١٢٣٤٥٦٧٨٩`), shorthand symbols (`~` for inches), and mixed sizing standards (inches, millimeters, or brand-specific pipe thicknesses).
- Manual lookup across price lists for multiple manufacturers takes significant time per customer and leads to pricing mistakes.
- Shops frequently need to **compare total quote cost across brands** (e.g., Premium vs. Mid-tier) for the same list, convert full pipe lengths vs. per-meter pricing, and track partial or deferred customer balances.

### The Solution
Saarly digitizes and automates the entire shop counter workflow:
1. **Snap or Upload Paper Lists:** Take photos with the phone camera or upload gallery images (1–5 pages per list).
2. **AI Vision + Domain Intelligence:** Extracts items, quantities, sizes, and brands, maps plumber slang to shop SKUs, and applies domain rules automatically.
3. **Human-in-the-Loop Verification:** Confidence-tagged preview (`Confirmed`, `Needs Review`, `Unmatched`) with one-tap confirmation, smart same-category catalog switching, and automatic dictionary learning.
4. **Instant Brand Comparison & Customer Delivery:** Switch or clone quotes across brands, generate branded Arabic PDFs, and send formatted WhatsApp messages.
5. **Payment & Debt Collection Lifecycle:** Support cash, partial payment + deferred balance, and full deferred payment with automated overdue/due-today alerts.

---

## 2. Core Business Capabilities

### A. AI Handwritten List Scanning (`scan-invoice`)
- **Sequential AI Pipeline (Cost & Latency Optimized):** Runs a single primary request (`gemini-3.8-flash`) with high-resolution vision mode (`MEDIA_RESOLUTION_HIGH`), falling back sequentially (`gemini-3.5-flash-lite` -> OpenRouter `google/gemma-4-31b-it:free` -> GitHub `openai/gpt-4.1-mini`) only when an upstream provider fails.
- **Egyptian Plumbing Domain Rules Built Into AI & Post-Processing:**
  - **Eastern Arabic Numerals Priority:** Recognizes `٠–٩` accurately and normalizes quantities vs. fractions (`1/2`, `3/4`).
  - **Inch Shorthand (`~` / `ٓ`):** Understands `٤~` as `4 بوصة`, `٣/٤~` as `3/4 بوصة`, etc.
  - **Millimeter-to-Inch Conversion:** Maps millimeter sizing across DIN/ISO and ASTM/BS brand standards for both PPR feeding (`20–21mm -> 1/2"`, `25–27mm -> 3/4"`, `32–34mm -> 1"`, `40–42mm -> 1.25"`, `50mm -> 1.5"`, `60–63mm -> 2"`, `75mm -> 2.5"`, `90mm -> 3"`, `110mm -> 4"`) and uPVC/PVC drainage (`32mm -> 1"`, `40/43/48mm -> 1.5"`, `50/56/60/63mm -> 2"`, `75/82/89/90mm -> 3"`, `110/114mm -> 4"`, `125/140mm -> 5"`, `160/168mm -> 6"`, `200/219mm -> 8"`, `250mm -> 10"`, `315mm -> 12"`), while preserving square floor drains (`15x15`, `20x20`).
  - **Standard Variant Safety:** Selects standard plain fittings (e.g., `ماسورة عادي PIN20`, `كوع لحام`) unless specialized qualifiers (`مقاوم`, `معزول`, `مجلفن`, `أسود`, `بالباب`, `مسلوب`, `لاكور`, `بصامولة`, `PIN16`) are explicitly written.
  - **Pipe Length Pricing Conversion:** Automatically calculates per-meter pricing when a customer requests meters of a stick-priced pipe (`6m` divisor for drainage/pipes, `4m` divisor for PPR feeding pipes), or vice-versa.
  - **Header Brand Inheritance & Brand Pairing:** Applies header/first-line brand and repeat marks (`" "`, `//`, `،،`) across items, pairs typical feeding/drainage ecosystems (`راك` <-> `وايتكس`), and never assigns economy tier (`شعبي`) unless explicitly written.
  - **Pipe Derivatives (`ياردة`):** Treats pre-cut yard pipes (`25/50/100/150/200/300/600 cm`) as pipe derivatives in both AI matching and catalog filtering.

### B. Interactive Review, Verification & Self-Learning Dictionary
- **Confidence Status Filtering:** Dedicated filter tabs (`All`, `Confirmed`, `Needs Review`, `Unmatched`) with live item counts to jump straight to uncertain lines.
- **Quick Confirm & Approval Guard:** One-tap green checkmark (`✓`) marks an item confirmed; the **Approve** (`اعتماد`) action remains disabled until every item is verified.
- **Smart Catalog Selector:** Tapping any item name (or editing it) opens a smart catalog picker pre-filtered to the **closest matches & same category** with instant price/size/unit/brand updates.
- **Self-Learning Plumber Dictionary (`item_aliases`):** Re-linking a handwritten phrase automatically saves the normalized alias to the shop dictionary in Supabase (or queues offline) for instant 100% matching in future scans.

### C. Multi-Brand Switching & Quote Comparison
- **One-Tap Brand Switch:** Recalculate all matched items in a quote to another manufacturer's prices while keeping unmatched/unavailable items clearly flagged.
- **Side-by-Side Comparison Quotes:** Clone and link two brand versions of the same list under a shared `comparison_group_id`, highlight total savings between brands, and export a **Comparison PDF** or WhatsApp summary.

### D. Catalog Tree, Bulk Excel Engine & Profit Margin Management
- **Structured Catalog Tree:** Organized by Category (`تغذية (بولي)`, `صرف`, `مواسير`, `محابس وخلاطات`, `إكسسوارات ولوازم`, etc.), Template (item + size + unit), and Brand-specific Variant pricing (`commercial_price` + selling `price`).
- **Native `.xlsx` / `.csv` Import & Export:**
  - Supports reordered headers, Arabic/English digits, title rows, semicolon/tab delimiters, and evaluated multi-sheet Excel formulas without relying on `styles.xml`.
  - **Two Pricing Modes on Import:**
    1. *Commercial Cost Mode:* Enter optional manufacturer discount % + mandatory profit markup (% or fixed EGP) to compute selling prices automatically.
    2. *Direct Selling Price Mode:* Import ready-to-sell customer prices directly.
- **Bulk Profit Margin Recalculation:** Managers can update selling prices across the catalog (all items or filtered by category/brand) from stored `commercial_price` values.

### E. Invoicing, Payment Collection & Notifications
- **Payment Methods:**
  - **Cash (`كاش`):** Paid in full upon approval.
  - **Partial Now, Rest Later (`جزء الآن وجزء بعد الانتهاء`):** Records initial payment + due date.
  - **Deferred Without Deposit (`آجل بدون مقدم`):** Full balance scheduled with a due date.
  - **Deferred With Deposit (`آجل بمقدم`):** Records down payment + balance due date.
- **Due-Date Collection Workflow:** Approved invoices with a remaining balance replace the Approve button with two collection actions:
  - **Full Collection (`تم التحصيل`):** Collects remaining balance and settles the invoice.
  - **Partial Payment & Reschedule (`دفع جزء وباقي جزء`):** Logs an installment and sets a new due date for the remainder.
- **Notification Center & Android Device Alerts:**
  - Header notification bell with unread badge and popover distinguishing **Overdue** vs. **Due Today** customer balances.
  - Schedules local Android notifications at 9:00 AM for upcoming due dates and cleans up reminders once invoices are settled or deleted.

### F. Customer Delivery (WhatsApp & Arabic PDF) & Reports
- **Post-Approval Delivery Dialog:** Send via WhatsApp (with Egyptian phone normalization to `+20`), share PDF file, preview/print PDF, or save only. Optional technician/plumber field appears only when filled.
- **Sales & Performance Reports:** Period filters (`Today`, `Last 7 Days`, `This Month`, `All`), KPIs (Approved Sales, Pending Quotes, Conversion Rate), top-requested items, and staff performance breakdown.

---

## 3. User Roles & Security Model

Authentication and authorization are enforced via **Supabase Auth** and **PostgreSQL Row Level Security (RLS)** (`0001_initial_schema.sql` & `0002_harden_security_functions.sql`):

| Role | Capabilities |
| :--- | :--- |
| **Manager (`admin`)** | Full access: scan lists, create/approve/delete invoices, manage categories/brands/catalog pricing, import/export Excel, adjust profit margins, manage plumber dictionary, activate/deactivate staff, and change user roles. *(First registered user is automatically assigned `admin`.)* |
| **Staff / Salesperson (`staff`)** | Active shop employees: scan lists, search/view catalog prices, create quotes & approved invoices, record collections, and share PDFs/WhatsApp. Cannot edit catalog base prices, import spreadsheets, or manage users/settings. |

Additional security controls:
- JWT verification (`verify_jwt: true`) and active-profile check inside the `scan-invoice` Edge Function.
- Restricted CORS allowlist (`ALLOWED_ORIGINS` / localhost / private LAN / Cloudflare quick tunnel).
- Strict image validation (max 5 images, <= 5 MB each, verified JPEG/PNG/WEBP magic bytes).
- Private storage bucket for scanned invoice images.

---

## 4. End-to-End Business Workflow

```text
  [1. Camera / Gallery Upload]
               │
               ▼
  [2. AI Scan (scan-invoice Edge Function)]
      • Reads Arabic handwriting & Eastern digits
      • Converts mm/~/inches & resolves slang aliases
      • Matches catalog items & pairs brands
               │
               ▼
  [3. Review Screen]
      • Filter by Confirmed / Needs Review / Unmatched
      • Tap item name -> Smart same-category picker
      • Adjust quantity (+ / direct input / -), brand, discount
      • One-tap Confirm (✓) on uncertain items
               │
        ┌──────┴───────────────────────┐
        ▼                              ▼
  [Save Quote / Compare Brands]   [Approve (enabled once all items ✓)]
                                       │
                                       ▼
                         [Share PDF / WhatsApp / Print]
                                       │
                  (If Partial / Deferred balance remains)
                                       │
                                       ▼
                     [Due-Date Reminder -> Collect Full or Partial]
```

---

## 5. Technical Architecture & Project Structure

- **Frontend:** Flutter (Dart `^3.14.0`, Riverpod state management, GoRouter navigation, Arabic RTL localization, Material 3 UI) targeting **Android** and **Web**.
- **Backend:** Supabase (PostgreSQL with RLS, Auth, Storage, and Deno Edge Function `scan-invoice`).
- **Offline Resilience:** Local caching (`shared_preferences`) for catalog snapshots, offline invoices queue, and pending learned aliases with automatic foreground/resume sync.

```text
.
├── app/                                  # Flutter cross-platform application (Android & Web)
│   ├── lib/
│   │   ├── core/config/app_config.dart   # Runtime --dart-define config & Demo Mode toggle
│   │   ├── core/theme/app_theme.dart     # Theme tokens & confidence color palette
│   │   ├── data/                         # Supabase repository, local cache, Egyptian demo seed
│   │   ├── features/
│   │   │   ├── auth/                     # Login & registration screen
│   │   │   ├── catalog/                  # Product tree, Excel import/export, profit margin tools
│   │   │   ├── dashboard/                # Main dashboard, scan sheet, KPI overview
│   │   │   ├── invoices/                 # Invoices & quotes list with search and filters
│   │   │   ├── reports/                  # Sales & staff KPI analytics
│   │   │   ├── review/                   # Item verification, smart picker, payment & share dialogs
│   │   │   ├── settings/                 # Shop profile, staff permissions, plumber dictionary
│   │   │   └── shell/                    # Navigation shell, notifications popover, back handling
│   │   ├── models/                       # Catalog & invoice domain models
│   │   ├── providers/                    # Riverpod state notifiers (Auth, Catalog, Invoices, Staff, Notifications)
│   │   └── services/                     # AI scan client, Excel/CSV parser, PDF/WhatsApp share, local reminders
│   └── test/widget_test.dart             # Automated unit & widget test suite (38 tests)
├── scripts/
│   └── build_android_live.ps1            # Windows release APK build script with Supabase defines
└── supabase/
    ├── config.toml                       # Supabase project configuration
    ├── SETUP.md                          # Supabase & Edge Function secret setup notes
    ├── seed.sql                          # Initial categories, brands, templates, and seed data
    ├── functions/scan-invoice/index.ts   # Vision AI OCR & Egyptian plumbing matching Edge Function
    └── migrations/                       # SQL migrations (0001..0006)
```

---

## 6. Database Schema Overview

Core tables in Supabase PostgreSQL (`supabase/migrations/`):
- `profiles`: Linked to `auth.users` (`role`: `admin` | `staff`, `is_active`).
- `shop_settings`: Shop name, phone, address, and branding metadata shown on PDFs/WhatsApp.
- `categories`, `brands`, `item_templates`, `product_variants`: Normalized catalog supporting multi-brand pricing, commercial cost (`commercial_price`), selling price (`price`), units (`قطعة`, `عود`, `متر`, `ياردة`), and availability flags.
- `item_aliases`: Shop-specific plumber terminology dictionary mapping slang phrases to `item_template_id`.
- `invoices`, `invoice_items`: Quotes & approved invoices with discount rules, `comparison_group_id`, payment method, `paid_amount`, `payment_due_date`, scanned image references, and OCR confidence states.

---

## 7. Setup, Build & Running Locally

### 1. Backend (Supabase)
1. Apply SQL migrations in `supabase/migrations/` (`0001` through `0006`) and optionally `supabase/seed.sql`.
2. Configure Edge Function secrets in Supabase:
   - `GEMINI_API_KEY` (primary AI vision key)
   - Optional fallback keys: `OPENROUTER_API_KEY`, `GITHUB_TOKEN`
   - Optional: `ALLOWED_ORIGINS` (comma-separated allowed web origins)
3. Deploy the Edge Function (`verify_jwt = true`):
   ```bash
   supabase functions deploy scan-invoice
   ```

### 2. Frontend (Flutter App)
The app uses compile-time `--dart-define` environment flags (never hardcoded credentials):
- **Demo Mode (no backend required):** Omit `SUPABASE_URL` / `SUPABASE_ANON_KEY` to run locally with pre-seeded Egyptian sanitary ware data.
- **Live Connected Mode:** Pass `SUPABASE_URL` and `SUPABASE_ANON_KEY`:

```bash
cd app
flutter pub get

# Run Web release build
flutter build web --release --dart-define=SUPABASE_URL=<YOUR_URL> --dart-define=SUPABASE_ANON_KEY=<YOUR_ANON_KEY>

# Or build Android APK using the helper script (Windows PowerShell)
..\scripts\build_android_live.ps1 -SupabaseUrl "<YOUR_URL>" -SupabaseAnonKey "<YOUR_ANON_KEY>"
```

---

## 8. Excel / CSV Catalog Import Format

Upload `.xlsx`, `.csv`, or `.tsv` files via **Catalog (الأصناف) -> Excel Import/Export**:

| القسم (Category) | اسم الصنف (Item) | المقاس (Size) | الوحدة (Unit) | الشركة (Brand) | السعر (Price) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| تغذية (بولي) | كوع لحام | 1/2 بوصة | قطعة | الشريف | 18 |
| صرف | جلبة صرف بسن | 4 بوصة | قطعة | الشريف | 65 |
| محابس وخلاطات | محبس بلي نحاس | 3/4 بوصة | قطعة | BR | 210 |

- Columns can appear in any order as long as headers match standard Arabic/English names (`اسم الصنف` and `السعر` / `السعر التجاري` are required).
- Supports Excel formulas, company discounts, and automatic selling-price markup calculation.

---

## 9. Verification & Testing

The automated test suite (`app/test/widget_test.dart`) covers catalog filtering, Excel `.xlsx`/formula parsing, profit margin & company discount math, Egyptian pipe-meter pricing, confidence gating, partial payment collection flows, system back navigation, notifications, and PDF/WhatsApp formatting:

```bash
cd app
flutter analyze
flutter test
```
