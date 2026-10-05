-- Immutable financial records — Retail OS
--
-- The product promise is "nothing goes untracked". Application-level
-- discipline is not enough: a single careless UPDATE or DELETE on a
-- ledger table would corrupt the shop's financial history with no trace.
-- These triggers enforce immutability in the database itself, so the
-- guarantee holds regardless of which code path touched the table.
--
-- Applied to every provisioned shop instance.

-- ---------------------------------------------------------------------
-- Guard function: reject UPDATE/DELETE on append-only tables.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION retail_os_forbid_mutation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION
    'Table % is append-only. % is not permitted. Record a reversing entry instead.',
    TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'restrict_violation';
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- Customer ledger — a customer's balance history is never rewritten.
-- ---------------------------------------------------------------------
CREATE TRIGGER customer_ledger_no_update
BEFORE UPDATE ON customer_ledger
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

CREATE TRIGGER customer_ledger_no_delete
BEFORE DELETE ON customer_ledger
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

-- ---------------------------------------------------------------------
-- Stock movements — every quantity change is permanent history.
-- ---------------------------------------------------------------------
CREATE TRIGGER stock_movements_no_update
BEFORE UPDATE ON stock_movements
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

CREATE TRIGGER stock_movements_no_delete
BEFORE DELETE ON stock_movements
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

-- ---------------------------------------------------------------------
-- Audit log — append-only by definition.
-- ---------------------------------------------------------------------
CREATE TRIGGER audit_logs_no_update
BEFORE UPDATE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

CREATE TRIGGER audit_logs_no_delete
BEFORE DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

-- ---------------------------------------------------------------------
-- Cash movements — cash in/out history underpins variance detection.
-- ---------------------------------------------------------------------
CREATE TRIGGER cash_movements_no_update
BEFORE UPDATE ON cash_movements
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

CREATE TRIGGER cash_movements_no_delete
BEFORE DELETE ON cash_movements
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

-- ---------------------------------------------------------------------
-- Sale payments — settled payment facts never change. A late M-Pesa
-- settlement is recorded as a NEW row pointing at the original via
-- reversalOfId, never as an UPDATE.
-- ---------------------------------------------------------------------
CREATE TRIGGER sale_payments_no_delete
BEFORE DELETE ON sale_payments
FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

-- ---------------------------------------------------------------------
-- Money invariants. Floating point never touches a financial column:
-- assert every money-typed column is NUMERIC, so a bad migration cannot
-- quietly introduce a float into the ledger.
-- ---------------------------------------------------------------------
DO $$
DECLARE
  offending text;
BEGIN
  -- Column names match the Prisma-generated schema (camelCase, no @map).
  -- This list must stay in sync with prisma/schema.prisma: a silent
  -- mismatch would make this check a no-op that always passes, which is
  -- worse than having no check at all.
  SELECT string_agg(format('%I.%I is %s', table_name, column_name, udt_name), ', ')
    INTO offending
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND column_name IN (
      'subtotal', 'discount', 'vatAmount', 'total', 'costTotal',
      'amount', 'balance', 'creditLimit', 'openingCash', 'cashSales',
      'cashRefunds', 'debtPayments', 'cashExpenses', 'dropsToBank',
      'otherIn', 'otherOut', 'expectedCash', 'countedCash', 'variance',
      'costPrice', 'salePrice', 'unitCost', 'unitPrice', 'lineTotal',
      'paid', 'quantity', 'stock', 'balanceAfter',
      'lowStockThreshold', 'approvalThreshold', 'vatRate'
    )
    AND data_type <> 'numeric'
    AND udt_name <> 'money';

  IF offending IS NOT NULL THEN
    RAISE EXCEPTION 'Financial columns must be NUMERIC, never float: %', offending;
  END IF;
END;
$$;
