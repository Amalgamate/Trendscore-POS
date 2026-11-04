ALTER TABLE "products"
  ADD COLUMN "purchaseContainerName" TEXT,
  ADD COLUMN "purchaseContainerSize" DECIMAL(14,3),
  ADD COLUMN "quickQuantityPresets" JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE "sale_items"
  ADD COLUMN "soldQuantity" DECIMAL(14,3),
  ADD COLUMN "soldUnit" TEXT;

UPDATE "sale_items" AS item
SET "soldQuantity" = item."quantity",
    "soldUnit" = product."unit"
FROM "products" AS product
WHERE product."id" = item."productId";

ALTER TABLE "sale_items"
  ALTER COLUMN "soldQuantity" SET NOT NULL,
  ALTER COLUMN "soldUnit" SET NOT NULL;
