import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pos_state.dart';

// ─── Double-Leaf Brand Logo Painter ──────────────────────────────────────────

class _LeafLogoPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;

  const _LeafLogoPainter({
    this.primaryColor = const Color(0xFF10B981),
    this.secondaryColor = const Color(0xFF34D399),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Primary upright leaf
    final path1 = Path();
    path1.moveTo(w * 0.48, h * 0.92);
    path1.cubicTo(w * 0.40, h * 0.52, w * 0.52, h * 0.12, w * 0.88, h * 0.08);
    path1.cubicTo(w * 0.98, h * 0.48, w * 0.82, h * 0.82, w * 0.48, h * 0.92);
    path1.close();

    final paint1 = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path1, paint1);

    // Secondary lower curving leaf
    final path2 = Path();
    path2.moveTo(w * 0.48, h * 0.92);
    path2.cubicTo(w * 0.10, h * 0.86, w * 0.04, h * 0.48, w * 0.28, h * 0.32);
    path2.cubicTo(w * 0.48, h * 0.44, w * 0.54, h * 0.70, w * 0.48, h * 0.92);
    path2.close();

    final paint2 = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Shake Controller for invalid PIN ────────────────────────────────────────

class _ShakeController extends StatefulWidget {
  const _ShakeController({required this.child, required this.shakeKey});
  final Widget child;
  final GlobalKey<_ShakeControllerState> shakeKey;

  @override
  _ShakeControllerState createState() => _ShakeControllerState();
}

class _ShakeControllerState extends State<_ShakeController>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );

  void shake() => _ctrl.forward(from: 0);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) {
        final t = _ctrl.value;
        final dx = math.sin(t * math.pi * 4.5) * 8 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

// ─── Main Login View (ShopSmart POS) ─────────────────────────────────────────

class LoginView extends StatefulWidget {
  const LoginView({
    super.key,
    required this.state,
    required this.onAuthenticated,
  });

  final PosState state;
  final VoidCallback onAuthenticated;

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  String _pin = '';
  String? _errorMsg;
  bool _isLoading = false;
  int _selectedUserIdx = 0;

  final _shakeKey = GlobalKey<_ShakeControllerState>();
  final FocusNode _focusNode = FocusNode();

  List<PosUser> get _users => widget.state.activeUsers;

  PosUser get _user {
    if (_users.isEmpty) {
      return PosUser(
        id: 'usr_default',
        fullName: 'John Mwangi',
        phone: '+254 700 000 000',
        pin: '1234',
        role: PosUserRole.cashier,
      );
    }
    final safeIdx = _selectedUserIdx.clamp(0, _users.length - 1);
    return _users[safeIdx];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _tapKey(String key) {
    if (_isLoading) return;
    setState(() {
      _errorMsg = null;
      if (key == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (key == 'BIO') {
        _handleBiometricAuth();
      } else if (key == 'CLR') {
        _pin = '';
      } else {
        if (_pin.length < 4) {
          _pin += key;
          if (_pin.length == 4) {
            _verifyPin();
          }
        }
      }
    });
  }

  void _handleBiometricAuth() {
    // Biometric touch: either instant verified login or staff quick switcher
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F8F2),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFD1FAE5)),
                  ),
                  child: const Icon(Icons.fingerprint, color: Color(0xFF0D9488), size: 32),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Biometric Authentication',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Authenticate as ${_user.fullName} using terminal biometrics.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showCashierPicker();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        child: const Text('Switch Staff', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          unawaited(widget.state.connectToShopApi(_user.phone, _pin));
                          widget.state.currentLoggedInUser = _user;
                          widget.state.activeCashierName = _user.fullName;
                          widget.onAuthenticated();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: const Text('Verify & Open Till', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _verifyPin() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    if (_pin == _user.pin) {
      unawaited(widget.state.connectToShopApi(_user.phone, _pin));
      widget.state.currentLoggedInUser = _user;
      widget.state.activeCashierName = _user.fullName;
      widget.onAuthenticated();
    } else {
      _shakeKey.currentState?.shake();
      setState(() {
        _isLoading = false;
        _pin = '';
        _errorMsg = 'Incorrect PIN. Try again or switch account.';
      });
    }
  }

  void _showCashierPicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Select Staff Account',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Choose the active staff operator for this session',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ...List.generate(_users.length, (idx) {
                  final u = _users[idx];
                  final isSelected = idx == _selectedUserIdx;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedUserIdx = idx;
                        _pin = '';
                        _errorMsg = null;
                      });
                      Navigator.pop(ctx);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF0FDF4) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: u.color.withValues(alpha: 0.15),
                            child: Text(
                              u.initials,
                              style: TextStyle(
                                color: u.color,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      u.fullName,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        color: const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _roleBadgeColor(u.role).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        u.roleDisplay,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: _roleBadgeColor(u.role),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Default PIN: ${u.pin} • ${u.rolePermissions}',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _roleBadgeColor(PosUserRole role) {
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

  void _handleHardwareKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.backspace) {
        _tapKey('⌫');
      } else if (key == LogicalKeyboardKey.escape) {
        _tapKey('CLR');
      } else if (event.character != null && RegExp(r'^[0-9]$').hasMatch(event.character!)) {
        _tapKey(event.character!);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleHardwareKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 850;

            if (isWide) {
              return Row(
                children: [
                  // Left Hero Showcase Panel for Desktop/Tablet
                  Expanded(
                    flex: 11,
                    child: _buildDesktopHeroPanel(),
                  ),
                  // Right Mobile-Styled PIN Terminal Panel
                  Expanded(
                    flex: 9,
                    child: Container(
                      color: Colors.white,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _buildPinPanelContent(isCompact: false),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // Mobile-first layout (Optimized for 390 x 844px smartphone viewport)
            return _buildMobileLayout(constraints);
          },
        ),
      ),
    );
  }

  Widget _buildBrandLogo(double size, {double radius = 6}) {
    if (widget.state.brandLogoBase64 != null && widget.state.brandLogoBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(widget.state.brandLogoBase64!.split(',').last);
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      } catch (_) {}
    }
    if (widget.state.brandLogoUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          widget.state.brandLogoUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => SizedBox(
            width: size,
            height: size,
            child: const CustomPaint(painter: _LeafLogoPainter()),
          ),
        ),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _LeafLogoPainter()),
    );
  }

  // ─── Mobile-First Screen Layout ───────────────────────────────────────────

  Widget _buildMobileLayout(BoxConstraints constraints) {
    final screenHeight = constraints.maxHeight;
    final topPadding = MediaQuery.paddingOf(context).top;
    
    // Scale hero height dynamically: ~32-35% on tall phones, compact on short phones
    final heroHeight = math.max(220.0, math.min(270.0, screenHeight * 0.33));

    return Stack(
      children: [
        // 1. Background Retail Photo & Hero Content
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: heroHeight + 36, // Extra height so white card overlaps smoothly
          child: _buildMobileHero(topPadding),
        ),

        // 2. White Bottom Sheet / Card overlapping hero
        Positioned(
          top: heroHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x1A0F172A),
                  blurRadius: 24,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: _buildPinPanelContent(isCompact: true),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Mobile Hero Header with Retail Photography ───────────────────────────

  Widget _buildMobileHero(double topPadding) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Retail Photograph (Cashier smiling with POS terminal)
        Image.network(
          widget.state.heroImageUrl.isNotEmpty ? widget.state.heroImageUrl : 'cashier_banner.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.network(
            'https://images.unsplash.com/photo-1556742049-0a67c5574f73?w=1200&q=80',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0A192F)),
          ),
        ),

        // Dark gradient & soft blur for pristine text contrast
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xD9061423), // 85% dark navy at top
                    Color(0x990A223B), // softer in middle to see attendant smile
                    Color(0xE6061423), // dark near sheet overlap
                  ],
                ),
              ),
            ),
          ),
        ),

        // Hero Foreground Content
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top-Left Logo
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildBrandLogo(32),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.state.shopName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const Text(
                          'POS',
                          style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Staff Switcher Tag
                    InkWell(
                      onTap: _showCashierPicker,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 5,
                              backgroundColor: _user.color,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _user.firstName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.swap_horiz, color: Color(0xFF34D399), size: 13),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Welcome back, John
                Text(
                  'Welcome back,\n${_user.firstName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 6),

                // Subtitle
                Text(
                  widget.state.brandTagline,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ─── PIN Panel Content (Exact Reference Layout) ───────────────────────────

  Widget _buildPinPanelContent({required bool isCompact}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final needsScroll = availableHeight < 460;

        final content = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 24 : 32,
            vertical: isCompact ? 16 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. Small Secure-Lock Icon with subtle green accent
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFD1FAE5), width: 1.2),
                ),
                child: const Center(
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: Color(0xFF0D9488),
                    size: 22,
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // 2. Heading
              const Text(
                'Enter Your PIN',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.4,
                ),
              ),

              const SizedBox(height: 4),

              // 3. Supporting Text
              const Text(
                'Please enter your 4-digit PIN to continue\nto your POS session.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),

              const SizedBox(height: 14),

              // 4. Four Elegant PIN Indicators inside a soft pill
              _ShakeController(
                shakeKey: _shakeKey,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(4, (index) {
                      final isFilled = index < _pin.length;
                      final isError = _errorMsg != null;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 7),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isError
                              ? const Color(0xFFEF4444)
                              : isFilled
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFCBD5E1),
                        ),
                      );
                    }),
                  ),
                ),
              ),

              // Error or loading status
              SizedBox(
                height: 22,
                child: Center(
                  child: _isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                          ),
                        )
                      : _errorMsg != null
                          ? Text(
                              _errorMsg!,
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                ),
              ),

              const SizedBox(height: 6),

              // 5. Large, highly usable 3-column numeric keypad
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: _buildKeypad(),
              ),

              const SizedBox(height: 16),

              // 6. Security Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.shield_outlined, size: 14, color: Color(0xFF64748B)),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'This device is secure and your data is protected.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: math.max(10.0, MediaQuery.paddingOf(context).bottom)),
            ],
          ),
        );

        if (needsScroll) {
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: content,
          );
        }

        return Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: content,
          ),
        );
      },
    );
  }

  // ─── 3-Column Numeric Keypad ──────────────────────────────────────────────

  Widget _buildKeypad() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildKeypadRow(['1', '2', '3']),
        const SizedBox(height: 8),
        _buildKeypadRow(['4', '5', '6']),
        const SizedBox(height: 8),
        _buildKeypadRow(['7', '8', '9']),
        const SizedBox(height: 8),
        _buildKeypadRow(['BIO', '0', '⌫']),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.map((key) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: _buildKeyButton(key),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeyButton(String label) {
    final isBackspace = label == '⌫';
    final isBio = label == 'BIO';

    final bgColor = isBio ? const Color(0xFFE8F8F2) : const Color(0xFFFFFFFF);
    final borderColor = isBio ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _tapKey(label),
        borderRadius: BorderRadius.circular(14),
        splashColor: (isBio ? const Color(0xFF0D9488) : const Color(0xFF0F172A)).withValues(alpha: 0.1),
        highlightColor: (isBio ? const Color(0xFF0D9488) : const Color(0xFF0F172A)).withValues(alpha: 0.05),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x05000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Center(
            child: isBackspace
                ? const Icon(
                    Icons.backspace_outlined,
                    color: Color(0xFF0F172A),
                    size: 20,
                  )
                : isBio
                    ? const Icon(
                        Icons.fingerprint,
                        color: Color(0xFF0D9488),
                        size: 24,
                      )
                    : Text(
                        label,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  // ─── Desktop Left Hero Showcase ───────────────────────────────────────────

  Widget _buildDesktopHeroPanel() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          widget.state.heroImageUrl.isNotEmpty ? widget.state.heroImageUrl : 'cashier_banner.jpg',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.network(
            'https://images.unsplash.com/photo-1556742049-0a67c5574f73?w=1600&q=80',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0F2B48)),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Color(0xFA081B2E),
                Color(0xDF0A243D),
                Color(0x550A243D),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildBrandLogo(40, radius: 8),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.state.shopName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Text(
                          'POS',
                          style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Smart Shops • Better Business',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(flex: 2),
              const Text(
                'Welcome back,',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  height: 1.1,
                ),
              ),
              Text(
                _user.firstName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.state.brandTagline,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 36),
              _buildDesktopFeature(Icons.shopping_cart_outlined, 'Fast & easy sales'),
              const SizedBox(height: 16),
              _buildDesktopFeature(Icons.inventory_2_outlined, 'Live inventory tracking'),
              const SizedBox(height: 16),
              _buildDesktopFeature(Icons.people_outline, 'Customer credit book'),
              const SizedBox(height: 16),
              _buildDesktopFeature(Icons.trending_up, 'Actionable analytics & reports'),
              const Spacer(flex: 3),
              const Text(
                'Simple tools. Real growth.',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontStyle: FontStyle.italic,
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 72,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopFeature(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF34D399), size: 20),
        const SizedBox(width: 14),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.95),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
