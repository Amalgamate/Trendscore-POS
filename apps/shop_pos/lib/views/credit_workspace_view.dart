import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../cart.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../services/credit_document_picker.dart';
import '../theme/tokens.dart';

enum _CreditTab { transactions, account, terms, notes, documents }

class CreditWorkspaceView extends StatefulWidget {
  const CreditWorkspaceView({super.key, required this.state});

  final PosState state;

  @override
  State<CreditWorkspaceView> createState() => _CreditWorkspaceViewState();
}

class _CreditWorkspaceViewState extends State<CreditWorkspaceView> {
  final _search = TextEditingController();
  final _notesController = TextEditingController();
  PosCustomer? _selectedCustomer;
  _CreditTab _selectedTab = _CreditTab.transactions;
  String _ledgerFilter = 'All';
  bool _mobileShowDetails = false;
  bool _showArchived = false;
  bool _loadingAccounts = false;
  bool _loadingDocuments = false;
  bool _savingNotes = false;
  bool _uploadingDocument = false;
  List<Map<String, dynamic>> _documents = [];

  List<PosCustomer> get _accounts =>
      _showArchived ? widget.state.archivedCustomers : widget.state.customers;

  List<PosCustomer> get _filteredCustomers {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _accounts;
    return _accounts.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          customer.phone.toLowerCase().contains(query) ||
          customer.id.toLowerCase().contains(query);
    }).toList();
  }

  bool get _canManage => widget.state.canManageCustomerCredit;
  bool get _hasRemoteAccount =>
      _selectedCustomer != null &&
      ApiService.instance.hasToken &&
      _isRemoteId(_selectedCustomer!.id);

  @override
  void initState() {
    super.initState();
    if (widget.state.customers.isNotEmpty) {
      _selectedCustomer = widget.state.customers.first;
      _notesController.text = _selectedCustomer?.notes ?? '';
    }
    if (ApiService.instance.hasToken) _refreshAccounts();
  }

  @override
  void dispose() {
    _search.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static bool _isRemoteId(String id) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(id);

  Money _moneyFromApi(Object? value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return Money.fromDouble(math.max(0, amount).toDouble());
  }

  PosCustomer _customerFromApi(Map<String, dynamic> data) {
    final ledger = (data['ledger'] as List<dynamic>? ?? const []).map((item) {
      final entry = Map<String, dynamic>.from(item as Map);
      final entryType = entry['entryType'] as String? ?? '';
      final type = switch (entryType) {
        'DEBIT' => LedgerEntryType.saleDebit,
        'CREDIT' => LedgerEntryType.paymentCredit,
        _ => LedgerEntryType.reversal,
      };
      return CustomerLedgerEntry(
        id:
            entry['id'] as String? ??
            'ledger_${DateTime.now().microsecondsSinceEpoch}',
        timestamp:
            DateTime.tryParse(entry['createdAt'] as String? ?? '') ??
            DateTime.now(),
        type: type,
        amount: _moneyFromApi(entry['amount']),
        reference: entry['reference'] as String? ?? '',
        runningBalance: _moneyFromApi(entry['balance']),
      );
    }).toList();

    return PosCustomer(
      id: data['id'] as String,
      name: data['fullName'] as String? ?? 'Customer',
      phone: data['phone'] as String? ?? '',
      email: data['email'] as String?,
      address: data['address'] as String?,
      notes: data['notes'] as String?,
      creditLimit: _moneyFromApi(data['creditLimit']),
      currentBalance: _moneyFromApi(data['balance']),
      creditFrozen: data['creditFrozen'] as bool? ?? false,
      status: data['status'] as String? ?? 'ACTIVE',
      history: ledger,
    );
  }

  Future<void> _refreshAccounts() async {
    if (!ApiService.instance.hasToken || !mounted) return;
    setState(() => _loadingAccounts = true);
    final responses = await Future.wait([
      ApiService.instance.getCustomers(status: 'ACTIVE'),
      ApiService.instance.getCustomers(status: 'ARCHIVED'),
    ]);
    if (!mounted) return;
    if (responses[0] == null || responses[1] == null) {
      setState(() => _loadingAccounts = false);
      _showMessage(
        ApiService.instance.lastError ?? 'Could not refresh customer accounts.',
        error: true,
      );
      return;
    }

    widget.state.replaceCustomerAccounts(
      active: responses[0]!.map(_customerFromApi).toList(),
      archived: responses[1]!.map(_customerFromApi).toList(),
    );
    final available = _accounts;
    final previousId = _selectedCustomer?.id;
    final selection = available.where((item) => item.id == previousId);
    _selectedCustomer = selection.isNotEmpty
        ? selection.first
        : (available.isEmpty ? null : available.first);
    _notesController.text = _selectedCustomer?.notes ?? '';
    setState(() {
      _loadingAccounts = false;
      _documents = [];
    });
    if (_selectedCustomer != null) {
      await _loadSelectedDetails(_selectedCustomer!);
    }
  }

  Future<void> _loadSelectedDetails(PosCustomer customer) async {
    if (!ApiService.instance.hasToken || !_isRemoteId(customer.id)) {
      _notesController.text = customer.notes ?? '';
      if (_selectedTab == _CreditTab.documents) await _loadDocuments(customer);
      return;
    }
    final response = await ApiService.instance.getCustomer(customer.id);
    if (!mounted) return;
    if (response == null) {
      _showMessage(
        ApiService.instance.lastError ?? 'Could not load customer details.',
        error: true,
      );
      return;
    }
    final updated = _customerFromApi(response);
    widget.state.updateCustomerSnapshot(updated);
    if (_selectedCustomer?.id == updated.id) {
      setState(() {
        _selectedCustomer = updated;
        _notesController.text = updated.notes ?? '';
      });
      if (_selectedTab == _CreditTab.documents) await _loadDocuments(updated);
    }
  }

  void _selectCustomer(PosCustomer customer, {bool fetchDetails = true}) {
    setState(() {
      _selectedCustomer = customer;
      _selectedTab = _CreditTab.transactions;
      _ledgerFilter = 'All';
      _documents = [];
      _mobileShowDetails = true;
      _notesController.text = customer.notes ?? '';
    });
    if (fetchDetails) _loadSelectedDetails(customer);
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.status_danger : null,
      ),
    );
  }

  Future<void> _showNewCustomerDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final limitController = TextEditingController(text: '10000');
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Open customer credit account'),
          content: SizedBox(
            width: math.min(480, MediaQuery.sizeOf(dialogContext).width - 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogField(nameController, 'Customer name *'),
                  const SizedBox(height: 12),
                  _dialogField(
                    phoneController,
                    'Phone number',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _dialogField(emailController, 'Email address'),
                  const SizedBox(height: 12),
                  _dialogField(addressController, 'Address'),
                  const SizedBox(height: 12),
                  _dialogField(
                    limitController,
                    'Approved limit (KES)',
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final phone = phoneController.text.trim();
                      final limitText = limitController.text.trim();
                      if (name.isEmpty) {
                        _showMessage('Enter the customer name.', error: true);
                        return;
                      }
                      Money limit;
                      try {
                        limit = Money.parse(limitText);
                      } on FormatException {
                        _showMessage(
                          'Enter a valid credit limit in KES.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        final email = emailController.text.trim();
                        final address = addressController.text.trim();
                        PosCustomer customer;
                        if (ApiService.instance.hasToken) {
                          final created = await ApiService.instance
                              .createCustomer({
                                'fullName': name,
                                if (phone.isNotEmpty) 'phone': phone,
                                if (email.isNotEmpty) 'email': email,
                                if (address.isNotEmpty) 'address': address,
                                'creditLimit': limit.minorUnits / 100,
                              });
                          if (created == null) {
                            throw PosException(
                              ApiService.instance.lastError ??
                                  'Could not create the customer account.',
                            );
                          }
                          customer = _customerFromApi(created);
                        } else {
                          customer = PosCustomer(
                            id: 'cust_${DateTime.now().microsecondsSinceEpoch}',
                            name: name,
                            phone: phone,
                            email: email.isEmpty ? null : email,
                            address: address.isEmpty ? null : address,
                            creditLimit: limit,
                            currentBalance: const Money(0),
                          );
                        }
                        widget.state.addCustomer(customer);
                        if (!mounted || !dialogContext.mounted) return;
                        setState(() {
                          _showArchived = false;
                          _selectedCustomer = customer;
                          _mobileShowDetails = true;
                        });
                        Navigator.pop(dialogContext);
                        _showMessage(
                          'Credit account opened for ${customer.name}.',
                        );
                      } on PosException catch (error) {
                        setDialogState(() => saving = false);
                        _showMessage(error.message, error: true);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account'),
            ),
          ],
        ),
      ),
    );
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    addressController.dispose();
    limitController.dispose();
  }

  Widget _dialogField(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _showPaymentDialog(PosCustomer customer) async {
    final amountController = TextEditingController(
      text: customer.currentBalance.minorUnits == 0
          ? ''
          : Money(
              customer.currentBalance.minorUnits,
            ).formatted.replaceAll(',', ''),
    );
    final referenceController = TextEditingController();
    final noteController = TextEditingController();
    String method = 'M-Pesa';
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Record payment · ${customer.name}'),
          content: SizedBox(
            width: math.min(440, MediaQuery.sizeOf(dialogContext).width - 32),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BalanceBanner(customer: customer),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Payment amount (KES)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: method,
                    decoration: const InputDecoration(
                      labelText: 'Payment method',
                      border: OutlineInputBorder(),
                    ),
                    items: const ['M-Pesa', 'Cash', 'Bank Transfer']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() => method = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: referenceController,
                    decoration: const InputDecoration(
                      labelText: 'Receipt / transaction reference *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note (optional)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      Money amount;
                      try {
                        amount = Money.parse(amountController.text);
                      } on FormatException {
                        _showMessage(
                          'Enter a valid payment amount.',
                          error: true,
                        );
                        return;
                      }
                      if (amount.minorUnits <= 0 ||
                          amount.minorUnits >
                              customer.currentBalance.minorUnits) {
                        _showMessage(
                          'Payment must be greater than zero and no more than the outstanding balance.',
                          error: true,
                        );
                        return;
                      }
                      final reference = referenceController.text.trim();
                      if (reference.isEmpty) {
                        _showMessage(
                          'Enter the payment reference before recording it.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.state.recordCustomerPayment(
                          customer.id,
                          amount,
                          reference,
                          method,
                          note: noteController.text.trim(),
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        _showMessage(
                          'Payment of KES ${amount.formatted} recorded.',
                        );
                        await _loadSelectedDetails(customer);
                      } on PosException catch (error) {
                        setDialogState(() => saving = false);
                        _showMessage(error.message, error: true);
                      }
                    },
              icon: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    referenceController.dispose();
    noteController.dispose();
  }

  Future<void> _adjustLimit(PosCustomer customer) async {
    final controller = TextEditingController(
      text: customer.creditLimit.formatted.replaceAll(',', ''),
    );
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Adjust approved credit limit'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current balance: KES ${customer.currentBalance.formatted}',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'New limit (KES)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The adjustment changes future borrowing capacity; it does not rewrite past transactions.',
                  style: AppText.xs,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      Money amount;
                      try {
                        amount = Money.parse(controller.text);
                      } on FormatException {
                        _showMessage(
                          'Enter a valid credit limit.',
                          error: true,
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.state.updateCustomerCredit(
                          customer,
                          creditLimit: amount,
                        );
                        if (!mounted || !dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        setState(() {});
                        _showMessage('Credit limit updated.');
                      } on PosException catch (error) {
                        setDialogState(() => saving = false);
                        _showMessage(error.message, error: true);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save limit'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _toggleCreditFreeze(PosCustomer customer) async {
    final shouldFreeze = !customer.creditFrozen;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(shouldFreeze ? 'Freeze credit?' : 'Restore credit access?'),
        content: Text(
          shouldFreeze
              ? 'New credit sales for ${customer.name} will be blocked. Existing debt and payments remain unchanged.'
              : 'Allow ${customer.name} to use available credit again, subject to the approved limit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(shouldFreeze ? 'Freeze credit' : 'Unfreeze credit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.state.updateCustomerCredit(
        customer,
        creditFrozen: shouldFreeze,
      );
      if (!mounted) return;
      setState(() {});
      _showMessage(shouldFreeze ? 'Credit frozen.' : 'Credit access restored.');
    } on PosException catch (error) {
      _showMessage(error.message, error: true);
    }
  }

  Future<void> _archiveCustomer(PosCustomer customer) async {
    if (customer.currentBalance.minorUnits > 0) {
      _showMessage(
        'Settle the outstanding balance before archiving this account.',
        error: true,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive customer account?'),
        content: Text(
          'Archive ${customer.name}? It will leave the active list, but its transaction history, notes, and documents will be retained. You can restore it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.state.archiveCustomer(customer.id);
      if (!mounted) return;
      setState(() {
        _selectedCustomer = widget.state.customers.isEmpty
            ? null
            : widget.state.customers.first;
        _mobileShowDetails = false;
      });
      _showMessage(
        'Customer account archived. Financial history was retained.',
      );
    } on PosException catch (error) {
      _showMessage(error.message, error: true);
    }
  }

  Future<void> _restoreCustomer(PosCustomer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore customer account?'),
        content: Text(
          'Restore ${customer.name} to the active credit account list?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restore account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.state.restoreCustomer(customer);
      if (!mounted) return;
      setState(() {
        _showArchived = false;
        _selectedCustomer = customer;
        _mobileShowDetails = true;
      });
      _showMessage('Customer account restored.');
    } on PosException catch (error) {
      _showMessage(error.message, error: true);
    }
  }

  Future<void> _permanentlyDeleteCustomer(PosCustomer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete this account?'),
        content: Text(
          'Delete ${customer.name} permanently? This is only allowed when there are no financial transactions or linked records. Accounts with history must remain archived.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status_danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.state.permanentlyDeleteCustomer(customer);
      if (!mounted) return;
      setState(() {
        _selectedCustomer = widget.state.archivedCustomers.isEmpty
            ? null
            : widget.state.archivedCustomers.first;
      });
      _showMessage('Customer account deleted.');
    } on PosException catch (error) {
      _showMessage(error.message, error: true);
    }
  }

  Future<void> _saveNotes(PosCustomer customer) async {
    setState(() => _savingNotes = true);
    try {
      await widget.state.saveCustomerNotes(customer, _notesController.text);
      if (!mounted) return;
      setState(() => _savingNotes = false);
      _showMessage('Notes saved.');
    } on PosException catch (error) {
      if (!mounted) return;
      setState(() => _savingNotes = false);
      _showMessage(error.message, error: true);
    }
  }

  Future<void> _loadDocuments(PosCustomer customer) async {
    if (!ApiService.instance.hasToken || !_isRemoteId(customer.id)) {
      setState(() {
        _documents = [];
        _loadingDocuments = false;
      });
      return;
    }
    setState(() => _loadingDocuments = true);
    final documents = await ApiService.instance.getCustomerDocuments(
      customer.id,
    );
    if (!mounted) return;
    setState(() {
      _documents = documents ?? [];
      _loadingDocuments = false;
    });
    if (documents == null) {
      _showMessage(
        ApiService.instance.lastError ?? 'Could not load account documents.',
        error: true,
      );
    }
  }

  Future<void> _uploadDocument(PosCustomer customer) async {
    if (!_hasRemoteAccount) {
      _showMessage(
        'Sign in and sync this customer account before uploading documents.',
        error: true,
      );
      return;
    }
    try {
      final file = await pickCreditDocument();
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 8 * 1024 * 1024) {
        _showMessage('Documents must be 8 MB or smaller.', error: true);
        return;
      }
      final extension = file.extension?.toLowerCase();
      final contentType = switch (extension) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        _ => null,
      };
      if (contentType == null) {
        _showMessage('Choose a PDF, JPG, or PNG file.', error: true);
        return;
      }
      setState(() => _uploadingDocument = true);
      final uploaded = await ApiService.instance.uploadCustomerDocument(
        customer.id,
        fileName: file.name,
        contentType: contentType,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _uploadingDocument = false);
      if (uploaded == null) {
        _showMessage(
          ApiService.instance.lastError ?? 'Could not upload the document.',
          error: true,
        );
        return;
      }
      await _loadDocuments(customer);
      _showMessage('Document uploaded.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingDocument = false);
      _showMessage('Could not read the selected file: $error', error: true);
    }
  }

  Future<void> _downloadDocument(
    PosCustomer customer,
    Map<String, dynamic> document,
  ) async {
    final bytes = await ApiService.instance.downloadCustomerDocument(
      customer.id,
      document['id'] as String,
    );
    if (!mounted) return;
    if (bytes == null) {
      _showMessage(
        ApiService.instance.lastError ?? 'Could not download the document.',
        error: true,
      );
      return;
    }
    try {
      await FilePicker.saveFile(
        dialogTitle: 'Save customer document',
        fileName: document['fileName'] as String? ?? 'customer-document',
        bytes: bytes,
      );
    } catch (error) {
      _showMessage('Could not save the document: $error', error: true);
    }
  }

  Future<void> _deleteDocument(
    PosCustomer customer,
    Map<String, dynamic> document,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          'Permanently remove "${document['fileName']}" from this customer account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status_danger,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete document'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await ApiService.instance.deleteCustomerDocument(
      customer.id,
      document['id'] as String,
    );
    if (!mounted) return;
    if (!deleted) {
      _showMessage(
        ApiService.instance.lastError ?? 'Could not delete the document.',
        error: true,
      );
      return;
    }
    await _loadDocuments(customer);
    _showMessage('Document deleted.');
  }

  List<CustomerLedgerEntry> _visibleLedger(PosCustomer customer) {
    return switch (_ledgerFilter) {
      'Debits' => customer.ledger.where((entry) => entry.type.isDebit).toList(),
      'Credits' =>
        customer.ledger.where((entry) => !entry.type.isDebit).toList(),
      _ => customer.ledger,
    };
  }

  @override
  Widget build(BuildContext context) {
    final customers = widget.state.customers;
    final totalOutstanding = customers.fold(
      0,
      (sum, customer) => sum + customer.currentBalance.minorUnits,
    );
    final totalLimit = customers.fold(
      0,
      (sum, customer) => sum + customer.creditLimit.minorUnits,
    );
    final highRisk = customers.where((customer) {
      if (customer.creditLimit.minorUnits == 0) return false;
      return customer.currentBalance.minorUnits /
              customer.creditLimit.minorUnits >=
          0.8;
    }).length;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;
          return Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPageHeading(isMobile),
                const SizedBox(height: 16),
                _buildPortfolioStats(
                  customers,
                  totalOutstanding,
                  totalLimit,
                  highRisk,
                  isMobile,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isMobile
                      ? (_mobileShowDetails && _selectedCustomer != null
                            ? _buildDetailsPane(
                                _selectedCustomer!,
                                isMobile: true,
                              )
                            : _buildCustomerList(isMobile: true))
                      : Row(
                          children: [
                            SizedBox(
                              width: math.min(390, constraints.maxWidth * 0.34),
                              child: _buildCustomerList(isMobile: false),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: _selectedCustomer == null
                                  ? _emptyPanel(
                                      _loadingAccounts
                                          ? 'Loading accounts…'
                                          : 'Select an account to view details',
                                    )
                                  : _buildDetailsPane(
                                      _selectedCustomer!,
                                      isMobile: false,
                                    ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPageHeading(bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (ApiService.instance.hasToken)
          IconButton(
            tooltip: 'Refresh accounts',
            onPressed: _loadingAccounts ? null : _refreshAccounts,
            icon: _loadingAccounts
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _showNewCustomerDialog,
          icon: const Icon(Icons.person_add_alt_1, size: 18),
          label: Text(isMobile ? 'New' : 'New Account'),
        ),
      ],
    );
  }

  Widget _buildPortfolioStats(
    List<PosCustomer> customers,
    int totalOutstanding,
    int totalLimit,
    int highRisk,
    bool isMobile,
  ) {
    final utilization = totalLimit == 0
        ? 0.0
        : totalOutstanding / totalLimit * 100;
    final cards = [
      _PortfolioMetric(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Outstanding debt',
        value: 'KES ${Money(totalOutstanding).formatted}',
        detail: 'Across ${customers.length} active accounts',
        color: AppColors.status_warning,
      ),
      _PortfolioMetric(
        icon: Icons.credit_card_outlined,
        title: 'Credit allocated',
        value: 'KES ${Money(totalLimit).formatted}',
        detail: 'Approved account limits',
        color: AppColors.accent_primary,
      ),
      _PortfolioMetric(
        icon: Icons.percent,
        title: 'Credit utilization',
        value: '${utilization.toStringAsFixed(1)}%',
        detail: highRisk == 0
            ? 'Portfolio within limits'
            : '$highRisk accounts above 80%',
        color: highRisk == 0
            ? AppColors.status_success
            : AppColors.status_warning,
      ),
      _PortfolioMetric(
        icon: Icons.people_outline,
        title: 'Active accounts',
        value: '${customers.length}',
        detail: 'Available to use credit',
        color: AppColors.text_primary,
      ),
    ];
    if (isMobile) {
      return SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: cards.length,
          separatorBuilder: (_, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) =>
              SizedBox(width: 225, child: cards[index]),
        ),
      );
    }
    return Row(
      children: [
        for (var index = 0; index < cards.length; index++) ...[
          if (index > 0) const SizedBox(width: 12),
          Expanded(child: cards[index]),
        ],
      ],
    );
  }

  Widget _buildCustomerList({required bool isMobile}) {
    return _panel(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Active')),
                ButtonSegment(value: true, label: Text('Archived')),
              ],
              selected: {_showArchived},
              onSelectionChanged: (selected) {
                final showArchived = selected.first;
                setState(() {
                  _showArchived = showArchived;
                  _selectedCustomer = showArchived
                      ? (widget.state.archivedCustomers.isEmpty
                            ? null
                            : widget.state.archivedCustomers.first)
                      : (widget.state.customers.isEmpty
                            ? null
                            : widget.state.customers.first);
                  _mobileShowDetails = false;
                  _documents = [];
                });
                if (_selectedCustomer != null) {
                  _loadSelectedDetails(_selectedCustomer!);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search name, phone, or account…',
                prefixIcon: Icon(Icons.search, size: 19),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loadingAccounts && _filteredCustomers.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                ? _emptyState(
                    _showArchived
                        ? 'No archived accounts'
                        : 'No credit accounts yet',
                    _showArchived
                        ? 'Archived customers will appear here and can be restored.'
                        : 'Create a customer account to start managing credit.',
                  )
                : ListView.separated(
                    itemCount: _filteredCustomers.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    separatorBuilder: (_, index) =>
                        const Divider(height: 1, indent: 14, endIndent: 14),
                    itemBuilder: (context, index) {
                      final customer = _filteredCustomers[index];
                      return _CustomerRow(
                        customer: customer,
                        selected: customer.id == _selectedCustomer?.id,
                        onTap: () => _selectCustomer(customer),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPane(PosCustomer customer, {required bool isMobile}) {
    return _panel(
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAccountHeader(customer, isMobile),
            const SizedBox(height: 14),
            _buildAccountMetrics(customer, isMobile),
            const SizedBox(height: 12),
            _buildTabs(),
            const SizedBox(height: 8),
            Expanded(child: _buildTabContent(customer)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountHeader(PosCustomer customer, bool isMobile) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        if (isMobile)
          IconButton(
            tooltip: 'Back to accounts',
            onPressed: () => setState(() => _mobileShowDetails = false),
            icon: const Icon(Icons.arrow_back),
          ),
        CircleAvatar(
          radius: 23,
          backgroundColor: AppColors.accent_light,
          foregroundColor: AppColors.accent_primary,
          child: Text(
            customer.name.isEmpty
                ? 'C'
                : customer.name
                      .trim()
                      .split(RegExp(r'\s+'))
                      .take(2)
                      .map((part) => part[0].toUpperCase())
                      .join(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 140, maxWidth: 310),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                [
                  if (customer.phone.isNotEmpty) customer.phone,
                  'Ref: ${customer.id}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.xs,
              ),
            ],
          ),
        ),
        _StatusPill(customer: customer),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: () => _showStatement(customer),
          icon: const Icon(Icons.receipt_long_outlined, size: 17),
          label: const Text('Statement'),
        ),
        if (customer.status == 'ACTIVE')
          FilledButton.icon(
            onPressed: customer.currentBalance.minorUnits == 0
                ? null
                : () => _showPaymentDialog(customer),
            icon: const Icon(Icons.payments_outlined, size: 17),
            label: const Text('Pay debt'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.status_success,
            ),
          ),
        if (_canManage)
          PopupMenuButton<String>(
            tooltip: 'Account actions',
            onSelected: (action) {
              switch (action) {
                case 'freeze':
                  _toggleCreditFreeze(customer);
                case 'limit':
                  _adjustLimit(customer);
                case 'archive':
                  _archiveCustomer(customer);
                case 'restore':
                  _restoreCustomer(customer);
                case 'delete':
                  _permanentlyDeleteCustomer(customer);
              }
            },
            itemBuilder: (context) => [
              if (customer.status == 'ACTIVE') ...[
                PopupMenuItem(
                  value: 'freeze',
                  child: Row(
                    children: [
                      Icon(
                        customer.creditFrozen
                            ? Icons.lock_open_outlined
                            : Icons.ac_unit,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        customer.creditFrozen
                            ? 'Restore credit'
                            : 'Freeze credit',
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'limit',
                  child: Row(
                    children: [
                      Icon(Icons.tune),
                      SizedBox(width: 8),
                      Text('Adjust limit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'archive',
                  enabled: customer.currentBalance.minorUnits == 0,
                  child: const Row(
                    children: [
                      Icon(Icons.archive_outlined),
                      SizedBox(width: 8),
                      Text('Archive account'),
                    ],
                  ),
                ),
              ] else ...[
                const PopupMenuItem(
                  value: 'restore',
                  child: Row(
                    children: [
                      Icon(Icons.restore),
                      SizedBox(width: 8),
                      Text('Restore account'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  enabled:
                      customer.currentBalance.minorUnits == 0 &&
                      customer.ledger.isEmpty,
                  child: const Row(
                    children: [
                      Icon(
                        Icons.delete_outline,
                        color: AppColors.status_danger,
                      ),
                      SizedBox(width: 8),
                      Text('Delete permanently'),
                    ],
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildAccountMetrics(PosCustomer customer, bool isMobile) {
    final ratio = customer.creditLimit.minorUnits == 0
        ? 0.0
        : (customer.currentBalance.minorUnits / customer.creditLimit.minorUnits)
              .clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = isMobile
            ? constraints.maxWidth
            : (constraints.maxWidth - 30) / 4;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _AccountMetric(
              width: width,
              title: 'Current debt',
              value: 'KES ${customer.currentBalance.formatted}',
              icon: Icons.arrow_downward,
              color: AppColors.status_danger,
            ),
            _AccountMetric(
              width: width,
              title: 'Approved limit',
              value: 'KES ${customer.creditLimit.formatted}',
              icon: Icons.credit_card_outlined,
              color: AppColors.text_primary,
            ),
            _AccountMetric(
              width: width,
              title: 'Available credit',
              value: 'KES ${customer.availableCredit.formatted}',
              icon: Icons.arrow_upward,
              color: AppColors.status_success,
            ),
            Container(
              width: width,
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bg_canvas,
                borderRadius: AppRadius.md,
                border: Border.all(color: AppColors.border_subtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.percent,
                        size: 17,
                        color: AppColors.text_secondary,
                      ),
                      const SizedBox(width: 7),
                      const Text('Utilization', style: AppText.xs),
                      const Spacer(),
                      Text(
                        '${(ratio * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: AppColors.border_subtle,
                    color: ratio >= 0.8
                        ? AppColors.status_warning
                        : AppColors.accent_primary,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTabs() {
    const tabs = [
      (
        label: 'Transactions',
        icon: Icons.receipt_long_outlined,
        tab: _CreditTab.transactions,
      ),
      (
        label: 'Account details',
        icon: Icons.person_outline,
        tab: _CreditTab.account,
      ),
      (
        label: 'Credit terms',
        icon: Icons.credit_score_outlined,
        tab: _CreditTab.terms,
      ),
      (label: 'Notes', icon: Icons.notes_outlined, tab: _CreditTab.notes),
      (
        label: 'Documents',
        icon: Icons.folder_open_outlined,
        tab: _CreditTab.documents,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in tabs)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: () {
                  setState(() => _selectedTab = tab.tab);
                  if (tab.tab == _CreditTab.documents &&
                      _selectedCustomer != null) {
                    _loadDocuments(_selectedCustomer!);
                  }
                },
                icon: Icon(tab.icon, size: 17),
                label: Text(tab.label),
                style: TextButton.styleFrom(
                  foregroundColor: _selectedTab == tab.tab
                      ? AppColors.accent_primary
                      : AppColors.text_secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  side: _selectedTab == tab.tab
                      ? const BorderSide(color: AppColors.accent_primary)
                      : BorderSide.none,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabContent(PosCustomer customer) {
    return switch (_selectedTab) {
      _CreditTab.transactions => _buildTransactions(customer),
      _CreditTab.account => _buildAccountDetails(customer),
      _CreditTab.terms => _buildCreditTerms(customer),
      _CreditTab.notes => _buildNotes(customer),
      _CreditTab.documents => _buildDocuments(customer),
    };
  }

  Widget _buildTransactions(PosCustomer customer) {
    final entries = _visibleLedger(customer);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Append-only transaction history',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final filter in ['All', 'Debits', 'Credits'])
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: ChoiceChip(
                  label: Text(filter),
                  selected: _ledgerFilter == filter,
                  onSelected: (_) => setState(() => _ledgerFilter = filter),
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Expanded(
            child: _emptyState(
              'No transactions yet',
              'Credit sales and debt payments will appear here. Entries are retained for the life of the account.',
            ),
          )
        else ...[
          _LedgerHeader(),
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _LedgerRow(entry: entries[index]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAccountDetails(PosCustomer customer) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Account details', style: AppText.lg),
          const SizedBox(height: 16),
          Wrap(
            spacing: 32,
            runSpacing: 20,
            children: [
              _DetailField(label: 'Customer name', value: customer.name),
              _DetailField(
                label: 'Phone number',
                value: customer.phone.isEmpty ? 'Not provided' : customer.phone,
              ),
              _DetailField(
                label: 'Email address',
                value: customer.email?.isNotEmpty == true
                    ? customer.email!
                    : 'Not provided',
              ),
              _DetailField(
                label: 'Address',
                value: customer.address?.isNotEmpty == true
                    ? customer.address!
                    : 'Not provided',
              ),
              _DetailField(label: 'Account reference', value: customer.id),
              _DetailField(
                label: 'Account status',
                value: customer.status == 'ARCHIVED' ? 'Archived' : 'Active',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditTerms(PosCustomer customer) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Text('Credit terms', style: AppText.lg)),
              if (_canManage && customer.status == 'ACTIVE')
                OutlinedButton.icon(
                  onPressed: () => _adjustLimit(customer),
                  icon: const Icon(Icons.tune, size: 17),
                  label: const Text('Adjust limit'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 18,
            children: [
              _DetailField(
                label: 'Approved credit limit',
                value: 'KES ${customer.creditLimit.formatted}',
              ),
              _DetailField(
                label: 'Current balance',
                value: 'KES ${customer.currentBalance.formatted}',
              ),
              _DetailField(
                label: 'Available credit',
                value: 'KES ${customer.availableCredit.formatted}',
              ),
              _DetailField(
                label: 'Credit access',
                value: customer.creditFrozen ? 'Frozen' : 'Available',
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (customer.status == 'ACTIVE')
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                customer.creditFrozen ? 'Credit is frozen' : 'Credit is active',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                customer.creditFrozen
                    ? 'New credit sales are blocked; payments and history remain available.'
                    : 'This customer may make credit purchases within the approved limit.',
              ),
              value: customer.creditFrozen,
              onChanged: _canManage
                  ? (_) => _toggleCreditFreeze(customer)
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _buildNotes(PosCustomer customer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Account notes', style: AppText.lg),
        const SizedBox(height: 8),
        const Text(
          'Keep useful context for the next staff member. Notes do not change the financial ledger.',
          style: AppText.sm,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _notesController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText:
                  'Add payment preferences, contact notes, or follow-up details…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _savingNotes ? null : () => _saveNotes(customer),
            icon: _savingNotes
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 17),
            label: const Text('Save notes'),
          ),
        ),
      ],
    );
  }

  Widget _buildDocuments(PosCustomer customer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Account documents', style: AppText.lg),
                  SizedBox(height: 3),
                  Text(
                    'PDF, JPG, or PNG · maximum 8 MB per file',
                    style: AppText.xs,
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _uploadingDocument
                  ? null
                  : () => _uploadDocument(customer),
              icon: _uploadingDocument
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined, size: 17),
              label: Text(_uploadingDocument ? 'Uploading…' : 'Upload file'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingDocuments)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (!_hasRemoteAccount)
          Expanded(
            child: _emptyState(
              'Connect this account to the shop API',
              'Document uploads are stored with the shop database. Sign in and refresh to manage documents for this account.',
            ),
          )
        else if (_documents.isEmpty)
          Expanded(
            child: _emptyState(
              'No documents attached',
              'Upload a customer document to keep it with this account.',
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _documents.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final document = _documents[index];
                final size = (document['size'] as num?)?.toInt() ?? 0;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.accent_light,
                      borderRadius: AppRadius.md,
                    ),
                    child: Icon(
                      document['contentType'] == 'application/pdf'
                          ? Icons.picture_as_pdf_outlined
                          : Icons.image_outlined,
                      color: AppColors.accent_primary,
                    ),
                  ),
                  title: Text(
                    document['fileName'] as String? ?? 'Customer document',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatBytes(size)} · ${_formatDate(document['createdAt'])}',
                    style: AppText.xs,
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: 'Download',
                        onPressed: () => _downloadDocument(customer, document),
                        icon: const Icon(Icons.download_outlined),
                      ),
                      if (_canManage)
                        IconButton(
                          tooltip: 'Delete document',
                          onPressed: () => _deleteDocument(customer, document),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppColors.status_danger,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  void _showStatement(PosCustomer customer) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${customer.name} · Statement'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _DetailField(
                    label: 'Outstanding',
                    value: 'KES ${customer.currentBalance.formatted}',
                  ),
                  _DetailField(
                    label: 'Credit limit',
                    value: 'KES ${customer.creditLimit.formatted}',
                  ),
                ],
              ),
              const Divider(height: 24),
              SizedBox(
                height: 300,
                child: customer.ledger.isEmpty
                    ? const Center(child: Text('No transactions recorded.'))
                    : ListView.separated(
                        itemCount: customer.ledger.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = customer.ledger[index];
                          return _LedgerRow(entry: entry);
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg_surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border_subtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _emptyPanel(String message) => _panel(
    child: Center(child: Text(message, style: AppText.sm)),
  );

  Widget _emptyState(String title, String description) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(description, textAlign: TextAlign.center, style: AppText.sm),
        ],
      ),
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (date == null) return 'Date unavailable';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

class _PortfolioMetric extends StatelessWidget {
  const _PortfolioMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg_surface,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: AppRadius.md,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.xs,
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.xs,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.customer,
    required this.selected,
    required this.onTap,
  });

  final PosCustomer customer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = customer.creditLimit.minorUnits == 0
        ? 0.0
        : (customer.currentBalance.minorUnits / customer.creditLimit.minorUnits)
              .clamp(0.0, 1.0);
    final risk = ratio >= 0.8;
    return Material(
      color: selected ? AppColors.accent_light : AppColors.bg_surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: selected
                        ? AppColors.accent_primary
                        : AppColors.bg_subtle,
                    foregroundColor: selected
                        ? AppColors.text_inverse
                        : AppColors.text_secondary,
                    child: Text(
                      customer.name.isEmpty
                          ? 'C'
                          : customer.name.trim()[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          customer.phone.isEmpty
                              ? 'No phone number'
                              : customer.phone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.xs,
                        ),
                      ],
                    ),
                  ),
                  _StatusPill(customer: customer, compact: true),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.text_tertiary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ListMetric(
                      label: 'Outstanding',
                      value: 'KES ${customer.currentBalance.formatted}',
                      valueColor: customer.currentBalance.minorUnits > 0
                          ? AppColors.status_warning
                          : AppColors.text_primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ListMetric(
                      label: 'Credit limit',
                      value: 'KES ${customer.creditLimit.formatted}',
                      valueColor: AppColors.text_primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: ratio,
                minHeight: 5,
                borderRadius: BorderRadius.circular(6),
                color: risk
                    ? AppColors.status_warning
                    : AppColors.accent_primary,
                backgroundColor: AppColors.border_subtle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListMetric extends StatelessWidget {
  const _ListMetric({
    required this.label,
    required this.value,
    required this.valueColor,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.xs),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.customer, this.compact = false});

  final PosCustomer customer;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = customer.status == 'ARCHIVED'
        ? 'Archived'
        : customer.creditFrozen
        ? 'Credit frozen'
        : 'Active';
    final color = customer.status == 'ARCHIVED'
        ? AppColors.text_secondary
        : customer.creditFrozen
        ? AppColors.status_warning
        : AppColors.status_success;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 10 : 11,
        ),
      ),
    );
  }
}

class _AccountMetric extends StatelessWidget {
  const _AccountMetric({
    required this.width,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final double width;
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: AppColors.bg_canvas,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.xs,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _DetailField extends StatelessWidget {
  const _DetailField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.xs),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: const TextStyle(
              color: AppColors.text_primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceBanner extends StatelessWidget {
  const _BalanceBanner({required this.customer});
  final PosCustomer customer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg_canvas,
        borderRadius: AppRadius.md,
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _DetailField(
            label: 'Outstanding debt',
            value: 'KES ${customer.currentBalance.formatted}',
          ),
          _DetailField(
            label: 'Approved limit',
            value: 'KES ${customer.creditLimit.formatted}',
          ),
        ],
      ),
    );
  }
}

class _LedgerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: const BoxDecoration(
        color: AppColors.bg_subtle,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Text('Date / transaction', style: AppText.xs),
          ),
          Expanded(flex: 2, child: Text('Reference', style: AppText.xs)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Amount', style: AppText.xs),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text('Balance', style: AppText.xs),
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});
  final CustomerLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final isDebit = entry.type.isDebit;
    final date =
        '${entry.timestamp.day.toString().padLeft(2, '0')} ${_month(entry.timestamp.month)} ${entry.timestamp.year}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.type.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(date, style: AppText.xs),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              entry.reference.isEmpty ? '—' : entry.reference,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.xs,
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${isDebit ? '+' : '−'} KES ${entry.amount.formatted}',
                maxLines: 1,
                style: TextStyle(
                  color: isDebit
                      ? AppColors.status_danger
                      : AppColors.status_success,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'KES ${entry.runningBalance.formatted}',
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _month(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];
