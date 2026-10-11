ALTER TABLE "products"
  ADD COLUMN "description" TEXT,
  ADD COLUMN "notes" TEXT,
  ADD COLUMN "groupId" TEXT,
  ADD COLUMN "variantLabel" TEXT,
  ADD COLUMN "isPublished" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "publishedAt" TIMESTAMP(3);

CREATE INDEX "products_businessId_isPublished_active_idx"
  ON "products"("businessId", "isPublished", "active");

CREATE TABLE "product_images" (
  "id" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "imageData" TEXT NOT NULL,
  "altText" TEXT,
  "position" INTEGER NOT NULL DEFAULT 0,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "product_images_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "product_images_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "products"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "product_images_productId_position_key"
  ON "product_images"("productId", "position");
