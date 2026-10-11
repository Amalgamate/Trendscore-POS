ALTER TABLE "storefront_orders"
  ADD COLUMN "deliveryFeeQuotedAt" TIMESTAMP(3),
  ADD COLUMN "deliveryFeeAcceptedAt" TIMESTAMP(3);
