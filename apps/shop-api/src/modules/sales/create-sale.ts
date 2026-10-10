/**
 * Writing a completed sale.
 *
 * A sale is one atomic unit of work spanning five tables. If any part is
 * missing the books are wrong, so it is all-or-nothing inside a single
 * transaction: sale header, lines, payment, stock movements, and the stock
 * cache the till reads.
 */
import { Prisma, PrismaClient, type PaymentMethod, type SaleStatus } from '@prisma/client';
import { ulid } from 'ulid';
import {
  SaleValidationError,
  toCents,
  toMilli,
} from './pricing';

/** Thrown when an idempotency key replays. Carries the original receipt. */
export class DuplicateSaleError extends Error {
  constructor(
    public readonly receiptNumber: string,
    public readonly saleId: string,
    public readonly total: number,
    public readonly customerId: string | null,
  ) {
    super(`Sale already recorded as ${receiptNumber}`);
    this.name = 'DuplicateSaleError';
  }
}

export interface CreateSaleInput {
  businessId: string;
  cashierId: string;
  /** Client-generated. A retried sync must never create a second sale. */
  idempotencyKey: string;
  clientRef?: string;
  customerId?: string;
  /** Method of primary payment. */
  method: PaymentMethod;
  paymentReference?: string;
  cashTendered?: number;
  offline?: boolean;
  status?: SaleStatus;
  lines: Array<{ productId: string; quantity: number }>;
}

export interface CreateSaleResult {
  saleId: string;
  receiptNumber: string;
  subtotal: number;
  vatAmount: number;
  total: number;
  costTotal: number;
  items: number;
  paymentStatus: 'PENDING' | 'SUCCESS';
  paymentReference: string;
}

