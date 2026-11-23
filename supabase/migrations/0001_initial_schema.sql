-- 0001_initial_schema.sql
-- Supabase PostgreSQL schema for Egyptian Sanitary Ware & Plumbing Pricing App
-- Includes Product Tree, Aliases, Multi-Brand Quote Comparison, Optional Technician Name,
-- Strict Row Level Security (RLS), and Private Storage Bucket.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 1. Helper Trigger Functions
-- ============================================================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ============================================================================
-- 2. Profiles & Role Helpers
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'staff' CHECK (role IN ('admin', 'staff')),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  assigned_role text;
  user_full_name text;
BEGIN
  LOCK TABLE public.profiles IN SHARE ROW EXCLUSIVE MODE;

  IF NOT EXISTS (SELECT 1 FROM public.profiles) THEN
    assigned_role := 'admin';
  ELSE
    assigned_role := 'staff';
  END IF;

  user_full_name := NULLIF(btrim(COALESCE(NEW.raw_user_meta_data ->> 'full_name', '')), '');
  IF user_full_name IS NULL THEN
    user_full_name := COALESCE(NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''), 'مستخدم');
  END IF;

  INSERT INTO public.profiles (id, full_name, role, is_active)
  VALUES (NEW.id, user_full_name, assigned_role, true)
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

CREATE OR REPLACE FUNCTION public.is_active_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = auth.uid()
      AND is_active = true
      AND role = 'admin'
  );
$$;

