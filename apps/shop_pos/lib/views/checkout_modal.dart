import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import 'receipt_dialog.dart';

/// Modal bottom sheet or dialog for payment execution.
class CheckoutModal extends StatefulWidget {
  const CheckoutModal({
    super.key,
    required this.state,
    required this.onSaleCompleted,
  });

  final PosState state;
  final VoidCallback onSaleCompleted;

  static void show(
    BuildContext context,
    PosState state, {
    required VoidCallback onSaleCompleted,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          CheckoutModal(state: state, onSaleCompleted: onSaleCompleted),
    );
  }

  @override
  State<CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends State<CheckoutModal> {
  SalePaymentMethod _method = SalePaymentMethod.mpesa;

  // Manual M-Pesa Till payment
  final _tillNumberController = TextEditingController();
  final _mpesaReceiptController = TextEditingController();

  // Cash State
  final _cashController = TextEditingController();
  int _cashTenderedMinor = 0;

  // Credit State
  PosCustomer? _selectedCreditCustomer;
  bool _saleSubmitting = false;
  final int _saleKeySeed = DateTime.now().microsecondsSinceEpoch;
  final Map<String, String> _saleIdempotencyKeys = {};

  @override
  void initState() {
    super.initState();
    _selectedCreditCustomer = widget.state.selectedCustomer;
    _cashTenderedMinor = widget.state.cart.subtotal.minorUnits;
    _cashController.text = _cashInput(widget.state.cart.subtotal.minorUnits);
  }

  String _cashInput(int minorUnits) =>
      '${minorUnits ~/ 100}.${(minorUnits % 100).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _tillNumberController.dispose();
    _mpesaReceiptController.dispose();
    _cashController.dispose();
    super.dispose();
  }

