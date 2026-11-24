-- Merge 'وصلات صرف' category into 'صرف' so all drainage items appear under 'صرف'.

DO $$
DECLARE
  v_target_id uuid;
  v_old_id uuid;
BEGIN
  SELECT id INTO v_old_id
  FROM public.categories
  WHERE name = 'وصلات صرف'
  LIMIT 1;

  IF v_old_id IS NOT NULL THEN
    SELECT id INTO v_target_id
    FROM public.categories
    WHERE name = 'صرف'
    LIMIT 1;

    IF v_target_id IS NULL THEN
      UPDATE public.categories
      SET name = 'صرف'
      WHERE id = v_old_id;
    ELSE
      UPDATE public.item_templates
      SET category_id = v_target_id
      WHERE category_id = v_old_id;

      DELETE FROM public.categories
      WHERE id = v_old_id;
    END IF;
  END IF;
END $$;