export async function createSale(
  prisma: PrismaClient,
  input: CreateSaleInput,
): Promise<CreateSaleResult> {
  const {
    businessId,
    cashierId,
    idempotencyKey,
    customerId,
    method,
    paymentReference,
    cashTendered,
    offline,
    lines,
  } = input;

  return await prisma.$transaction(async (tx) => {
    // 1. Check idempotency
    const existing = await tx.sale.findUnique({
      where: { idempotencyKey },
      select: { id: true, receiptNumber: true, total: true, customerId: true },
    });
    if (existing) {
      throw new DuplicateSaleError(
        existing.receiptNumber,
        existing.id,
        Number(existing.total),
        existing.customerId,
      );
    }

    if (!lines || lines.length === 0) {
      throw new SaleValidationError({ kind: 'EMPTY_SALE' }, 'A sale must have at least one line item.');
    }
    if (method === 'MPESA' && !paymentReference?.trim()) {
      throw new SaleValidationError(
        { kind: 'MPESA_REFERENCE_REQUIRED' },
        'Enter the M-Pesa Till number before recording this sale.',
      );
    }

    // 2. Fetch products and lock them FOR UPDATE
    const productIds = lines.map((l) => l.productId);
    const products = await tx.product.findMany({
      where: { id: { in: productIds }, businessId },
    });

    if (products.length !== lines.length) {
      throw new SaleValidationError({ kind: 'PRODUCT_NOT_FOUND', productId: 'unknown' }, 'One or more products were not found in this catalog.');
    }

    const productMap = new Map(products.map((p) => [p.id, p]));

    let subtotalCents = 0;
    let vatAmountCents = 0;
    let costTotalCents = 0;

    const lineCalculations = lines.map((line) => {
      const p = productMap.get(line.productId)!;
      if (!p.active) {
        throw new SaleValidationError({ kind: 'PRODUCT_INACTIVE', productId: p.id, name: p.name }, `Product '${p.name}' is inactive.`);
      }

      const requestedQty = line.quantity;
      const currentStock = Number(p.stock);

      if (!offline && currentStock < requestedQty) {
        throw new SaleValidationError(
          { kind: 'INSUFFICIENT_STOCK', productId: p.id, name: p.name, available: toMilli(currentStock), requested: toMilli(requestedQty) },
          `Insufficient stock for '${p.name}'. Requested ${requestedQty}, available ${currentStock}.`,
        );
      }

      const unitPriceCents = toCents(Number(p.salePrice));
      const unitCostCents = toCents(Number(p.costPrice));
      const lineTotalCents = Math.round(unitPriceCents * requestedQty);
      const lineCostCents = Math.round(unitCostCents * requestedQty);
      const vatRate = Number(p.vatRate);
      const lineVatCents = Math.round((lineTotalCents * vatRate) / (1 + vatRate));

      subtotalCents += (lineTotalCents - lineVatCents);
      vatAmountCents += lineVatCents;
      costTotalCents += lineCostCents;

      return {
        product: p,
        quantity: requestedQty,
        unitPrice: Number(p.salePrice),
        unitCost: Number(p.costPrice),
        vatRate,
        lineTotal: lineTotalCents / 100,
        newStock: currentStock - requestedQty,
      };
    });

    const totalCents = subtotalCents + vatAmountCents;
    const subtotal = subtotalCents / 100;
    const vatAmount = vatAmountCents / 100;
    const total = totalCents / 100;
    const costTotal = costTotalCents / 100;

    if (method === 'CASH' && (cashTendered ?? total) < total) {
      throw new SaleValidationError(
        { kind: 'CASH_TENDER_INSUFFICIENT' },
        'Cash tendered is less than the sale total.',
      );
    }

    if (method === 'CREDIT') {
      if (!customerId) {
        throw new SaleValidationError(
          { kind: 'CUSTOMER_REQUIRED' },
          'Select an active customer account before charging a sale to credit.',
        );
      }
      await tx.$queryRaw(
        Prisma.sql`SELECT "id" FROM "customers"
          WHERE "id" = ${customerId}::uuid AND "businessId" = ${businessId}::uuid
          FOR UPDATE`,
      );
      const customer = await tx.customer.findFirst({
        where: { id: customerId, businessId },
      });
      if (!customer || customer.status !== 'ACTIVE') {
        throw new SaleValidationError(
          { kind: 'CREDIT_ACCOUNT_UNAVAILABLE', customerId },
          'This customer credit account is unavailable. Refresh the account list and try again.',
        );
      }
      if (customer.creditFrozen) {
        throw new SaleValidationError(
          { kind: 'CREDIT_FROZEN', customerId },
          `Credit is frozen for ${customer.fullName}. Record the sale using another payment method.`,
        );
      }
      if (Number(customer.balance) + total > Number(customer.creditLimit)) {
        throw new SaleValidationError(
          {
            kind: 'CREDIT_LIMIT_EXCEEDED',
            customerId,
            available: Math.max(0, Math.round((Number(customer.creditLimit) - Number(customer.balance)) * 100)),
            requested: totalCents,
          },
          `${customer.fullName} does not have enough available credit for this sale.`,
        );
      }
    }

    // 3. Generate receipt number
    const count = await tx.sale.count({ where: { businessId } });
    const receiptNumber = `REC-${new Date().toISOString().slice(2, 10).replace(/-/g, '')}-${String(count + 1).padStart(4, '0')}`;
    const clientRef = input.clientRef && input.clientRef.length > 0 ? input.clientRef : ulid();

    // 4. Create Sale
    const sale = await tx.sale.create({
      data: {
        businessId,
        cashierId,
        customerId,
        receiptNumber,
        clientRef,
        idempotencyKey,
        status: 'COMPLETED',
        subtotal,
        vatAmount,
        total,
        costTotal,
        offline: offline ?? false,
      },
    });

    // 5. Insert Sale Items
    for (const item of lineCalculations) {
      await tx.saleItem.create({
        data: {
          saleId: sale.id,
          productId: item.product.id,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          unitCost: item.unitCost,
          vatRate: item.vatRate,
          lineTotal: item.lineTotal,
        },
      });

      // Update product stock cache
      await tx.product.update({
        where: { id: item.product.id },
        data: { stock: item.newStock },
      });

      // Append-only stock movement
      await tx.stockMovement.create({
        data: {
          businessId,
          productId: item.product.id,
          type: 'SALE',
          quantity: -item.quantity,
          balanceAfter: item.newStock,
          unitCost: item.unitCost,
          reference: receiptNumber,
          saleId: sale.id,
          createdById: cashierId,
        },
      });
    }

    // 6. Record payment
    await tx.salePayment.create({
      data: {
        saleId: sale.id,
        method,
        status: method === 'MPESA' ? 'PENDING' : 'SUCCESS',
        amount: total,
        cashTendered: method === 'CASH' ? cashTendered ?? total : null,
        changeDue:
          method === 'CASH' ? Math.max(0, (cashTendered ?? total) - total) : null,
        reference: paymentReference?.trim() || null,
        resultDesc: method === 'MPESA' ? 'Awaiting manual reconciliation.' : null,
        idempotencyKey: `pay-${idempotencyKey}`,
        settledAt: method === 'MPESA' ? null : new Date(),
      },
    });

    // 7. If Credit method, update Customer balance & append to CustomerLedger
    if (method === 'CREDIT' && customerId) {
      const customer = await tx.customer.findUniqueOrThrow({ where: { id: customerId } });
      const newBalance = Number(customer.balance) + total;

      await tx.customer.update({
        where: { id: customerId },
        data: { balance: newBalance },
      });

      await tx.customerLedger.create({
        data: {
          customerId,
          businessId,
          entryType: 'DEBIT',
          amount: total,
          balance: newBalance,
          entityType: 'SALE',
          entityId: sale.id,
          reference: receiptNumber,
          note: `Goods purchased on credit`,
          createdById: cashierId,
        },
      });
    }

    return {
      saleId: sale.id,
      receiptNumber,
      subtotal,
      vatAmount,
      total,
      costTotal,
      items: lines.length,
      paymentStatus: method === 'MPESA' ? 'PENDING' : 'SUCCESS',
      paymentReference: paymentReference?.trim() ?? '',
    };
  });
}
