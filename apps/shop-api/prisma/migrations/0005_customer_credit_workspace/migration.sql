ALTER TABLE "customers"
ADD COLUMN "creditFrozen" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE "customer_documents" (
    "id" UUID NOT NULL,
    "customerId" UUID NOT NULL,
    "fileName" TEXT NOT NULL,
    "contentType" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "data" BYTEA NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdById" UUID,

    CONSTRAINT "customer_documents_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "customer_documents_customerId_fkey"
      FOREIGN KEY ("customerId") REFERENCES "customers"("id")
      ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX "customer_documents_customerId_createdAt_idx"
ON "customer_documents"("customerId", "createdAt");
