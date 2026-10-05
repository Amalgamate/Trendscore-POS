-- Verification for migration 0001_immutable_ledgers.
--
-- Proves the append-only guarantee actually holds in the database, not
-- just in application code. Run with:
--   psql -f apps/shop-api/prisma/verify-immutability.sql
--
-- Each check FAILS the script if the database permitted a mutation that
-- the product promises is impossible.

\set ON_ERROR_STOP on
BEGIN;

-- Minimal fixtures.
INSERT INTO businesses (id, name, slug, "createdAt", "updatedAt")
VALUES ('11111111-1111-1111-1111-111111111111', 'Test Shop', 'test-shop', now(), now());

INSERT INTO customers (id, "businessId", "fullName", "createdAt", "updatedAt")
VALUES ('22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111', 'John Kamau', now(), now());

INSERT INTO customer_ledger
  (id, "customerId", "businessId", "entryType", amount, balance, "entityType", "createdAt")
VALUES ('33333333-3333-3333-3333-333333333333',
        '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        'DEBIT', 2500.00, 2500.00, 'SALE', now());

\echo '--- 1. ledger UPDATE must be rejected ---'
DO $$
BEGIN
  BEGIN
    UPDATE customer_ledger SET amount = 1.00
      WHERE id = '33333333-3333-3333-3333-333333333333';
    RAISE EXCEPTION 'FAIL: customer_ledger UPDATE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: ledger UPDATE blocked';
  END;
END;
$$;

\echo '--- 2. ledger DELETE must be rejected ---'
DO $$
BEGIN
  BEGIN
    DELETE FROM customer_ledger WHERE id = '33333333-3333-3333-3333-333333333333';
    RAISE EXCEPTION 'FAIL: customer_ledger DELETE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: ledger DELETE blocked';
  END;
END;
$$;

\echo '--- 3. stock_movements DELETE must be rejected ---'
-- A real row must exist: BEFORE ... FOR EACH ROW triggers do not fire on
-- an empty table, so testing against an empty table proves nothing.
INSERT INTO products (id, "businessId", name, "salePrice", "costPrice",
                      stock, "createdAt", "updatedAt")
VALUES ('55555555-5555-5555-5555-555555555555',
        '11111111-1111-1111-1111-111111111111', 'Milk 1L', 140.00, 120.00,
        10, now(), now());

INSERT INTO stock_movements
  (id, "businessId", "productId", type, quantity, "balanceAfter", "createdAt")
VALUES ('66666666-6666-6666-6666-666666666666',
        '11111111-1111-1111-1111-111111111111',
        '55555555-5555-5555-5555-555555555555',
        'PURCHASE', 10, 10, now());

DO $$
BEGIN
  BEGIN
    DELETE FROM stock_movements WHERE id = '66666666-6666-6666-6666-666666666666';
    RAISE EXCEPTION 'FAIL: stock_movements DELETE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: stock_movements DELETE blocked';
  END;
END;
$$;

\echo '--- 3b. stock_movements UPDATE must be rejected ---'
DO $$
BEGIN
  BEGIN
    UPDATE stock_movements SET quantity = 999
      WHERE id = '66666666-6666-6666-6666-666666666666';
    RAISE EXCEPTION 'FAIL: stock_movements UPDATE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: stock_movements UPDATE blocked';
  END;
END;
$$;

\echo '--- 3c. sale_payments DELETE must be rejected ---'
-- Needs a real row: sale_payments requires a full sale to satisfy FKs.
INSERT INTO users (id, "fullName", phone, "pinHash", role, "createdAt", "updatedAt")
VALUES ('77777777-7777-7777-7777-777777777777', 'James', '0700000000', 'hash', 'OWNER', now(), now());

INSERT INTO sales
  (id, "businessId", "receiptNumber", "cashierId", "clientRef", "idempotencyKey",
   status, subtotal, total, "createdAt", "updatedAt")
VALUES ('88888888-8888-8888-8888-888888888888',
        '11111111-1111-1111-1111-111111111111', 'RCP-0001',
        '77777777-7777-7777-7777-777777777777', 'ULID-TEST-1', 'idem-test-1',
        'COMPLETED', 500.00, 500.00, now(), now());

INSERT INTO sale_payments (id, "saleId", method, status, amount, "idempotencyKey", "createdAt", "updatedAt")
VALUES ('99999999-9999-9999-9999-999999999999',
        '88888888-8888-8888-8888-888888888888', 'MPESA', 'SUCCESS', 500.00,
        'mpesa-idem-1', now(), now());

DO $$
BEGIN
  BEGIN
    DELETE FROM sale_payments WHERE id = '99999999-9999-9999-9999-999999999999';
    RAISE EXCEPTION 'FAIL: sale_payments DELETE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: sale_payments DELETE blocked';
  END;
END;
$$;

\echo '--- 4. audit_logs UPDATE must be rejected ---'
INSERT INTO audit_logs (id, "businessId", action, "entityType", "createdAt")
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111', 'SALE_CREATED', 'SALE', now());

DO $$
BEGIN
  BEGIN
    UPDATE audit_logs SET action = 'tampered'
      WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'FAIL: audit_logs UPDATE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: audit_logs UPDATE blocked';
  END;
END;
$$;

\echo '--- 4b. audit_logs DELETE must be rejected ---'
DO $$
BEGIN
  BEGIN
    DELETE FROM audit_logs WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
    RAISE EXCEPTION 'FAIL: audit_logs DELETE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: audit_logs DELETE blocked';
  END;
END;
$$;

\echo '--- 4c. cash_movements DELETE must be rejected ---'
INSERT INTO cash_sessions (id, "businessId", "cashierId", status, "openingCash", "openedAt")
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        '11111111-1111-1111-1111-111111111111',
        '77777777-7777-7777-7777-777777777777', 'OPEN', 5000.00, now());

INSERT INTO cash_movements (id, "businessId", "cashSessionId", type, direction,
                            amount, reason, "createdById", "createdAt")
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc',
        '11111111-1111-1111-1111-111111111111',
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'PAID_IN', 'CREDIT', 5000.00,
        'Opening float', '77777777-7777-7777-7777-777777777777', now());

DO $$
BEGIN
  BEGIN
    DELETE FROM cash_movements WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
    RAISE EXCEPTION 'FAIL: cash_movements DELETE was allowed';
  EXCEPTION WHEN restrict_violation THEN
    RAISE NOTICE 'PASS: cash_movements DELETE blocked';
  END;
END;
$$;

\echo '--- 5. INSERT into the ledger must still work ---'
INSERT INTO customer_ledger
  (id, "customerId", "businessId", "entryType", amount, balance, "entityType", "createdAt")
VALUES ('44444444-4444-4444-4444-444444444444',
        '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        'CREDIT', 1000.00, 1500.00, 'CUSTOMER_PAYMENT', now());
SELECT 'PASS: reversing/credit entry appended' AS result;

ROLLBACK;
\echo 'All immutability checks passed.'
