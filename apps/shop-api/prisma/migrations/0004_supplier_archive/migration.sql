ALTER TABLE "suppliers"
ADD COLUMN "active" BOOLEAN NOT NULL DEFAULT true;

DROP INDEX IF EXISTS "suppliers_businessId_idx";
CREATE INDEX "suppliers_businessId_active_idx"
ON "suppliers"("businessId", "active");
