import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pos_state.dart';
import '../theme/tokens.dart';

class StaffManagementView extends StatefulWidget {
  const StaffManagementView({super.key, required this.state});

  final PosState state;

  @override
  State<StaffManagementView> createState() => _StaffManagementViewState();
}

class _StaffManagementViewState extends State<StaffManagementView> {
  Future<void> _showCreateUserDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final pinController = TextEditingController();
    var selectedRole = PosUserRole.cashier;
    var obscurePin = true;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add Staff Account'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Full Name'),
                  TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Grace Wambui',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Mobile Phone Number'),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      hintText: '+254 700 000 000',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _fieldLabel('Staff PIN (4–6 digits)'),
                  TextField(
                    controller: pinController,
                    maxLength: 6,
                    obscureText: obscurePin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      hintText: '4–6 digits',
                      suffixIcon: IconButton(
                        tooltip: obscurePin ? 'Show PIN' : 'Hide PIN',
                        icon: Icon(
                          obscurePin ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setDialogState(() => obscurePin = !obscurePin),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _fieldLabel('Role'),
                  DropdownButtonFormField<PosUserRole>(
                    initialValue: selectedRole,
                    items: PosUserRole.values
                        .where((role) {
                          final actor = widget.state.currentLoggedInUser?.role;
                          if (role == PosUserRole.systemAdmin) {
                            return actor == PosUserRole.systemAdmin;
                          }
                          if (actor == PosUserRole.manager &&
                              role == PosUserRole.owner) {
                            return false;
                          }
                          return true;
                        })
                        .map(
                          (role) => DropdownMenuItem(
                            value: role,
                            child: Text(_roleLabel(role)),
                          ),
                        )
                        .toList(),
                    onChanged: (role) {
                      if (role != null) {
                        setDialogState(() => selectedRole = role);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final phone = phoneController.text.trim();
                final pin = pinController.text.trim();
                if (name.isEmpty) {
                  _showError('Please enter a valid staff name.');
                  return;
                }
                if (phone.replaceAll(RegExp(r'\D'), '').length < 9) {
                  _showError('Enter a valid staff phone number.');
                  return;
                }
                if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
                  _showError('PIN must be 4 to 6 numeric digits.');
                  return;
                }

                try {
                  await widget.state.addUser(
                    PosUser(
                      id: '',
                      fullName: name,
                      phone: phone,
                      pin: pin,
                      role: selectedRole,
                      color: _roleColor(selectedRole),
                    ),
                  );
                } catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          error.toString().replaceFirst('PosException: ', ''),
                        ),
                      ),
                    );
                  }
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              child: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    phoneController.dispose();
    pinController.dispose();
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff account created.'),
          backgroundColor: AppColors.status_success,
        ),
      );
    }
  }

  static Widget _fieldLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.text_secondary,
      ),
    ),
  );

  static Color _roleColor(PosUserRole role) => switch (role) {
    PosUserRole.systemAdmin => const Color(0xFFDC2626),
    PosUserRole.owner => const Color(0xFFD97706),
    PosUserRole.manager => const Color(0xFF7C3AED),
    PosUserRole.cashier => const Color(0xFF10B981),
    PosUserRole.stockClerk => const Color(0xFF2563EB),
  };

  static String _roleLabel(PosUserRole role) => switch (role) {
    PosUserRole.systemAdmin => 'SYSTEM ADMIN',
    PosUserRole.owner => 'OWNER',
    PosUserRole.manager => 'MANAGER',
    PosUserRole.cashier => 'CASHIER',
    PosUserRole.stockClerk => 'STOCK CLERK',
  };

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg_canvas,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.state,
          builder: (context, _) {
            final users = widget.state.users;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.icon(
                            onPressed: widget.state.canCreateUsers
                                ? _showCreateUserDialog
                                : null,
                            icon: const Icon(Icons.person_add_alt_1, size: 16),
                            label: const Text('Add Staff Member'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      for (final user in users)
                        Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: user.color.withValues(
                                alpha: 0.15,
                              ),
                              child: Text(
                                user.initials,
                                style: TextStyle(
                                  color: user.color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(user.fullName),
                            subtitle: Text(user.phone),
                            trailing: Chip(
                              label: Text(user.roleDisplay),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      if (users.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Text('No staff accounts found.'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