  void _recordMpesaTillSale() {
    if (!ApiService.instance.hasToken) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reconnect to the shop before recording an M-Pesa Till sale.',
          ),
        ),
      );
      return;
    }
    final tillNumber = _tillNumberController.text.trim();
    if (tillNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the M-Pesa Till number used.')),
      );
      return;
    }
    if (!RegExp(r'^\d{3,15}$').hasMatch(tillNumber)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid numeric Till number.')),
      );
      return;
    }
    final receipt = _mpesaReceiptController.text.trim();
    final reference = [
      'TILL: $tillNumber',
      if (receipt.isNotEmpty) 'M-PESA REF: $receipt',
    ].join(' · ');
    _finishSale(method: SalePaymentMethod.mpesa, reference: reference);
  }

  void _executeCashSale() {
    final subtotal = widget.state.cart.subtotal;
    if (_cashTenderedMinor < subtotal.minorUnits) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cash tendered cannot be less than sale total!'),
        ),
      );
      return;
    }

    final changeDue = Money(_cashTenderedMinor - subtotal.minorUnits);
    _finishSale(
      method: SalePaymentMethod.cash,
      reference: 'CASH',
      cashTendered: Money(_cashTenderedMinor),
      changeDue: changeDue,
    );
  }

  void _executeCreditSale() {
    final cust = _selectedCreditCustomer;
    if (cust == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a customer for credit sale!'),
        ),
      );
      return;
    }
    if (!ApiService.instance.hasToken) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reconnect to the shop before recording a credit sale.',
          ),
        ),
      );
      return;
    }

    final subtotal = widget.state.cart.subtotal;
    if (cust.status != 'ACTIVE' || cust.creditFrozen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cust.creditFrozen
                ? 'Credit is frozen for ${cust.name}. Choose another payment method.'
                : 'This customer credit account is not active.',
          ),
        ),
      );
      return;
    }
    if (cust.currentBalance.minorUnits + subtotal.minorUnits >
        cust.creditLimit.minorUnits) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Credit limit exceeded! Customer available credit is KES ${cust.availableCredit.formatted}',
          ),
        ),
      );
      return;
    }

    _finishSale(
      method: SalePaymentMethod.credit,
      reference: 'CREDIT: ${cust.name}',
    );
  }

  void _finishSale({
    required SalePaymentMethod method,
    required String reference,
    Money? cashTendered,
    Money? changeDue,
  }) async {
    if (_saleSubmitting) return;
    final customer = method == SalePaymentMethod.credit
        ? _selectedCreditCustomer
        : null;
    final requestKey = [
      method.apiValue,
      customer?.id ?? '',
      ...widget.state.cart.lines.map(
        (line) => '${line.productId}:${line.quantity}',
      ),
    ].join('|');
    final idempotencyKey = _saleIdempotencyKeys.putIfAbsent(
      requestKey,
      () =>
          'pos-$_saleKeySeed-${identityHashCode(this)}-${_saleIdempotencyKeys.length + 1}',
    );

    setState(() => _saleSubmitting = true);
    try {
      final sale = await widget.state.completeSale(
        method: method,
        paymentReference: reference,
        idempotencyKey: idempotencyKey,
        customer: customer,
        cashTendered: cashTendered,
        changeDue: changeDue,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ReceiptDialog.show(
        context,
        sale,
        onNewSale: widget.onSaleCompleted,
        state: widget.state,
      );
    } on PosException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sale was not recorded: $error')));
    } finally {
      if (mounted) setState(() => _saleSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.state.cart.subtotal;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: math.min(580.0, MediaQuery.sizeOf(context).width - 24),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Complete Sale',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${widget.state.cart.itemCount} items · VAT Included (16%)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text_tertiary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bg_subtle,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'KES ${subtotal.formatted}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accent_primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Method Selector Tabs (equal height, icons share one baseline)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MethodTab(
                    label: 'M-Pesa Till',
                    icon: Icons.storefront_outlined,
                    activeColor: const Color(0xFF16A34A),
                    isSelected: _method == SalePaymentMethod.mpesa,
                    onTap: _saleSubmitting
                        ? () {}
                        : () =>
                              setState(() => _method = SalePaymentMethod.mpesa),
                  ),
                  const SizedBox(width: 8),
                  _MethodTab(
                    label: 'Cash Tender',
                    icon: Icons.payments_outlined,
                    activeColor: AppColors.accent_primary,
                    isSelected: _method == SalePaymentMethod.cash,
                    onTap: _saleSubmitting
                        ? () {}
                        : () =>
                              setState(() => _method = SalePaymentMethod.cash),
                  ),
                  const SizedBox(width: 8),
                  _MethodTab(
                    label: 'Customer Credit',
                    icon: Icons.account_balance_outlined,
                    activeColor: const Color(0xFFD97706),
                    isSelected: _method == SalePaymentMethod.credit,
                    onTap: _saleSubmitting
                        ? () {}
                        : () => setState(
                            () => _method = SalePaymentMethod.credit,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tab Content
            if (_method == SalePaymentMethod.mpesa) _buildMpesaTab(subtotal),
            if (_method == SalePaymentMethod.cash) _buildCashTab(subtotal),
            if (_method == SalePaymentMethod.credit) _buildCreditTab(subtotal),

            const SizedBox(height: 20),

            // Cancel button
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saleSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel & Return to Cart'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMpesaTab(Money subtotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.storefront_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'M-Pesa Till payment',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF166534),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Business M-Pesa Till number:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tillNumberController,
            enabled: !_saleSubmitting,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.storefront_outlined, size: 18),
              hintText: 'Enter the Till number',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF86EFAC)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mpesaReceiptController,
            enabled: !_saleSubmitting,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.receipt_long_outlined, size: 18),
              labelText: 'M-Pesa receipt code (optional)',
              hintText: 'e.g. QGH7X2P9',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'This records the sale for manual reconciliation; it does not send STK or confirm payment.',
            style: TextStyle(fontSize: 12, color: Color(0xFF166534)),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text('Record Till Sale · KES ${subtotal.formatted}'),
            onPressed: _saleSubmitting ? null : _recordMpesaTillSale,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashTab(Money subtotal) {
    final changeDue = _cashTenderedMinor >= subtotal.minorUnits
        ? Money(_cashTenderedMinor - subtotal.minorUnits)
        : const Money(0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg_canvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tendered Cash (KES):',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              Text(
                'Total Due: KES ${subtotal.formatted}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text_tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cashController,
            onChanged: (text) {
              try {
                final parsed = Money.parse(text);
                setState(() => _cashTenderedMinor = parsed.minorUnits);
              } on FormatException {
                setState(() => _cashTenderedMinor = 0);
              }
            },
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              prefixText: 'KES ',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Quick tender buttons
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Exact Amount'),
                onPressed: () {
                  setState(() {
                    _cashTenderedMinor = subtotal.minorUnits;
                    _cashController.text = _cashInput(subtotal.minorUnits);
                  });
                },
              ),
              ...[100, 200, 500, 1000].map((denom) {
                return ActionChip(
                  label: Text('+$denom'),
                  onPressed: () {
                    setState(() {
                      _cashTenderedMinor += denom * 100;
                      _cashController.text = _cashInput(_cashTenderedMinor);
                    });
                  },
                );
              }),
            ],
          ),
          const Divider(height: 24),

          // Change due
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Change Due:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              Text(
                'KES ${changeDue.formatted}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.status_success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          FilledButton(
            onPressed:
                !_saleSubmitting && _cashTenderedMinor >= subtotal.minorUnits
                ? _executeCashSale
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent_primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Confirm Cash Payment'),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditTab(Money subtotal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFFD97706),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.book_outlined,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Post to Customer Credit Ledger',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF92400E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Select Customer Account:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<PosCustomer>(
            initialValue: _selectedCreditCustomer,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: widget.state.customers.map((c) {
              return DropdownMenuItem(
                value: c,
                child: Text('${c.name} (${c.phone})'),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedCreditCustomer = val),
          ),
          if (_selectedCreditCustomer != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  _CreditRow(
                    label: 'Current Balance Owed:',
                    value:
                        'KES ${_selectedCreditCustomer!.currentBalance.formatted}',
                  ),
                  const SizedBox(height: 4),
                  _CreditRow(
                    label: 'Available Credit Limit:',
                    value:
                        'KES ${_selectedCreditCustomer!.availableCredit.formatted}',
                  ),
                  const Divider(height: 12),
                  _CreditRow(
                    label: 'New Balance After Sale:',
                    value:
                        'KES ${(_selectedCreditCustomer!.currentBalance + subtotal).formatted}',
                    isBold: true,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: !_saleSubmitting && _selectedCreditCustomer != null
                ? _executeCreditSale
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _saleSubmitting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text('Recording sale...'),
                    ],
                  )
                : const Text('Record Debt & Complete Sale'),
          ),
        ],
      ),
    );
  }
}

class _MethodTab extends StatelessWidget {
  const _MethodTab({
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          alignment: Alignment.topCenter,
          decoration: BoxDecoration(
            color: isSelected
                ? activeColor.withAlpha(20)
                : AppColors.bg_surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor : AppColors.border_subtle,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Fixed 24x24 slot, glyph centred, so every tab's icon sits on the same line.
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: Icon(
                    icon,
                    color: isSelected ? activeColor : AppColors.text_tertiary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? activeColor : AppColors.text_secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditRow extends StatelessWidget {
  const _CreditRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  final String label;
  final String value;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isBold ? AppColors.text_primary : AppColors.text_tertiary,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isBold ? const Color(0xFFD97706) : AppColors.text_primary,
          ),
        ),
      ],
    );
  }
}
