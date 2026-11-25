-- Add payment collection tracking fields to public.invoices
ALTER TABLE public.invoices
  ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'cash'
    CHECK (payment_method IN ('cash', 'partial_now_rest_later', 'deferred_no_deposit', 'deferred_with_deposit')),
  ADD COLUMN IF NOT EXISTS paid_amount numeric(12,2) NOT NULL DEFAULT 0
    CHECK (paid_amount >= 0),
  ADD COLUMN IF NOT EXISTS payment_due_date date;
