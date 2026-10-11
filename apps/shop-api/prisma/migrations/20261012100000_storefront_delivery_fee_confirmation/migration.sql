ALTER TABLE "storefront_orders"
  ADD COLUMN "deliveryFee" DECIMAL(14,2),
  ADD COLUMN "deliveryFeeQuotedAt" TIMESTAMP(3),
  ADD COLUMN "deliveryFeeAcceptedAt" TIMESTAMP(3);
