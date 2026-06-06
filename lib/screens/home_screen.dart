import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/main.dart';
import 'package:smartlockdemo_client/models/borrow_order.dart';
import 'package:smartlockdemo_client/screens/history_screen.dart';
import 'package:smartlockdemo_client/screens/return_screen.dart';
import 'package:smartlockdemo_client/screens/scan_screen.dart';
import 'package:smartlockdemo_client/screens/settings_screen.dart';
import 'package:smartlockdemo_client/screens/unlocking_screen.dart';
import 'package:smartlockdemo_client/main.dart' show routeObserver;
import 'package:smartlockdemo_client/services/api_service.dart';
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';
import 'package:smartlockdemo_client/utils/toast.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with RouteAware {
  final ApiService _api = ApiService();
  OrderHistory? _activeOrder;
  Timer? _countdownTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActiveOrder());
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  String? _depositCountdown() {
    final expiry = _activeOrder?.depositExpiresAt;
    if (expiry == null) return null;
    final diff = expiry.difference(_now);
    if (diff.isNegative) return null;
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void didPopNext() {
    _loadActiveOrder();
  }

  Future<void> _loadActiveOrder() async {
    final userId = context.read<AppState>().userId;
    try {
      final order = await _api.getActiveOrder(userId);
      if (mounted) setState(() => _activeOrder = order);
    } catch (_) {}
  }

  void _handleReturn() {
    if (_activeOrder == null || _activeOrder!.status != 'UNLOCKED') {
      showCenterToast(context, S.read(context).noActiveDevice);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReturnScreen(order: _activeOrder!)),
    ).then((_) => _loadActiveOrder());
  }

  Future<void> _handleProxyReturn() async {
    // Step 1: Scan QR code
    final deviceCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ProxyScanPage()),
    );
    if (deviceCode == null || !mounted) return;

    // Step 2: Query active order for device
    OrderHistory? order;
    bool queryFailed = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF1A73E8)),
              const SizedBox(height: 16),
              Text(S.of(_).proxyLockQuerying,
                  style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
      ),
    );

    try {
      order = await _api.getDeviceActiveOrder(deviceCode);
    } catch (_) {
      queryFailed = true;
    }

    if (!mounted) return;
    Navigator.pop(context); // close loading dialog

    if (queryFailed) {
      showCenterToast(context, S.read(context).proxyLockNoOrder);
      return;
    }

    if (order != null) {
      // Found active order → go to ReturnScreen
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReturnScreen(order: order!)),
      ).then((_) => _loadActiveOrder());
    } else {
      // No active order → toast + async BLE lock (fire-and-forget)
      showCenterToast(context, S.read(context).proxyLockNoOrder);
      _asyncCheckAndLock(deviceCode);
    }
  }

  void _asyncCheckAndLock(String deviceCode) {
    // SDK接口4：lock — 代关场景，连接并主动关锁
    final sdk = SmartLockSdk();
    sdk.lock(deviceCode, '').catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildTopSection(),
              _buildActionRow(),
              if (_activeOrder != null) _buildActiveOrderCard(),
              _buildGuideCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopSection() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A73E8), Color(0xFF0D5BD1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 6),
              child: GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                child: const Icon(Icons.settings_outlined, color: Colors.white70, size: 24),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScanScreen()),
            ).then((_) => _loadActiveOrder()),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
              ),
              child: const Icon(Icons.lock_open, size: 48, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            S.of(context).unlockTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 2),
          Text(
            _activeOrder != null
              ? (_activeOrder!.status == 'PAID' ? S.of(context).paidPendingUnlock : S.of(context).deviceInUse)
              : S.of(context).tapToScan,
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85)),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.history,
            label: S.of(context).historyTitle,
            color: const Color(0xFF1A73E8),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
          ),
          _buildActionButton(
            icon: Icons.lock,
            label: S.of(context).returnRefund,
            color: const Color(0xFF10B981),
            onTap: _handleReturn,
          ),
          _buildActionButton(
            icon: Icons.manage_accounts,
            label: S.of(context).proxyReturn,
            color: const Color(0xFFFF6B35),
            onTap: _handleProxyReturn,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: loading
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: color, strokeWidth: 2.5),
                  )
                : Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _p(int v) => v.toString().padLeft(2, '0');

  Widget _buildActiveOrderCard() {
    final o = _activeOrder!;
    final isPaid = o.status == 'PAID';
    final accentColor = isPaid ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final cardColor = isPaid ? const Color(0xFFFFFBEB) : const Color(0xFFF0FFF4);
    final usedAt = o.paidAt ?? o.createdAt;
    final timeStr = '${_p(usedAt.hour)}:${_p(usedAt.minute)}';
    final countdown = _depositCountdown();
    final expired = o.depositExpiresAt != null && _now.isAfter(o.depositExpiresAt!);
    final s = S.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Order ID + Status badge
          Row(
            children: [
              Expanded(
                child: Text(
                  s.deviceShortId(o.mac.length > 4 ? o.mac.substring(o.mac.length - 4) : o.mac),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isPaid ? s.paidPendingUnlock : s.deviceInUse,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: Usage time + action button
          Row(
            children: [
              Text(
                '${s.usageTime}  $timeStr',
                style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
              ),
              const Spacer(),
              GestureDetector(
                onTap: isPaid ? _handleRetryUnlock : _handleReturn,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPaid ? s.goUnlock : s.returnRefund,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          // Row 3: Free deposit countdown (only if deposit expiry exists)
          if (o.depositExpiresAt != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  s.freeDepositOf(s.currency(o.depositAmount)),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const Spacer(),
                Text(
                  expired ? s.expired : (countdown ?? ''),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: expired ? Colors.red : accentColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleRetryUnlock() async {
    if (_activeOrder == null) return;
    try {
      final mac = _activeOrder!.bleMac ?? await _api.resolveDevice(_activeOrder!.mac);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UnlockingScreen(
            mac: mac,
            orderId: _activeOrder!.orderId,
            unlockToken: '',
          ),
        ),
      ).then((_) => _loadActiveOrder());
    } catch (e) {
      if (mounted) {
        showCenterToast(context, '${S.read(context).fetchDeviceFailed}: $e');
      }
    }
  }

  Widget _buildGuideCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(S.of(context).howToUse, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          _buildStep('1', S.of(context).step1),
          _buildStep('2', S.of(context).step2),
          _buildStep('3', S.of(context).step3),
          _buildStep('4', S.of(context).step4),
        ],
      ),
    );
  }

  Widget _buildStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: const Color(0xFF1A73E8),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: Color(0xFF374151)))),
        ],
      ),
    );
  }
}

