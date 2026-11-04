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
import argon2 from 'argon2';
import {
  SaleValidationError,
  toCents,
  toMilli,
} from './pricing';
import { toBaseQuantity, UnitConversionError } from './measured-units';

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
  customerName?: string;
  /** Owner/manager authorization for a sale that leaves stock negative. */
  stockOverride?: { approverId: string; pin: string };
  /** Method of primary payment. */
  method: PaymentMethod;
  paymentReference?: string;
  cashTendered?: number;
  offline?: boolean;
  status?: SaleStatus;
  lines: Array<{ productId: string; quantity: number; unit?: string }>;
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
  /** Authoritative server balance after a credit sale. */
  customerBalance?: number;
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
    customerName,
    stockOverride,
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

    // Lock stock rows in a stable order before reading balances so POS sales
    // serialize with storefront reservations and other inventory mutations.
    const productIds = [...new Set(lines.map((line) => line.productId))].sort();
    await tx.$queryRaw(
      Prisma.sql`SELECT "id" FROM "products"
        WHERE "businessId" = ${businessId}::uuid
          AND "id" IN (${Prisma.join(productIds.map((id) => Prisma.sql`${id}::uuid`))})
        ORDER BY "id"
        FOR UPDATE`,
    );
    const products = await tx.product.findMany({
      where: { id: { in: productIds }, businessId },
    });

    if (products.length !== lines.length) {
      throw new SaleValidationError({ kind: 'PRODUCT_NOT_FOUND', productId: 'unknown' }, 'One or more products were not found in this catalog.');
    }

    const productMap = new Map(products.map((p) => [p.id, p]));

    let stockApprover: { id: string; fullName: string } | null = null;
    if (stockOverride) {
      const candidate = await tx.user.findFirst({
        where: {
          id: stockOverride.approverId,
          active: true,
          role: { in: ['OWNER', 'MANAGER'] },
        },
        select: { id: true, fullName: true, pinHash: true },
      });
      if (!candidate || !(await argon2.verify(candidate.pinHash, stockOverride.pin))) {
        throw new SaleValidationError(
          { kind: 'STOCK_OVERRIDE_DENIED' },
          'A valid Owner or Manager PIN is required to approve this stock override.',
        );
      }
      stockApprover = { id: candidate.id, fullName: candidate.fullName };
    }

    let subtotalCents = 0;
    let vatAmountCents = 0;
    let costTotalCents = 0;

    const lineCalculations = lines.map((line) => {
      const p = productMap.get(line.productId)!;
      if (!p.active) {
        throw new SaleValidationError({ kind: 'PRODUCT_INACTIVE', productId: p.id, name: p.name }, `Product '${p.name}' is inactive.`);
      }

      let requestedMilli: number;
      try {
        requestedMilli = line.unit
          ? toBaseQuantity(line.quantity, line.unit, p.unit)
          : toMilli(line.quantity);
      } catch (error) {
        if (error instanceof UnitConversionError) {
          throw new SaleValidationError(
            { kind: 'QUANTITY_NOT_POSITIVE', productId: p.id, requested: line.quantity },
            error.message,
          );
        }
        throw error;
      }
      const requestedQty = requestedMilli / 1000;
      const currentMilli = toMilli(p.stock.toString());
      const currentStock = currentMilli / 1000;

      if (!offline && currentStock < requestedQty && !stockApprover) {
        throw new SaleValidationError(
          { kind: 'INSUFFICIENT_STOCK', productId: p.id, name: p.name, available: toMilli(currentStock), requested: toMilli(requestedQty) },
          `Insufficient stock for '${p.name}'. Requested ${requestedQty}, available ${currentStock}.`,
        );
      }

      const unitPriceCents = toCents(p.salePrice.toString());
      const unitCostCents = toCents(p.costPrice.toString());
      // Price and quantity are integer cents and milli-units. Round half-up
      // once at the line boundary, without binary floating point.
      const lineTotalCents = Math.floor(
        (unitPriceCents * requestedMilli + 500) / 1000,
      );
      const lineCostCents = Math.floor(
        (unitCostCents * requestedMilli + 500) / 1000,
      );
      const vatRate = Number(p.vatRate);
      const lineVatCents = Math.round((lineTotalCents * vatRate) / (1 + vatRate));

      subtotalCents += (lineTotalCents - lineVatCents);
      vatAmountCents += lineVatCents;
      costTotalCents += lineCostCents;

      return {
        product: p,
        quantity: requestedQty,
        soldQuantity: line.quantity,
        soldUnit: line.unit ?? p.unit,
        unitPrice: Number(p.salePrice),
        unitCost: Number(p.costPrice),
        vatRate,
        lineTotal: lineTotalCents / 100,
        newStock: new Prisma.Decimal(p.stock.toString()).minus(new Prisma.Decimal(requestedMilli).div(1000)),
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

    let customerBalance: number | undefined;
    let receiptCustomerName = customerName?.trim() || undefined;
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
      receiptCustomerName ??= customer.fullName;
      if (customer.creditFrozen) {
        throw new SaleValidationError(
          { kind: 'CREDIT_FROZEN', customerId },
          `Credit is frozen for ${customer.fullName}. Record the sale using another payment method.`,
        );
      }
      const balanceCents = toCents(customer.balance.toString());
      const creditLimitCents = toCents(customer.creditLimit.toString());
      if (balanceCents + totalCents > creditLimitCents) {
        throw new SaleValidationError(
          {
            kind: 'CREDIT_LIMIT_EXCEEDED',
            customerId,
            available: Math.max(0, creditLimitCents - balanceCents),
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
    if (!receiptCustomerName && customerId) {
      const customer = await tx.customer.findFirst({
        where: { id: customerId, businessId },
        select: { fullName: true },
      });
      receiptCustomerName = customer?.fullName;
    }

    const sale = await tx.sale.create({
      data: {
        businessId,
        cashierId,
        customerId,
        customerName: receiptCustomerName,
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
          soldQuantity: item.soldQuantity,
          soldUnit: item.soldUnit,
          unitPrice: item.unitPrice,
          unitCost: item.unitCost,
          vatRate: item.vatRate,
          lineTotal: item.lineTotal,
        },
      });

      // Update product stock cache
      const changed = await tx.product.updateMany({
        where: {
          id: item.product.id,
          businessId,
          stock: { gte: item.quantity },
        },
        data: {
          stock: { decrement: item.quantity },
          varianceFlag: item.newStock.isNegative() || item.product.varianceFlag,
        },
      });
      if (changed.count !== 1) {
        if (stockApprover) {
          const forced = await tx.product.updateMany({
            where: { id: item.product.id, businessId },
            data: { stock: { decrement: item.quantity }, varianceFlag: true },
          });
          if (forced.count !== 1) {
            throw new SaleValidationError(
              { kind: 'INSUFFICIENT_STOCK', productId: item.product.id, name: item.product.name, available: toMilli(item.product.stock.toString()), requested: toMilli(item.quantity.toString()) },
              `Insufficient stock for '${item.product.name}'. Refresh stock and try again.`,
            );
          }
          const shortfall = new Prisma.Decimal(item.quantity.toString()).minus(item.product.stock);
          await tx.approval.create({
            data: {
              entityType: 'ADJUSTMENT',
              entityId: item.product.id,
              reason: `Negative-stock sale ${receiptNumber}: ${item.product.name}; shortfall ${shortfall.toString()} ${item.product.unit}`,
              status: 'APPROVED',
              requestedById: cashierId,
              approvedById: stockApprover.id,
              decidedAt: new Date(),
              decisionNote: `Approved by ${stockApprover.fullName} at checkout.`,
            },
          });
          await tx.auditLog.create({
            data: {
              businessId,
              userId: cashierId,
              action: 'STOCK_OVERRIDE_APPROVED',
              entityType: 'PRODUCT',
              entityId: item.product.id,
              beforeJson: { stock: item.product.stock.toString() },
              afterJson: { stock: item.newStock.toString(), saleId: sale.id, approvedById: stockApprover.id },
            },
          });
        } else {
          throw new SaleValidationError(
            { kind: 'INSUFFICIENT_STOCK', productId: item.product.id, name: item.product.name, available: toMilli(item.product.stock.toString()), requested: toMilli(item.quantity.toString()) },
            `Insufficient stock for '${item.product.name}'. Refresh stock and try again.`,
          );
        }
      }

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
      const amountDecimal = new Prisma.Decimal(totalCents).div(100);
      const newBalance = new Prisma.Decimal(customer.balance.toString()).plus(amountDecimal);

      await tx.customer.update({
        where: { id: customerId },
        data: { balance: newBalance },
      });

      await tx.customerLedger.create({
        data: {
          customerId,
          businessId,
          entryType: 'DEBIT',
          amount: amountDecimal,
          balance: newBalance,
          entityType: 'SALE',
          entityId: sale.id,
          reference: receiptNumber,
          note: `Goods purchased on credit`,
          createdById: cashierId,
        },
      });
      customerBalance = Number(newBalance.toString());
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
      ...(customerBalance !== undefined ? { customerBalance } : {}),
    };
  });
}
