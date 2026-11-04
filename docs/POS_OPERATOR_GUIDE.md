# POS operator guide

Use this guide for the Guta Gala POS. The API is the source of truth for stock
and customer balances; wait for a successful save before repeating an action.

## Set up a measured product

1. Open **Inventory & Catalogue** and add a product.
2. Choose its base stock unit, such as `L`, `kg`, or `pc`. Set the selling and
   cost prices for that base unit. For example, set cooking oil to KES 300/L.
3. If useful, enter the purchase-container name and its size in base units (for
   example, `Jerrycan`, `20 L`) and add quick sale sizes such as `250 ml` and
   `500 ml`.
4. Save the product. Receive opening stock through the receive-stock action;
   receiving three 20 L jerrycans records 60 L. Check the stock movement history
   after receiving.

At checkout, tap a measured product, choose a preset or enter a custom quantity
and unit, then select **Add**. Check the displayed line total before charging.
For 250 ml at KES 300/L, the line is KES 75 and stock falls by 0.25 L after a
successful sale. A customer name typed during checkout is printed on the
receipt when the business receipt-name setting is enabled. To charge a sale to
credit, select the customer's saved account; a receipt name alone is not a
credit account.

## Record spillage, damage, or a count

1. In **Inventory & Catalogue**, open the stock adjustment action for the
   product.
2. Choose the correct reason (spillage, wastage, damage, expiry, or correction)
   and enter the quantity in a compatible unit. The system records the signed
   movement and audit entry; do not create a replacement product to hide a
   discrepancy.
3. For a physical count, open the count action, enter the observed quantity,
   and save. The system records the difference and before/after balances.
4. Review the product's movement history and resolve any variance flag with a
   follow-up count.

## Remove a duplicate product

Open the product and choose permanent delete only for a duplicate with no sale,
purchase, or refund history. If it has transaction history, use **Archive** so
old receipts and reports remain valid. If stock remains, follow the explicit
discard confirmation and review the audit entry; permanent deletion cannot be
undone.

## Review the day and print reports

1. Open **Reports** and choose **End of day report** for the current business
   day. Review the sales total, payment breakdown, refunds, and debt payments.
2. Open **Inventory & Catalogue → Export → View stock audit list** to review
   products, quantities, units, and valuation totals.
3. Choose **Print A4 stock count sheet**, **Download Excel stock list**, or
   **Download CSV stock list**. Before distributing a printout, check the
   browser's page count, repeating headings, shop name, units, and totals. For
   a physical stock count, write in the Counted and Difference columns.

## Before closing a sale

- Confirm the product, unit, quantity, price, and remaining stock.
- For cash, enter the amount received and confirm change before payment.
- For M-Pesa Till, enter the till number used and keep the transaction reference
  if available.
- For credit, verify the selected customer's name and available limit.
- Keep the receipt and use the movement history or customer statement to
  investigate any discrepancy. Do not retry a sale while its payment result is
  still pending; ask a Manager to reconcile it first.
