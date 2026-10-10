import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pos_state.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../shared/icons.dart';

/// First-launch onboarding screen that asks the device operator for a
/// shop code and resolves it to a server URL before unlocking the POS.
class ShopCodeView extends StatefulWidget {
  const ShopCodeView({
    super.key,
    required this.state,
    required this.onConnected,
  });

  final PosState state;
  final VoidCallback onConnected;

  @override
  State<ShopCodeView> createState() => _ShopCodeViewState();
}

class _ShopCodeViewState extends State<ShopCodeView> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter a shop code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    String url;
    if (code == 'LOCAL') {
      url = 'http://localhost:4001';
    } else {
      url = await ApiService.instance.resolveShopCode(code);
      if (url.isEmpty) {
        setState(() {
          _loading = false;
          _error = ApiService.instance.lastError ?? 'Shop code not found.';
        });
        return;
      }
    }

    ApiService.instance.configure(url);
    final healthy = await ApiService.instance.checkHealth();
    if (!healthy) {
      setState(() {
        _loading = false;
        _error = 'Could not reach the shop server at $url. Check your network.';
      });
      return;
    }

    await widget.state.saveSettings(newServerUrl: url);
    if (!mounted) return;
    widget.onConnected();
  }

  Future<void> _useLocalServer() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    const url = 'http://localhost:4001';
    ApiService.instance.configure(url);
    await widget.state.saveSettings(newServerUrl: url);
    if (!mounted) return;
    widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // App logo placeholder
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.accent_primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: Icon(
                        AppIcons.storefront,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Title
                  const Text(
                    'Connect to Your Shop',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.4,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Subtitle
                  const Text(
                    'Enter your shop name or code provided by your administrator.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Shop code text field
                  TextField(
                    controller: _codeController,
                    enabled: !_loading,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      color: Color(0xFF0F172A),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Shop Code',
                      hintText: 'e.g. gutagala',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.accent_primary,
                          width: 2,
                        ),
                      ),
                      hintStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 4,
                        color: Color(0xFFCBD5E1),
                      ),
                      labelStyle: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    onSubmitted: (_) => _connect(),
                  ),

                  // Error message
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFF87171),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Connect button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _connect,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent_primary,
                        disabledBackgroundColor:
                            AppColors.accent_primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text(
                              'Connect',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Dev shortcut
                  TextButton(
                    onPressed: _loading ? null : _useLocalServer,
                    child: const Text(
                      'Use local server (dev)',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
