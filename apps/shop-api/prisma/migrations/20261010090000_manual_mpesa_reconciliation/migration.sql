ALTER TABLE "sale_payments"
  ADD COLUMN "reference" TEXT,
  ADD COLUMN "cashTendered" DECIMAL(14,2),
  ADD COLUMN "changeDue" DECIMAL(14,2),
  ADD COLUMN "reconciledById" UUID,
  ADD COLUMN "reconciledAt" TIMESTAMP(3);

ALTER TABLE "sale_payments"
  ADD CONSTRAINT "sale_payments_reconciledById_fkey"
  FOREIGN KEY ("reconciledById") REFERENCES "users"("id")
  ON DELETE RESTRICT ON UPDATE CASCADE;

CREATE INDEX "sale_payments_reconciledById_idx"
  ON "sale_payments"("reconciledById");
