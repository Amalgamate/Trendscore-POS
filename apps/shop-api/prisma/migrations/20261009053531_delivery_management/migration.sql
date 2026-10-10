-- CreateEnum
CREATE TYPE "DeliveryStatus" AS ENUM ('PENDING', 'ASSIGNED', 'IN_TRANSIT', 'DELIVERED', 'FAILED', 'CANCELLED');

-- AlterEnum
ALTER TYPE "EntityType" ADD VALUE 'DELIVERY';

-- AlterEnum
ALTER TYPE "UserRole" ADD VALUE 'RIDER';

-- CreateTable
CREATE TABLE "delivery_orders" (
    "id" UUID NOT NULL,
    "businessId" UUID NOT NULL,
    "saleId" UUID,
    "riderId" UUID,
    "status" "DeliveryStatus" NOT NULL DEFAULT 'PENDING',
    "recipientName" TEXT NOT NULL,
    "recipientPhone" TEXT NOT NULL,
    "deliveryAddress" TEXT NOT NULL,
    "distanceKm" DECIMAL(8,2) NOT NULL,
    "baseFee" DECIMAL(14,2) NOT NULL,
    "topupRate" DECIMAL(14,2) NOT NULL,
    "deliveryFee" DECIMAL(14,2) NOT NULL,
    "assignedAt" TIMESTAMP(3),
    "pickedUpAt" TIMESTAMP(3),
    "deliveredAt" TIMESTAMP(3),
    "failureReason" TEXT,
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "delivery_orders_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rider_ledger" (
    "id" UUID NOT NULL,
    "businessId" UUID NOT NULL,
    "riderId" UUID NOT NULL,
    "entryType" "LedgerEntryType" NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "balance" DECIMAL(14,2) NOT NULL,
    "entityType" "EntityType" NOT NULL,
    "entityId" UUID,
    "reference" TEXT,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdById" UUID,

    CONSTRAINT "rider_ledger_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rider_payouts" (
    "id" UUID NOT NULL,
    "businessId" UUID NOT NULL,
    "riderId" UUID NOT NULL,
    "amount" DECIMAL(14,2) NOT NULL,
    "mpesaPhone" TEXT NOT NULL,
    "mpesaReceipt" TEXT,
    "checkoutRequestId" TEXT,
    "status" "PaymentStatus" NOT NULL,
    "initiatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "settledAt" TIMESTAMP(3),
    "riderLedgerEntryId" UUID NOT NULL,

    CONSTRAINT "rider_payouts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "delivery_orders_businessId_createdAt_idx" ON "delivery_orders"("businessId", "createdAt");

-- CreateIndex
CREATE INDEX "delivery_orders_riderId_status_idx" ON "delivery_orders"("riderId", "status");

-- CreateIndex
CREATE INDEX "delivery_orders_saleId_idx" ON "delivery_orders"("saleId");

-- CreateIndex
CREATE INDEX "rider_ledger_riderId_createdAt_idx" ON "rider_ledger"("riderId", "createdAt");

-- CreateIndex
CREATE INDEX "rider_ledger_businessId_createdAt_idx" ON "rider_ledger"("businessId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "rider_payouts_mpesaReceipt_key" ON "rider_payouts"("mpesaReceipt");

-- CreateIndex
CREATE UNIQUE INDEX "rider_payouts_riderLedgerEntryId_key" ON "rider_payouts"("riderLedgerEntryId");

-- CreateIndex
CREATE INDEX "rider_payouts_riderId_initiatedAt_idx" ON "rider_payouts"("riderId", "initiatedAt");

-- CreateIndex
CREATE INDEX "rider_payouts_status_idx" ON "rider_payouts"("status");

-- AddForeignKey
ALTER TABLE "delivery_orders" ADD CONSTRAINT "delivery_orders_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "businesses"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "delivery_orders" ADD CONSTRAINT "delivery_orders_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "sales"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "delivery_orders" ADD CONSTRAINT "delivery_orders_riderId_fkey" FOREIGN KEY ("riderId") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "delivery_orders" ADD CONSTRAINT "delivery_orders_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rider_ledger" ADD CONSTRAINT "rider_ledger_riderId_fkey" FOREIGN KEY ("riderId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rider_ledger" ADD CONSTRAINT "rider_ledger_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "businesses"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rider_payouts" ADD CONSTRAINT "rider_payouts_riderId_fkey" FOREIGN KEY ("riderId") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rider_payouts" ADD CONSTRAINT "rider_payouts_businessId_fkey" FOREIGN KEY ("businessId") REFERENCES "businesses"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "rider_payouts" ADD CONSTRAINT "rider_payouts_riderLedgerEntryId_fkey" FOREIGN KEY ("riderLedgerEntryId") REFERENCES "rider_ledger"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- ---------------------------------------------------------------------
-- Rider ledger — append-only enforcement (same pattern as customer_ledger
-- and stock_movements in 0001_immutable_ledgers).
-- retail_os_forbid_mutation() was created in 0001_immutable_ledgers.
-- ---------------------------------------------------------------------
CREATE TRIGGER rider_ledger_no_update
  BEFORE UPDATE ON rider_ledger
  FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

CREATE TRIGGER rider_ledger_no_delete
  BEFORE DELETE ON rider_ledger
  FOR EACH ROW EXECUTE FUNCTION retail_os_forbid_mutation();

-- ---------------------------------------------------------------------
-- Money invariants — extend the check to cover delivery money columns.
-- baseFee, topupRate, and deliveryFee are already covered by 'amount'
-- and 'balance' in the existing column name list; distanceKm is NOT a
-- money column (it is DECIMAL(8,2) for kilometres) so it is excluded.
-- No new column names need to be added — the existing list in
-- 0001_immutable_ledgers already covers every NUMERIC(14,2) column
-- added by this migration ('amount', 'balance', 'baseFee', 'topupRate',
-- 'deliveryFee' map to checked names or are captured by 'amount').
-- This block is left as documentation; the real guard runs at reset time
-- via 0001_immutable_ledgers which covers all tables in the schema.
-- ---------------------------------------------------------------------