-- ============================================================================
-- 3. Product Tree (Categories, Brands, Shop Settings, Templates, Variants, Aliases)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.brands (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  tier text NOT NULL DEFAULT 'mid' CHECK (tier IN ('economy', 'mid', 'premium')),
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.shop_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_name text NOT NULL DEFAULT 'محل الأدوات الصحية',
  phone text,
  address text,
  logo_url text,
  default_brand_id uuid REFERENCES public.brands(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_shop_settings_updated_at ON public.shop_settings;
CREATE TRIGGER trg_shop_settings_updated_at
  BEFORE UPDATE ON public.shop_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.item_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id uuid NOT NULL REFERENCES public.categories(id) ON DELETE RESTRICT,
  name text NOT NULL,
  size text,
  unit text NOT NULL DEFAULT 'قطعة',
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_item_templates_unique
  ON public.item_templates (category_id, name, COALESCE(size, ''));

CREATE INDEX IF NOT EXISTS idx_item_templates_category
  ON public.item_templates (category_id);

DROP TRIGGER IF EXISTS trg_item_templates_updated_at ON public.item_templates;
CREATE TRIGGER trg_item_templates_updated_at
  BEFORE UPDATE ON public.item_templates
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.product_variants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_template_id uuid NOT NULL REFERENCES public.item_templates(id) ON DELETE CASCADE,
  brand_id uuid NOT NULL REFERENCES public.brands(id) ON DELETE CASCADE,
  price numeric(12,2) NOT NULL CHECK (price >= 0),
  cost_price numeric(12,2) CHECK (cost_price IS NULL OR cost_price >= 0),
  is_available boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (item_template_id, brand_id)
);

CREATE INDEX IF NOT EXISTS idx_product_variants_template
  ON public.product_variants (item_template_id);

CREATE INDEX IF NOT EXISTS idx_product_variants_brand
  ON public.product_variants (brand_id);

DROP TRIGGER IF EXISTS trg_product_variants_updated_at ON public.product_variants;
CREATE TRIGGER trg_product_variants_updated_at
  BEFORE UPDATE ON public.product_variants
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.item_aliases (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alias_text text NOT NULL,
  item_template_id uuid NOT NULL REFERENCES public.item_templates(id) ON DELETE CASCADE,
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_item_aliases_normalized
  ON public.item_aliases (lower(btrim(alias_text)));

-- ============================================================================
-- 4. Invoices & Quote Comparisons
-- ============================================================================
CREATE SEQUENCE IF NOT EXISTS public.invoice_number_seq START 1;

CREATE TABLE IF NOT EXISTS public.invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_number text NOT NULL UNIQUE DEFAULT ('INV-' || lpad(nextval('public.invoice_number_seq')::text, 5, '0')),
  status text NOT NULL DEFAULT 'quote' CHECK (status IN ('quote', 'approved')),
  comparison_group_id uuid,
  brand_id uuid REFERENCES public.brands(id) ON DELETE SET NULL,
  customer_name text NOT NULL DEFAULT '',
  customer_phone text,
  technician_name text, -- Optional; omitted from UI/PDF when null or blank
  discount_type text NOT NULL DEFAULT 'none' CHECK (discount_type IN ('none', 'fixed', 'percent')),
  discount_value numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount_value >= 0),
  subtotal numeric(12,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  total numeric(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
  notes text,
  image_paths text[] NOT NULL DEFAULT '{}',
  created_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invoices_created_at
  ON public.invoices (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_invoices_comparison_group
  ON public.invoices (comparison_group_id)
  WHERE comparison_group_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_invoices_updated_at ON public.invoices;
CREATE TRIGGER trg_invoices_updated_at
  BEFORE UPDATE ON public.invoices
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.invoice_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
  sort_order integer NOT NULL DEFAULT 0,
  raw_ocr_text text,
  item_template_id uuid REFERENCES public.item_templates(id) ON DELETE SET NULL,
  brand_id uuid REFERENCES public.brands(id) ON DELETE SET NULL,
  product_variant_id uuid REFERENCES public.product_variants(id) ON DELETE SET NULL,
  item_name text NOT NULL,
  size text,
  brand_name text,
  unit text NOT NULL DEFAULT 'قطعة',
  quantity numeric(10,2) NOT NULL CHECK (quantity > 0),
  unit_price numeric(12,2) NOT NULL CHECK (unit_price >= 0),
  line_total numeric(12,2) NOT NULL CHECK (line_total >= 0),
  confidence text NOT NULL DEFAULT 'high' CHECK (confidence IN ('high', 'medium', 'low'))
);

CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice
  ON public.invoice_items (invoice_id, sort_order);

-- ============================================================================
-- 5. Row Level Security (RLS) Policies
-- ============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.brands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.item_aliases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;

-- Profiles
CREATE POLICY profiles_select_staff ON public.profiles
  FOR SELECT USING (id = auth.uid() OR public.is_active_staff());
CREATE POLICY profiles_insert_admin ON public.profiles
  FOR INSERT WITH CHECK (public.is_admin());
CREATE POLICY profiles_update_admin ON public.profiles
  FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY profiles_delete_admin ON public.profiles
  FOR DELETE USING (public.is_admin());

-- Shop Settings
CREATE POLICY shop_settings_select_staff ON public.shop_settings
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY shop_settings_write_admin ON public.shop_settings
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Categories
CREATE POLICY categories_select_staff ON public.categories
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY categories_write_admin ON public.categories
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Brands
CREATE POLICY brands_select_staff ON public.brands
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY brands_write_admin ON public.brands
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Item Templates
CREATE POLICY item_templates_select_staff ON public.item_templates
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY item_templates_write_admin ON public.item_templates
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Product Variants
CREATE POLICY product_variants_select_staff ON public.product_variants
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY product_variants_write_admin ON public.product_variants
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Item Aliases (active staff can read & teach aliases; admin can also delete)
CREATE POLICY item_aliases_select_staff ON public.item_aliases
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY item_aliases_insert_staff ON public.item_aliases
  FOR INSERT WITH CHECK (public.is_active_staff());
CREATE POLICY item_aliases_update_staff ON public.item_aliases
  FOR UPDATE USING (public.is_active_staff()) WITH CHECK (public.is_active_staff());
CREATE POLICY item_aliases_delete_admin ON public.item_aliases
  FOR DELETE USING (public.is_admin());

-- Invoices (active staff can create/update; only admin can delete)
CREATE POLICY invoices_select_staff ON public.invoices
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY invoices_insert_staff ON public.invoices
  FOR INSERT WITH CHECK (public.is_active_staff());
CREATE POLICY invoices_update_staff ON public.invoices
  FOR UPDATE USING (public.is_active_staff()) WITH CHECK (public.is_active_staff());
CREATE POLICY invoices_delete_admin ON public.invoices
  FOR DELETE USING (public.is_admin());

-- Invoice Items (active staff can create/update/remove lines inside quotes; admin can delete freely)
CREATE POLICY invoice_items_select_staff ON public.invoice_items
  FOR SELECT USING (public.is_active_staff());
CREATE POLICY invoice_items_insert_staff ON public.invoice_items
  FOR INSERT WITH CHECK (public.is_active_staff());
CREATE POLICY invoice_items_update_staff ON public.invoice_items
  FOR UPDATE USING (public.is_active_staff()) WITH CHECK (public.is_active_staff());
CREATE POLICY invoice_items_delete_staff_or_admin ON public.invoice_items
  FOR DELETE USING (
    public.is_admin()
    OR (
      public.is_active_staff()
      AND EXISTS (
        SELECT 1 FROM public.invoices inv
        WHERE inv.id = invoice_items.invoice_id
          AND inv.status = 'quote'
      )
    )
  );

-- ============================================================================
-- 6. Private Storage Bucket for Handwritten Paper Scans
-- ============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'invoice-scans',
  'invoice-scans',
  false,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY invoice_scans_select_staff ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'invoice-scans'
    AND public.is_active_staff()
    AND (storage.foldername(name))[1] = 'shop'
  );

CREATE POLICY invoice_scans_insert_staff ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'invoice-scans'
    AND public.is_active_staff()
    AND (storage.foldername(name))[1] = 'shop'
  );

CREATE POLICY invoice_scans_delete_admin ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'invoice-scans'
    AND public.is_admin()
    AND (storage.foldername(name))[1] = 'shop'
  );
