ALTER TYPE "StorefrontOrderStatus" ADD VALUE 'PAID';

CREATE TYPE "StorefrontPaymentStatus" AS ENUM (
  'PENDING',
  'SUCCEEDED',
  'FAILED',
  'UNKNOWN'
);

ALTER TABLE "sales"
  ALTER COLUMN "cashierId" DROP NOT NULL;
ALTER TABLE "storefront_orders"
  ADD COLUMN "deliveryFee" DECIMAL(14,2),
  ADD COLUMN "saleId" UUID;
ALTER TABLE "storefront_order_items"
  ADD COLUMN "vatRate" DECIMAL(5,4) NOT NULL DEFAULT 0.16;

CREATE UNIQUE INDEX "storefront_orders_saleId_key"
  ON "storefront_orders"("saleId");
ALTER TABLE "storefront_orders"
  ADD CONSTRAINT "storefront_orders_saleId_fkey"
    FOREIGN KEY ("saleId") REFERENCES "sales"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "storefront_payments" (
  "id" UUID NOT NULL,
  "orderId" UUID NOT NULL,
  "idempotencyKeyHash" VARCHAR(64) NOT NULL,
  "requestHash" VARCHAR(64) NOT NULL,
  "status" "StorefrontPaymentStatus" NOT NULL DEFAULT 'PENDING',
  "amount" DECIMAL(14,2) NOT NULL,
  "phoneNumber" TEXT NOT NULL,
  "checkoutRequestId" TEXT,
  "merchantRequestId" TEXT,
  "mpesaReceipt" TEXT,
  "callbackReceiptNumber" TEXT,
  "resultCode" TEXT,
  "resultDescription" TEXT,
  "callbackAmount" DECIMAL(14,2),
  "callbackPhoneNumber" TEXT,
  "callbackMerchantRequestId" TEXT,
  "callbackReceivedAt" TIMESTAMP(3),
  "verifiedAt" TIMESTAMP(3),
  "saleId" UUID,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "storefront_payments_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "storefront_payments_idempotencyKeyHash_key"
  ON "storefront_payments"("idempotencyKeyHash");
CREATE UNIQUE INDEX "storefront_payments_checkoutRequestId_key"
  ON "storefront_payments"("checkoutRequestId");
CREATE UNIQUE INDEX "storefront_payments_mpesaReceipt_key"
  ON "storefront_payments"("mpesaReceipt");
CREATE UNIQUE INDEX "storefront_payments_saleId_key"
  ON "storefront_payments"("saleId");
CREATE INDEX "storefront_payments_orderId_createdAt_idx"
  ON "storefront_payments"("orderId", "createdAt");
CREATE INDEX "storefront_payments_status_updatedAt_idx"
  ON "storefront_payments"("status", "updatedAt");

ALTER TABLE "storefront_payments"
  ADD CONSTRAINT "storefront_payments_orderId_fkey"
    FOREIGN KEY ("orderId") REFERENCES "storefront_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "storefront_payments_saleId_fkey"
    FOREIGN KEY ("saleId") REFERENCES "sales"("id") ON DELETE SET NULL ON UPDATE CASCADE;
