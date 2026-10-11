ALTER TABLE "users"
  ADD COLUMN "riderLocationConsentAt" TIMESTAMP(3),
  ADD COLUMN "riderLocationConsentRevokedAt" TIMESTAMP(3);

CREATE TABLE "rider_locations" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "deliveryOrderId" UUID NOT NULL,
  "riderId" UUID NOT NULL,
  "latitude" DECIMAL(9,6) NOT NULL,
  "longitude" DECIMAL(9,6) NOT NULL,
  "accuracy" DECIMAL(8,2) NOT NULL,
  "recordedAt" TIMESTAMP(3) NOT NULL,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "rider_locations_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "rider_locations_deliveryOrderId_key" ON "rider_locations"("deliveryOrderId");
CREATE INDEX "rider_locations_businessId_recordedAt_idx" ON "rider_locations"("businessId", "recordedAt");
CREATE INDEX "rider_locations_riderId_recordedAt_idx" ON "rider_locations"("riderId", "recordedAt");

ALTER TABLE "rider_locations"
  ADD CONSTRAINT "rider_locations_businessId_fkey"
    FOREIGN KEY ("businessId") REFERENCES "businesses"("id") ON DELETE RESTRICT ON UPDATE CASCADE,
  ADD CONSTRAINT "rider_locations_deliveryOrderId_fkey"
    FOREIGN KEY ("deliveryOrderId") REFERENCES "delivery_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "rider_locations_riderId_fkey"
    FOREIGN KEY ("riderId") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
