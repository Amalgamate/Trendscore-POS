import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pos_state.dart';
import '../theme/tokens.dart';
import '../services/api_service.dart';
import 'widgets/image_upload_widget.dart';

/// POS Settings and Configuration screen.
/// Light Premium Theme: Solid flat cards, Slate typography, Teal accents.
/// Full Brand Upload & Customization, Users & Roles, Hardware, and Persistent Save.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.state});

  final PosState state;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late final TextEditingController _shopNameController;
  late final TextEditingController _storeBranchController;
  late final TextEditingController _tillIdController;
  late final TextEditingController _brandTaglineController;
  late final TextEditingController _brandLogoUrlController;
  late final TextEditingController _heroImageUrlController;
  late final TextEditingController _serverUrlController;

  late bool _autoPrintReceipt;
  late bool _cashDrawerKick;
  late bool _requirePinForReversal;
  late String _printerPaperSize;

  bool _isCheckingConnection = false;
  bool? _connectionResult;
  bool _isSaving = false;
  /// Pending logo base64 (picked this session, not yet saved)
  String? _pendingLogoBase64;
  bool _clearLogo = false;

  @override
  void initState() {
    super.initState();
    _shopNameController = TextEditingController(text: widget.state.shopName);
    _storeBranchController = TextEditingController(text: widget.state.storeBranch);
    _tillIdController = TextEditingController(text: widget.state.tillId);
    _brandTaglineController = TextEditingController(text: widget.state.brandTagline);
    _brandLogoUrlController = TextEditingController(text: widget.state.brandLogoUrl);
    _heroImageUrlController = TextEditingController(text: widget.state.heroImageUrl);
    _serverUrlController = TextEditingController(text: widget.state.serverUrl);

    _autoPrintReceipt = widget.state.autoPrintReceipt;
    _cashDrawerKick = widget.state.cashDrawerKick;
    _requirePinForReversal = widget.state.requirePinForReversal;
    _printerPaperSize = widget.state.printerPaperSize;
    _pendingLogoBase64 = widget.state.brandLogoBase64;
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _storeBranchController.dispose();
    _tillIdController.dispose();
    _brandTaglineController.dispose();
    _brandLogoUrlController.dispose();
    _heroImageUrlController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);

    await widget.state.saveSettings(
      newShopName: _shopNameController.text.trim(),
      newStoreBranch: _storeBranchController.text.trim(),
      newTillId: _tillIdController.text.trim(),
      newBrandTagline: _brandTaglineController.text.trim(),
      newBrandLogoUrl: _brandLogoUrlController.text.trim(),
      newBrandLogoBase64: _pendingLogoBase64,
      clearLogoBase64: _clearLogo,
      newHeroImageUrl: _heroImageUrlController.text.trim(),
      newServerUrl: _serverUrlController.text.trim(),
      newAutoPrintReceipt: _autoPrintReceipt,
      newCashDrawerKick: _cashDrawerKick,
      newRequirePinForReversal: _requirePinForReversal,
      newPrinterPaperSize: _printerPaperSize,
    );
    _clearLogo = false;

    ApiService.instance.configure(_serverUrlController.text);

    setState(() => _isSaving = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Settings and brand configuration saved successfully!'),
            ],
          ),
          backgroundColor: AppColors.status_success,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isCheckingConnection = true;
      _connectionResult = null;
    });

    ApiService.instance.configure(_serverUrlController.text);
    final ok = await ApiService.instance.checkHealth();

    setState(() {
      _isCheckingConnection = false;
      _connectionResult = ok;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Connected to Retail OS shop-api successfully!'
              : 'Could not reach server at ${_serverUrlController.text}'),
          backgroundColor: ok ? AppColors.accent_primary : AppColors.status_danger,
        ),
      );
    }
  }

  void _showUserEditorModal({PosUser? existingUser}) {
    final nameCtrl = TextEditingController(text: existingUser?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: existingUser?.phone ?? '');
    final pinCtrl = TextEditingController(text: existingUser?.pin ?? '');
    PosUserRole selectedRole = existingUser?.role ?? PosUserRole.cashier;
    bool obscurePin = true;

    Color roleColor(PosUserRole role) {
      switch (role) {
        case PosUserRole.owner:
          return const Color(0xFFD97706);
        case PosUserRole.manager:
          return const Color(0xFF7C3AED);
        case PosUserRole.cashier:
          return const Color(0xFF10B981);
        case PosUserRole.stockClerk:
          return const Color(0xFF2563EB);
      }
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.border_subtle),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accent_light,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  existingUser == null ? Icons.person_add_alt_1 : Icons.manage_accounts,
                  color: AppColors.accent_primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                existingUser == null ? 'Add Staff Account' : 'Edit Staff Account',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text_primary,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Full Name *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Grace Wambui',
                      filled: true,
                      fillColor: AppColors.bg_subtle,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text('Mobile Phone Number *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: '+254 700 000 000',
                      filled: true,
                      fillColor: AppColors.bg_subtle,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  const Text('4-Digit Terminal Login PIN *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: pinCtrl,
                    maxLength: 4,
                    obscureText: obscurePin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '4 digits (e.g. 1234)',
                      filled: true,
                      fillColor: AppColors.bg_subtle,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePin ? Icons.visibility_off : Icons.visibility, color: AppColors.text_tertiary, size: 18),
                        onPressed: () => setModalState(() => obscurePin = !obscurePin),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  const Text('Role & Authorization Level *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<PosUserRole>(
                    value: selectedRole,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.bg_subtle,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                    ),
                    items: PosUserRole.values.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: roleColor(r))),
                            const SizedBox(width: 8),
                            Text(r.name.toUpperCase()),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedRole = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: AppColors.text_secondary)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent_primary,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                final pin = pinCtrl.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid staff name.')));
                  return;
                }
                if (pin.length != 4) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN must be exactly 4 numeric digits.')));
                  return;
                }

                if (existingUser != null) {
                  existingUser.fullName = name;
                  existingUser.phone = phone;
                  existingUser.pin = pin;
                  existingUser.role = selectedRole;
                  existingUser.color = roleColor(selectedRole);
                  widget.state.updateUser(existingUser);
                } else {
                  final newUser = PosUser(
                    id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
                    fullName: name,
                    phone: phone,
                    pin: pin,
                    role: selectedRole,
                    color: roleColor(selectedRole),
                  );
                  widget.state.addUser(newUser);
                }

                setState(() {});
                Navigator.pop(ctx);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Staff account $name saved. Active PIN: $pin'),
                    backgroundColor: AppColors.status_success,
                  ),
                );
              },
              child: Text(existingUser == null ? 'Create Account' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Color _roleColor(PosUserRole role) {
    switch (role) {
      case PosUserRole.owner:
        return const Color(0xFFD97706);
      case PosUserRole.manager:
        return const Color(0xFF7C3AED);
      case PosUserRole.cashier:
        return const Color(0xFF10B981);
      case PosUserRole.stockClerk:
        return const Color(0xFF2563EB);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.state.users;

    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Bar with Save Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Terminal & Brand Settings',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.text_primary),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Customize branding, hero imagery, shop names, staff accounts, and hardware',
                      style: TextStyle(fontSize: 13, color: AppColors.text_tertiary),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveAllSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Save All Settings'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent_primary,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ─── 1. Brand & Store Identity ───────────────────────────────
            _buildSection(
              title: 'Brand Identity & Store Profile',
              icon: Icons.storefront_outlined,
              children: [
                const Text(
                  'Set your shop branding. This automatically customizes the login screen, receipt headers, and POS header navigation.',
                  style: TextStyle(fontSize: 13, color: AppColors.text_secondary, height: 1.4),
                ),
                const SizedBox(height: 18),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final isNarrow = constraints.maxWidth < 650;
                    if (isNarrow) {
                      return Column(
                        children: [
                          _buildTextField('Shop / Business Name', _shopNameController, hint: 'e.g. ShopSmart POS'),
                          const SizedBox(height: 12),
                          _buildTextField('Branch / Counter Location', _storeBranchController, hint: 'e.g. Kilimani Market · Counter 01'),
                          const SizedBox(height: 12),
                          _buildTextField('Till Terminal ID', _tillIdController, hint: 'e.g. TILL-01'),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(flex: 3, child: _buildTextField('Shop / Business Name', _shopNameController, hint: 'e.g. ShopSmart POS')),
                        const SizedBox(width: 12),
                        Expanded(flex: 3, child: _buildTextField('Branch / Counter Location', _storeBranchController, hint: 'e.g. Kilimani Market · Counter 01')),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: _buildTextField('Till Terminal ID', _tillIdController, hint: 'e.g. TILL-01')),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  'Store Tagline (shown on login screen & receipts)',
                  _brandTaglineController,
                  hint: 'e.g. Your shop. Your customers. Everything in one place.',
                ),
                const SizedBox(height: 20),

                // Brand Logo Upload
                const Text('Brand Logo',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
                const SizedBox(height: 4),
                const Text('Upload a square image — auto-cropped to 1:1 and compressed to keep the POS lightning fast.',
                    style: TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ImageUploadWidget(
                      currentBase64: _pendingLogoBase64,
                      size: 110,
                      label: 'Upload Logo',
                      borderRadius: 16,
                      isLogo: true,
                      onImagePicked: (b64) => setState(() {
                        _pendingLogoBase64 = b64;
                        _clearLogo = false;
                      }),
                      onImageCleared: () => setState(() {
                        _pendingLogoBase64 = null;
                        _clearLogo = true;
                      }),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('— or choose preset / URL —',
                              style: TextStyle(fontSize: 11, color: AppColors.text_tertiary)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _brandLogoUrlController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Leave empty for default leaf, or paste URL',
                              filled: true,
                              fillColor: AppColors.bg_subtle,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                              prefixIcon: const Icon(Icons.link, size: 18, color: AppColors.accent_primary),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _logoPresetChip('Default Leaf', ''),
                              _logoPresetChip('Retail Cart', 'https://cdn-icons-png.flaticon.com/512/3081/3081840.png'),
                              _logoPresetChip('Storefront', 'https://cdn-icons-png.flaticon.com/512/2331/2331970.png'),
                              _logoPresetChip('Shopping Bag', 'https://cdn-icons-png.flaticon.com/512/869/869636.png'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Hero Background Image URL & Presets
                const Text('Login Screen Hero Background Image',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text_primary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _heroImageUrlController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'e.g. cashier_banner.jpg or web image URL',
                          filled: true,
                          fillColor: AppColors.bg_subtle,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
                          prefixIcon: const Icon(Icons.wallpaper, size: 20, color: AppColors.accent_primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Quick Background Presets
                    PopupMenuButton<String>(
                      tooltip: 'Select Background Preset',
                      onSelected: (url) {
                        setState(() => _heroImageUrlController.text = url);
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'cashier_banner.jpg', child: Text('African Retail Cashier (Default)')),
                        const PopupMenuItem(
                            value: 'https://images.unsplash.com/photo-1556742049-0a67c5574f73?w=1600&q=80',
                            child: Text('Supermarket Checkout Counter')),
                        const PopupMenuItem(
                            value: 'https://images.unsplash.com/photo-1604719312566-8912e9227c6a?w=1600&q=80',
                            child: Text('Modern Grocery Aisle')),
                        const PopupMenuItem(
                            value: 'https://images.unsplash.com/photo-1578916171728-46686eac8d58?w=1600&q=80',
                            child: Text('Boutique & Retail Counter')),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.bg_subtle,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border_subtle),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.photo_library_outlined, size: 16, color: AppColors.accent_primary),
                            SizedBox(width: 6),
                            Text('Background Presets', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Icon(Icons.arrow_drop_down, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ─── 2. Users, Roles & Staff Access Section ──────────────────
            _buildSection(
              title: 'Users, Roles & Staff Access Control',
              icon: Icons.manage_accounts_outlined,
              headerTrailing: FilledButton.icon(
                onPressed: () => _showUserEditorModal(),
                icon: const Icon(Icons.person_add_alt_1, size: 16),
                label: const Text('Add Staff Member'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent_primary,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              children: [
                const Text(
                  'Manage authorized till attendants, supervisors, and store managers. Each staff member logs into the POS terminal with their personalized 4-digit PIN.',
                  style: TextStyle(fontSize: 13, color: AppColors.text_secondary, height: 1.4),
                ),
                const SizedBox(height: 18),

                // Staff Cards List
                ...users.map((u) {
                  final isCurrent = widget.state.currentLoggedInUser?.id == u.id;
                  final rColor = _roleColor(u.role);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.bg_subtle,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCurrent ? AppColors.accent_primary : AppColors.border_subtle,
                        width: isCurrent ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: u.color.withValues(alpha: 0.15),
                          child: Text(
                            u.initials,
                            style: TextStyle(color: u.color, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    u.fullName,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.text_primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: rColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      u.roleDisplay,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: rColor,
                                      ),
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent_light,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: AppColors.accent_primary.withValues(alpha: 0.3)),
                                      ),
                                      child: const Text(
                                        'Current Session',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accent_primary),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.phone_outlined, size: 12, color: AppColors.text_tertiary),
                                  const SizedBox(width: 4),
                                  Text(u.phone, style: const TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.vpn_key_outlined, size: 12, color: AppColors.text_tertiary),
                                  const SizedBox(width: 4),
                                  Text('PIN: ${u.pin}', style: const TextStyle(fontSize: 12, color: AppColors.text_secondary, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Active Toggle
                        Row(
                          children: [
                            Text(
                              u.active ? 'Active' : 'Disabled',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: u.active ? AppColors.status_success : AppColors.text_tertiary,
                              ),
                            ),
                            Transform.scale(
                              scale: 0.8,
                              child: Switch(
                                value: u.active,
                                activeThumbColor: AppColors.accent_primary,
                                onChanged: (val) {
                                  widget.state.toggleUserActive(u.id);
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Edit User & PIN',
                          icon: const Icon(Icons.edit_outlined, color: AppColors.text_secondary, size: 18),
                          onPressed: () => _showUserEditorModal(existingUser: u),
                        ),
                        if (users.length > 1)
                          IconButton(
                            tooltip: 'Delete User',
                            icon: const Icon(Icons.delete_outline, color: AppColors.status_danger, size: 18),
                            onPressed: () {
                              widget.state.deleteUser(u.id);
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Removed ${u.fullName} from staff accounts.')),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),

            const SizedBox(height: 24),

            // ─── 3. Hardware & Peripherals ─────────────────────────────────
            _buildSection(
              title: 'Hardware & Peripherals',
              icon: Icons.print_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Receipt Thermal Printer', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text_primary)),
                          SizedBox(height: 4),
                          Text('Select standard paper roll width for ESC/POS output',
                              style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                        ],
                      ),
                    ),
                    DropdownButton<String>(
                      value: _printerPaperSize,
                      dropdownColor: AppColors.bg_surface,
                      style: const TextStyle(color: AppColors.text_primary, fontWeight: FontWeight.bold),
                      items: ['80mm', '58mm'].map((s) {
                        return DropdownMenuItem(value: s, child: Text(s == '80mm' ? '80mm (Standard)' : '58mm (Compact)'));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _printerPaperSize = val);
                      },
                    ),
                  ],
                ),
                const Divider(color: AppColors.border_subtle, height: 28),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-print receipt on charge', style: TextStyle(color: AppColors.text_primary, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Immediately triggers thermal print job when transaction completes',
                      style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                  value: _autoPrintReceipt,
                  activeThumbColor: AppColors.accent_primary,
                  onChanged: (val) => setState(() => _autoPrintReceipt = val),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Kick Cash Drawer Pulse', style: TextStyle(color: AppColors.text_primary, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Send 24V solenoid pulse to RJ11 port on cash payments',
                      style: TextStyle(fontSize: 12, color: AppColors.text_tertiary)),
                  value: _cashDrawerKick,
                  activeThumbColor: AppColors.accent_primary,
                  onChanged: (val) => setState(() => _cashDrawerKick = val),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ─── 4. Cloud & Synchronization ───────────────────────────────
            _buildSection(
              title: 'Server & Cloud Synchronization',
              icon: Icons.cloud_sync_outlined,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _serverUrlController,
                        style: const TextStyle(color: AppColors.text_primary, fontSize: 14),
                        decoration: InputDecoration(
                          labelText: 'Shop API Base URL',
                          labelStyle: const TextStyle(color: AppColors.text_secondary),
                          filled: true,
                          fillColor: AppColors.bg_subtle,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border_subtle)),
                          prefixIcon: const Icon(Icons.link, color: AppColors.accent_primary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    ElevatedButton.icon(
                      onPressed: _isCheckingConnection ? null : _testConnection,
                      icon: _isCheckingConnection
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.wifi_tethering, size: 18),
                      label: const Text('Test Ping'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent_primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _connectionResult == true ? AppColors.status_success : AppColors.status_warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _connectionResult == true
                          ? 'Online • Synchronized with shop-api'
                          : 'Offline Fallback Enabled • Local transactions buffered in SQLite/RAM',
                      style: const TextStyle(fontSize: 12, color: AppColors.text_secondary),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ─── 5. Data & Catalogue Reset / Recovery ────────────────────
            _buildSection(
              title: 'Data & Catalogue Management',
              icon: Icons.storage_outlined,
              children: [
                Text(
                  '${widget.state.products.length} products in catalogue • ${widget.state.users.length} registered staff members.',
                  style: const TextStyle(fontSize: 13, color: AppColors.text_secondary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('Reset Catalogue to Defaults'),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reset Catalogue?'),
                            content: const Text('This will restore the factory sample product catalogue. Current customized products will be replaced.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: AppColors.status_danger),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  widget.state.resetCatalogueToDefaults();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Catalogue restored to defaults.')));
                                },
                                child: const Text('Confirm Reset'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.people_outline, size: 16),
                      label: const Text('Reset Staff Accounts'),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reset Staff Accounts?'),
                            content: const Text('This will restore the default staff accounts and PINs.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: AppColors.status_danger),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  widget.state.resetUsersToDefaults();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff accounts reset to defaults.')));
                                },
                                child: const Text('Confirm Reset'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 36),

            // Bottom Sticky Save Bar
            Center(
              child: SizedBox(
                width: 320,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _saveAllSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 20),
                  label: Text(_isSaving ? 'Saving Changes...' : 'Save All Settings'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent_primary,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.text_secondary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.text_primary, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppColors.bg_subtle,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border_subtle)),
          ),
        ),
      ],
    );
  }

  Widget _logoPresetChip(String label, String url) {
    final isSelected = (_pendingLogoBase64 == null || _pendingLogoBase64!.isEmpty) &&
        _brandLogoUrlController.text.trim() == url;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _brandLogoUrlController.text = url;
          _pendingLogoBase64 = null;
          _clearLogo = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.accent_primary.withAlpha(25) : AppColors.bg_subtle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.accent_primary : AppColors.border_subtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.accent_primary : AppColors.text_secondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    Widget? headerTrailing,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.bg_surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border_subtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.accent_primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text_primary),
                ),
              ),
              if (headerTrailing != null) headerTrailing,
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}
