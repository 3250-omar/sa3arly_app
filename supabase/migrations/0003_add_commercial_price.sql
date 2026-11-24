-- 0003_add_commercial_price.sql
-- Adds commercial_price column to existing product_variants table (no new table).

ALTER TABLE public.product_variants
  ADD COLUMN IF NOT EXISTS commercial_price numeric(12,2)
  CHECK (commercial_price IS NULL OR commercial_price >= 0);
