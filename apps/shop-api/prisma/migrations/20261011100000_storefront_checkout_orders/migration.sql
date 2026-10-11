ALTER TYPE "StockMovementType" ADD VALUE 'STOREFRONT_RESERVATION';
ALTER TYPE "StockMovementType" ADD VALUE 'STOREFRONT_RELEASE';

CREATE TYPE "StorefrontOrderStatus" AS ENUM (
  'AWAITING_PAYMENT',
  'CANCELLED',
  'EXPIRED'
);

CREATE TYPE "StorefrontFulfillmentMethod" AS ENUM ('DELIVERY', 'PICKUP');

CREATE TABLE "storefront_orders" (
  "id" UUID NOT NULL,
  "businessId" UUID NOT NULL,
  "orderNumber" TEXT NOT NULL,
  "idempotencyKeyHash" VARCHAR(64) NOT NULL,
  "requestHash" VARCHAR(64) NOT NULL,
  "customerName" TEXT NOT NULL,
  "customerPhone" TEXT NOT NULL,
  "customerEmail" TEXT,
  "fulfillmentMethod" "StorefrontFulfillmentMethod" NOT NULL,
  "deliveryAddress" TEXT,
  "subtotal" DECIMAL(14,2) NOT NULL,
  "total" DECIMAL(14,2) NOT NULL,
  "status" "StorefrontOrderStatus" NOT NULL DEFAULT 'AWAITING_PAYMENT',
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "storefront_orders_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "storefront_order_items" (
  "id" UUID NOT NULL,
  "orderId" UUID NOT NULL,
  "productId" UUID NOT NULL,
  "productName" TEXT NOT NULL,
  "variantLabel" TEXT,
  "quantity" DECIMAL(14,3) NOT NULL,
  "unitPrice" DECIMAL(14,2) NOT NULL,
  "unitCost" DECIMAL(14,2) NOT NULL,
  "lineTotal" DECIMAL(14,2) NOT NULL,
  CONSTRAINT "storefront_order_items_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "storefront_order_events" (
  "id" UUID NOT NULL,
  "orderId" UUID NOT NULL,
  "fromStatus" "StorefrontOrderStatus",
  "toStatus" "StorefrontOrderStatus" NOT NULL,
  "detail" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "storefront_order_events_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "storefront_orders_orderNumber_key"
  ON "storefront_orders"("orderNumber");
CREATE UNIQUE INDEX "storefront_orders_idempotencyKeyHash_key"
  ON "storefront_orders"("idempotencyKeyHash");
CREATE INDEX "storefront_orders_businessId_createdAt_idx"
  ON "storefront_orders"("businessId", "createdAt");
CREATE INDEX "storefront_orders_businessId_status_expiresAt_idx"
  ON "storefront_orders"("businessId", "status", "expiresAt");
CREATE INDEX "storefront_order_items_orderId_idx"
  ON "storefront_order_items"("orderId");
CREATE INDEX "storefront_order_items_productId_idx"
  ON "storefront_order_items"("productId");
CREATE INDEX "storefront_order_events_orderId_createdAt_idx"
  ON "storefront_order_events"("orderId", "createdAt");

ALTER TABLE "storefront_orders"
  ADD CONSTRAINT "storefront_orders_businessId_fkey"
    FOREIGN KEY ("businessId") REFERENCES "businesses"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "storefront_order_items"
  ADD CONSTRAINT "storefront_order_items_orderId_fkey"
    FOREIGN KEY ("orderId") REFERENCES "storefront_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT "storefront_order_items_productId_fkey"
    FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

ALTER TABLE "storefront_order_events"
  ADD CONSTRAINT "storefront_order_events_orderId_fkey"
    FOREIGN KEY ("orderId") REFERENCES "storefront_orders"("id") ON DELETE CASCADE ON UPDATE CASCADE;
