-- Phase 1: Product purge — narrow exception to the stock_movements append-only rule.
-- Drops the blanket no-delete trigger and replaces it with a guard that only allows
-- DELETE when (a) the session variable app.purge_product_id matches the row's productId
-- AND (b) the product has no rows in sale_items, purchase_items, or refund_items.

-- Drop old blanket trigger
DROP TRIGGER IF EXISTS stock_movements_no_delete ON stock_movements;

-- New guard function
CREATE OR REPLACE FUNCTION retail_os_stock_movements_purge_guard()
RETURNS TRIGGER AS $$
DECLARE
  purge_id text;
  has_history boolean;
BEGIN
  purge_id := current_setting('app.purge_product_id', true);
  IF purge_id IS NULL OR purge_id <> OLD."productId"::text THEN
    RAISE EXCEPTION
      'Table stock_movements is append-only. DELETE is not permitted. Record a reversing entry instead.'
      USING ERRCODE = 'restrict_violation';
  END IF;
  -- Reject if the product has any sales/purchase/refund history
  SELECT EXISTS (
    SELECT 1 FROM sale_items WHERE "productId" = OLD."productId"
    UNION ALL
    SELECT 1 FROM purchase_items WHERE "productId" = OLD."productId"
    UNION ALL
    SELECT 1 FROM refund_items WHERE "productId" = OLD."productId"
  ) INTO has_history;
  IF has_history THEN
    RAISE EXCEPTION
      'Cannot purge product % because it has sales, purchase, or refund history.',
      OLD."productId"
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER stock_movements_purge_guard
BEFORE DELETE ON stock_movements
FOR EACH ROW EXECUTE FUNCTION retail_os_stock_movements_purge_guard();
