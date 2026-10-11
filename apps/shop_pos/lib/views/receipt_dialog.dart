import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';

/// Shows digital thermal receipt and full A4 tax invoice preview for a sale.
class ReceiptDialog extends StatefulWidget {
  const ReceiptDialog({
    super.key,
    required this.sale,
    required this.onNewSale,
    this.state,
  });

  final SaleRecord sale;
  final VoidCallback onNewSale;
  final PosState? state;

  static void show(
    BuildContext context,
    SaleRecord sale, {
    required VoidCallback onNewSale,
    PosState? state,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ReceiptDialog(sale: sale, onNewSale: onNewSale, state: state),
    );
  }

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  int _viewMode = 0; // 0 = Thermal Slip, 1 = A4 Tax Invoice

  String get _shopName => widget.state?.shopName ?? 'SHOPSMART RETAIL POS';
  String get _branch => widget.state?.storeBranch ?? 'Main Branch';
  String get _tillId => widget.state?.tillId ?? 'Counter 01';

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;

    return Dialog(
      backgroundColor: AppColors.bg_surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: math.min(
          _viewMode == 0 ? 440.0 : 620.0,
          MediaQuery.sizeOf(context).width - 24,
        ),
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Status + View Mode Toggle
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: AppColors.status_success,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payment Approved',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text_primary,
                        ),
                      ),
                      Text(
                        'Receipt ${sale.receiptNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text_tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle Preview Format
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.bg_canvas,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border_subtle),
                  ),
                  child: Row(
                    children: [
                      _formatTab('Slip (80mm)', 0),
                      _formatTab('A4 Invoice', 1),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Scrollable Receipt / Invoice Container
            Expanded(
              child: SingleChildScrollView(
                child: _viewMode == 0
                    ? _buildThermalReceipt(sale)
                    : _buildA4Invoice(sale),
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text(
                      _viewMode == 0 ? 'Print Slip' : 'Print Invoice',
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${_viewMode == 0 ? "Thermal receipt" : "A4 Invoice"} sent to $_tillId printer!',
                          ),
                          backgroundColor: AppColors.accent_primary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Share via WhatsApp / SMS',
                  icon: const Icon(
                    Icons.share_outlined,
                    color: AppColors.text_secondary,
                    size: 20,
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Receipt #${sale.receiptNumber} link copied to clipboard!',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onNewSale();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent_primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'New Sale',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatTab(String label, int index) {
    final isSel = _viewMode == index;
    return InkWell(
      onTap: () => setState(() => _viewMode = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSel ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSel
              ? const [BoxShadow(color: Color(0x0F000000), blurRadius: 4)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
            color: isSel ? AppColors.accent_primary : AppColors.text_tertiary,
          ),
        ),
      ),
    );
  }

  Widget _buildThermalReceipt(SaleRecord sale) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bg_canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.state?.brandLogoBase64 != null &&
              widget.state!.brandLogoBase64!.isNotEmpty) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  base64Decode(widget.state!.brandLogoBase64!.split(',').last),
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ] else if (widget.state?.brandLogoUrl != null &&
              widget.state!.brandLogoUrl.isNotEmpty) ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  widget.state!.brandLogoUrl,
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Center(
            child: Text(
              _shopName.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 1,
              ),
            ),
          ),
          Center(
            child: Text(
              '$_branch · $_tillId',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.text_tertiary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cashier: ${sale.cashier}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.text_tertiary,
                ),
              ),
              Text(
                '${sale.timestamp.year}-${sale.timestamp.month.toString().padLeft(2, '0')}-${sale.timestamp.day.toString().padLeft(2, '0')} ${sale.timestamp.hour.toString().padLeft(2, '0')}:${sale.timestamp.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.text_tertiary,
                ),
              ),
            ],
          ),
          if (sale.customer != null) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Customer: ${sale.customer!.name}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.text_secondary,
                  ),
                ),
                Text(
                  sale.customer!.phone,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.text_tertiary,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 20, thickness: 1),

          // Items
          ...sale.items.map((item) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${item.quantity} × KES ${item.unitPrice.formatted}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.text_tertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'KES ${item.lineTotal.formatted}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),

          const Divider(height: 20, thickness: 1),

          // Financial Breakdown
          _TotalRow(
            label: 'Net Total (Excl. VAT)',
            value:
                'KES ${Money(sale.subtotal.minorUnits - sale.vatAmount.minorUnits).formatted}',
          ),
          const SizedBox(height: 4),
          _TotalRow(
            label: 'VAT Rate 16%',
            value: 'KES ${sale.vatAmount.formatted}',
          ),
          const SizedBox(height: 8),
          _TotalRow(
            label: 'TOTAL CHARGED',
            value: 'KES ${sale.subtotal.formatted}',
            isBold: true,
            fontSize: 16,
          ),
          const Divider(height: 18),

          // Payment method
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Payment: ${sale.paymentMethod.label.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                sale.paymentReference,
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppColors.text_secondary,
                ),
              ),
            ],
          ),
          if (sale.cashTendered != null) ...[
            const SizedBox(height: 4),
            _TotalRow(
              label: 'Cash Tendered',
              value: 'KES ${sale.cashTendered!.formatted}',
              isSmall: true,
            ),
            _TotalRow(
              label: 'Change Given',
              value: 'KES ${(sale.changeDue ?? const Money(0)).formatted}',
              isSmall: true,
            ),
          ],

          const SizedBox(height: 16),

          // Barcode Representation
          Center(
            child: Column(
              children: [
                Container(
                  height: 32,
                  width: 200,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border_subtle),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      24,
                      (i) => Container(
                        width: (i % 3 == 0) ? 3 : 1.5,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sale.receiptNumber,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                    color: AppColors.text_tertiary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Goods once sold are not returnable without valid receipt.',
                  style: TextStyle(fontSize: 9, color: AppColors.text_tertiary),
                ),
                const Text(
                  'Thank you for shopping with us!',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent_primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildA4Invoice(SaleRecord sale) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Corporate Tax Invoice Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.state?.brandLogoBase64 != null &&
                      widget.state!.brandLogoBase64!.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(
                          widget.state!.brandLogoBase64!.split(',').last,
                        ),
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _shopName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.accent_primary,
                        ),
                      ),
                      Text(
                        'Branch: $_branch · Terminal: $_tillId',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text_secondary,
                        ),
                      ),
                      const Text(
                        'PIN: P051239845Z · Tax Reg: ET-2024-KRA',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.text_tertiary,
                        ),
                      ),
                      const Text(
                        'Email: accounts@shopsmartpos.ke · Tel: +254 700 000 000',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.text_tertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'TAX INVOICE',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1D4ED8),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Invoice #: ${sale.receiptNumber}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Date: ${sale.timestamp.year}-${sale.timestamp.month.toString().padLeft(2, "0")}-${sale.timestamp.day.toString().padLeft(2, "0")}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text_tertiary,
                    ),
                  ),
                  Text(
                    'Cashier: ${sale.cashier}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.text_tertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 24),

          // Bill To
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg_canvas,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Billed To / Debtor Account:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text_tertiary,
                      ),
                    ),
                    Text(
                      sale.customer?.name ?? 'Walk-In Retail Client',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Phone: ${sale.customer?.phone ?? "N/A"}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text_secondary,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Payment Status:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.text_tertiary,
                      ),
                    ),
                    Text(
                      sale.paymentPending
                          ? 'PENDING RECONCILIATION'
                          : sale.paymentMethod == SalePaymentMethod.credit
                          ? 'CREDIT / PENDING'
                          : 'PAID IN FULL',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color:
                            sale.paymentPending ||
                                sale.paymentMethod == SalePaymentMethod.credit
                            ? const Color(0xFFD97706)
                            : AppColors.status_success,
                      ),
                    ),
                    Text(
                      'Ref: ${sale.paymentReference}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: AppColors.text_tertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Table of Items
          Table(
            border: TableBorder.all(color: AppColors.border_subtle, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Product Description',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Qty',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Unit Price',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Total (KES)',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              ...sale.items.map(
                (it) => TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        it.productName,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        it.quantity.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'KES ${it.unitPrice.formatted}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        'KES ${it.lineTotal.formatted}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Totals Table
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 260,
              child: Column(
                children: [
                  _TotalRow(
                    label: 'Subtotal (Excl. VAT)',
                    value:
                        'KES ${Money(sale.subtotal.minorUnits - sale.vatAmount.minorUnits).formatted}',
                  ),
                  const SizedBox(height: 4),
                  _TotalRow(
                    label: 'VAT (16.0%)',
                    value: 'KES ${sale.vatAmount.formatted}',
                  ),
                  const Divider(height: 12),
                  _TotalRow(
                    label: 'Grand Total Due',
                    value: 'KES ${sale.subtotal.formatted}',
                    isBold: true,
                    fontSize: 15,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Compliance & Stamp
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border_subtle),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified,
                  color: AppColors.status_success,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Certified KRA eTIMS Validated Electronic Document',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.text_primary,
                        ),
                      ),
                      Text(
                        'Official electronic tax register verified by Trends Retail CORE OS',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.text_tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.fontSize = 12,
    this.isSmall = false,
  });

  final String label;
  final String value;
  final bool isBold;
  final double fontSize;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isSmall ? 10 : fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold ? AppColors.text_primary : AppColors.text_tertiary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isSmall ? 10 : fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: isBold ? AppColors.accent_primary : AppColors.text_primary,
          ),
        ),
      ],
    );
  }
}
