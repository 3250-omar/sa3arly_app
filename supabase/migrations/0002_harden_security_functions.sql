-- 0002_harden_security_functions.sql
-- Move SECURITY DEFINER auth helper functions out of exposed public schema into private schema,
-- revoke public/anon execution on handle_new_user, lock search_path on set_updated_at,
-- and scope all RLS policies explicitly TO authenticated.

-- 1. Fix mutable search_path on set_updated_at
ALTER FUNCTION public.set_updated_at() SET search_path = public;

-- 2. Restrict handle_new_user trigger function from RPC execution
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;

-- 3. Create non-exposed private schema for auth helper functions
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;

CREATE OR REPLACE FUNCTION private.is_active_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = (SELECT auth.uid())
      AND is_active = true
  );
$$;

CREATE OR REPLACE FUNCTION private.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = (SELECT auth.uid())
      AND is_active = true
      AND role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION private.is_active_staff() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_active_staff() TO authenticated;

REVOKE ALL ON FUNCTION private.is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.is_admin() TO authenticated;

-- 4. Recreate RLS policies TO authenticated using private helpers

-- Profiles
DROP POLICY IF EXISTS profiles_select_staff ON public.profiles;
DROP POLICY IF EXISTS profiles_insert_admin ON public.profiles;
DROP POLICY IF EXISTS profiles_update_admin ON public.profiles;
DROP POLICY IF EXISTS profiles_delete_admin ON public.profiles;

CREATE POLICY profiles_select_staff ON public.profiles
  FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()) OR private.is_active_staff());
CREATE POLICY profiles_insert_admin ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (private.is_admin());
CREATE POLICY profiles_update_admin ON public.profiles
  FOR UPDATE TO authenticated
  USING (private.is_admin()) WITH CHECK (private.is_admin());
CREATE POLICY profiles_delete_admin ON public.profiles
  FOR DELETE TO authenticated
  USING (private.is_admin());

-- Shop Settings
DROP POLICY IF EXISTS shop_settings_select_staff ON public.shop_settings;
DROP POLICY IF EXISTS shop_settings_write_admin ON public.shop_settings;

CREATE POLICY shop_settings_select_staff ON public.shop_settings
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY shop_settings_write_admin ON public.shop_settings
  FOR ALL TO authenticated
  USING (private.is_admin()) WITH CHECK (private.is_admin());

-- Categories
DROP POLICY IF EXISTS categories_select_staff ON public.categories;
DROP POLICY IF EXISTS categories_write_admin ON public.categories;

CREATE POLICY categories_select_staff ON public.categories
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY categories_write_admin ON public.categories
  FOR ALL TO authenticated
  USING (private.is_admin()) WITH CHECK (private.is_admin());

-- Brands
DROP POLICY IF EXISTS brands_select_staff ON public.brands;
DROP POLICY IF EXISTS brands_write_admin ON public.brands;

CREATE POLICY brands_select_staff ON public.brands
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY brands_write_admin ON public.brands
  FOR ALL TO authenticated
  USING (private.is_admin()) WITH CHECK (private.is_admin());

-- Item Templates
DROP POLICY IF EXISTS item_templates_select_staff ON public.item_templates;
DROP POLICY IF EXISTS item_templates_write_admin ON public.item_templates;

CREATE POLICY item_templates_select_staff ON public.item_templates
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY item_templates_write_admin ON public.item_templates
  FOR ALL TO authenticated
  USING (private.is_admin()) WITH CHECK (private.is_admin());

-- Product Variants
DROP POLICY IF EXISTS product_variants_select_staff ON public.product_variants;
DROP POLICY IF EXISTS product_variants_write_admin ON public.product_variants;

CREATE POLICY product_variants_select_staff ON public.product_variants
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY product_variants_write_admin ON public.product_variants
  FOR ALL TO authenticated
  USING (private.is_admin()) WITH CHECK (private.is_admin());

-- Item Aliases
DROP POLICY IF EXISTS item_aliases_select_staff ON public.item_aliases;
DROP POLICY IF EXISTS item_aliases_insert_staff ON public.item_aliases;
DROP POLICY IF EXISTS item_aliases_update_staff ON public.item_aliases;
DROP POLICY IF EXISTS item_aliases_delete_admin ON public.item_aliases;

CREATE POLICY item_aliases_select_staff ON public.item_aliases
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY item_aliases_insert_staff ON public.item_aliases
  FOR INSERT TO authenticated
  WITH CHECK (private.is_active_staff());
CREATE POLICY item_aliases_update_staff ON public.item_aliases
  FOR UPDATE TO authenticated
  USING (private.is_active_staff()) WITH CHECK (private.is_active_staff());
CREATE POLICY item_aliases_delete_admin ON public.item_aliases
  FOR DELETE TO authenticated
  USING (private.is_admin());

-- Invoices
DROP POLICY IF EXISTS invoices_select_staff ON public.invoices;
DROP POLICY IF EXISTS invoices_insert_staff ON public.invoices;
DROP POLICY IF EXISTS invoices_update_staff ON public.invoices;
DROP POLICY IF EXISTS invoices_delete_admin ON public.invoices;

CREATE POLICY invoices_select_staff ON public.invoices
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY invoices_insert_staff ON public.invoices
  FOR INSERT TO authenticated
  WITH CHECK (private.is_active_staff());
CREATE POLICY invoices_update_staff ON public.invoices
  FOR UPDATE TO authenticated
  USING (private.is_active_staff()) WITH CHECK (private.is_active_staff());
CREATE POLICY invoices_delete_admin ON public.invoices
  FOR DELETE TO authenticated
  USING (private.is_admin());

-- Invoice Items
DROP POLICY IF EXISTS invoice_items_select_staff ON public.invoice_items;
DROP POLICY IF EXISTS invoice_items_insert_staff ON public.invoice_items;
DROP POLICY IF EXISTS invoice_items_update_staff ON public.invoice_items;
DROP POLICY IF EXISTS invoice_items_delete_staff_or_admin ON public.invoice_items;

CREATE POLICY invoice_items_select_staff ON public.invoice_items
  FOR SELECT TO authenticated
  USING (private.is_active_staff());
CREATE POLICY invoice_items_insert_staff ON public.invoice_items
  FOR INSERT TO authenticated
  WITH CHECK (private.is_active_staff());
CREATE POLICY invoice_items_update_staff ON public.invoice_items
  FOR UPDATE TO authenticated
  USING (private.is_active_staff()) WITH CHECK (private.is_active_staff());
CREATE POLICY invoice_items_delete_staff_or_admin ON public.invoice_items
  FOR DELETE TO authenticated
  USING (
    private.is_admin()
    OR (
      private.is_active_staff()
      AND EXISTS (
        SELECT 1 FROM public.invoices inv
        WHERE inv.id = invoice_items.invoice_id
          AND inv.status = 'quote'
      )
    )
  );

-- Storage objects (invoice-scans bucket)
DROP POLICY IF EXISTS invoice_scans_select_staff ON storage.objects;
DROP POLICY IF EXISTS invoice_scans_insert_staff ON storage.objects;
DROP POLICY IF EXISTS invoice_scans_delete_admin ON storage.objects;

CREATE POLICY invoice_scans_select_staff ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'invoice-scans'
    AND private.is_active_staff()
    AND (storage.foldername(name))[1] = 'shop'
  );

CREATE POLICY invoice_scans_insert_staff ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'invoice-scans'
    AND private.is_active_staff()
    AND (storage.foldername(name))[1] = 'shop'
  );

CREATE POLICY invoice_scans_delete_admin ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'invoice-scans'
    AND private.is_admin()
    AND (storage.foldername(name))[1] = 'shop'
  );

-- 5. Drop old exposed public helper functions
DROP FUNCTION IF EXISTS public.is_active_staff();
DROP FUNCTION IF EXISTS public.is_admin();
