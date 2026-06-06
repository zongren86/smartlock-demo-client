import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:fluwx/fluwx.dart';
import 'package:provider/provider.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/main.dart';
import 'package:smartlockdemo_client/models/borrow_order.dart';
import 'package:smartlockdemo_client/screens/success_screen.dart';
import 'package:smartlockdemo_client/services/api_service.dart';
import 'package:smartlockdemo_client/services/wx_pay_service.dart';
import 'package:tobias/tobias.dart' as tobias;
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';

class PaymentScreen extends StatefulWidget {
  final String qrCode;
  final String? knownMac;
  final int knownBattery; // -1 if unavailable
  const PaymentScreen({super.key, required this.qrCode, this.knownMac, this.knownBattery = -1});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final ApiService _api = ApiService();
  final WxPayService _wxPay = WxPayService();

  bool _loading = false;
  bool _loadingOrder = true;
  bool _orderLoadFailed = false; // 订单加载失败（区别于支付失败）
  String? _orderId;
  String? _resolvedMac;
  String? _errorMsg;
  String? _loadingStatus; // 冷启动重试时展示的状态文字
  StreamSubscription? _payResultSub;
  Timer? _pollTimer;
  int _pollCount = 0;

  BorrowOrderModel? _order;

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    if (mounted) setState(() { _loadingOrder = true; _orderLoadFailed = false; _errorMsg = null; _loadingStatus = null; });
    const maxRetries = 10;
    final s = S.read(context);
    final userId = context.read<AppState>().userId;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final order = await _api.createOrder(widget.qrCode, userId);
        // ✅ 必须获取真实BLE MAC用于开锁时精确匹配（防止串锁）
        final bleMac = await _api.resolveDeviceBleMac(widget.qrCode);
        // ⚠️ 如果后端未返回真实BLE MAC，则不能开锁（防止误开）
        if (bleMac == null || bleMac.isEmpty) {
          throw Exception('设备MAC地址未找到，请确保设备已正确注册 / Device MAC address not found');
        }
        if (mounted) setState(() {
          _order = order;
          _orderId = order.orderId;
          _resolvedMac = bleMac;  // ✅ 强制使用真实BLE MAC
          _loadingOrder = false;
          _loadingStatus = null;
        });
        return;
      } on DioException catch (e) {
        // unknown 类型包含 HandshakeException（Render 冷启动时 TLS 握手中断）
        final isConnError = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            (e.type == DioExceptionType.unknown &&
                (e.error?.toString().contains('HandshakeException') == true ||
                 e.error?.toString().contains('Connection terminated') == true ||
                 e.error?.toString().contains('SocketException') == true));
        if (isConnError && attempt < maxRetries) {
          if (mounted) setState(() =>
            _loadingStatus = s.serverStarting(attempt + 1, maxRetries));
          await Future.delayed(const Duration(seconds: 5));
          continue;
        }
        if (mounted) setState(() {
          _loadingOrder = false;
          _orderLoadFailed = true;
          _loadingStatus = null;
          _errorMsg = '${s.loadOrderFailed}：${e.message ?? e.toString()}';
        });
        return;
      } catch (e) {
        if (mounted) setState(() {
          _loadingOrder = false;
          _orderLoadFailed = true;
          _loadingStatus = null;
          _errorMsg = '${s.loadOrderFailed}：$e';
        });
        return;
      }
    }
  }

  @override
  void dispose() {
    _payResultSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<BorrowOrderModel?> _ensureOrder() async {
    return _order; // 按钮已通过 _order==null 禁用，此处只做防御
  }

  // ── Free Use ────────────────────────────────────────────────────

  Future<void> _startFreePay() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final userId = context.read<AppState>().userId;
      // 创建免费订单，客户端强制金额为0（使用金额和押金都为0）
      final freeOrder = await _api.createOrder(widget.qrCode, userId, isFreeUse: true);
      final zeroOrder = freeOrder.copyWith(usageAmount: 0, depositAmount: 0);
      setState(() => _order = zeroOrder);
      if (mounted) await _handleMockPay(freeOrder.orderId);
    } catch (e) {
      setState(() { _errorMsg = '$e'; _loading = false; });
    }
  }

  // ── WeChat Pay ──────────────────────────────────────────────────

  Future<void> _startWxPay() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final order = await _ensureOrder();
      if (order == null) return;

      if (order.isMock) {
        await _handleMockPay(order.orderId);
        return;
      }

      final wxInstalled = await _wxPay.isWeChatInstalled();
      if (!wxInstalled) {
        await _handleMockPay(order.orderId);
        return;
      }

      _payResultSub = _wxPay.payResultStream.listen(_onWxPayResult);
      final launched = await _wxPay.launchPay(order);
      if (!launched) {
        setState(() { _errorMsg = S.read(context).launchPayFailed; _loading = false; });
      }
    } catch (e) {
      setState(() { _errorMsg = '${S.read(context).payInitFailed}: $e'; _loading = false; });
    }
  }

  void _onWxPayResult(WeChatPaymentResponse resp) {
    _payResultSub?.cancel();
    if (resp.errCode == 0) {
      _startPolling();
    } else if (resp.errCode == -2) {
      setState(() { _errorMsg = S.read(context).paymentCancelled; _loading = false; });
    } else {
      setState(() { _errorMsg = '${S.read(context).paymentFailed}（errCode: ${resp.errCode}）'; _loading = false; });
    }
  }

  // ── Alipay ──────────────────────────────────────────────────────

  Future<void> _startAlipay() async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final order = await _ensureOrder();
      if (order == null) return;

      final result = await _api.createAlipayOrder(order.orderId);

      if (result['mock'] == true) {
        await _handleMockPay(order.orderId);
        return;
      }

      final orderString = result['orderString'] as String?;
      if (orderString == null || orderString.isEmpty) {
        setState(() { _errorMsg = S.read(context).alipayParamFailed; _loading = false; });
        return;
      }

      final payResult = await tobias.Tobias().pay(orderString);
      final resultStatus = payResult['resultStatus']?.toString() ?? '';

      if (resultStatus == '9000') {
        _startPolling();
      } else if (resultStatus == '6001') {
        setState(() { _errorMsg = S.read(context).paymentCancelled; _loading = false; });
      } else {
        setState(() {
          _errorMsg = S.read(context).alipayFailed(payResult['memo']?.toString() ?? resultStatus);
          _loading = false;
        });
      }
    } catch (e) {
      setState(() { _errorMsg = '${S.read(context).alipayLaunchFailed}: $e'; _loading = false; });
    }
  }

  // ── 轮询 / Mock ─────────────────────────────────────────────────

  void _startPolling() {
    _pollCount = 0;
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 2000),
      (_) => _pollOrderStatus(),
    );
  }

  Future<void> _pollOrderStatus() async {
    if (_orderId == null) return;
    _pollCount++;
    if (_pollCount > 30) {
      _pollTimer?.cancel();
      setState(() { _errorMsg = S.read(context).payConfirmTimeout; _loading = false; });
      return;
    }
    try {
      final status = await _api.getOrderStatus(_orderId!);
      if (status.isPaid && status.unlockToken != null) {
        _pollTimer?.cancel();
        await _navigateToUnlock(status);
      }
    } catch (_) {}
  }

  Future<void> _handleMockPay(String orderId) async {
    await Future.delayed(const Duration(seconds: 1));
    final status = await _api.mockPay(orderId);
    if (mounted) await _navigateToUnlock(status);
  }

  Future<void> _navigateToUnlock(OrderStatus status) async {
    if (!mounted) return;
    // 优先使用已知的真实BLE MAC，防止串锁
    final mac = widget.knownMac ?? (_resolvedMac ?? '');
    setState(() => _loading = false);

    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UnlockDialog(
        mac: mac,
        qrCode: widget.qrCode,
        orderId: status.orderId,
        unlockToken: status.unlockToken!,
        battery: widget.knownBattery,
      ),
    );

    if (success == true && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SuccessScreen(mac: mac, orderId: status.orderId),
        ),
      );
    }
  }

  // ── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(S.of(context).paymentTitle),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: Colors.black87,
      ),
      body: Column(
        children: [
          _buildHint(),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingOrder)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          const Center(child: CircularProgressIndicator(color: Color(0xFF1A73E8))),
                          if (_loadingStatus != null) ...[
                            const SizedBox(height: 12),
                            Text(_loadingStatus!, style: const TextStyle(fontSize: 13, color: Color(0xFF888888))),
                          ],
                        ],
                      ),
                    )
                  else
                    _buildInfoTable(),
                  if (_errorMsg != null) _buildErrorBox(),
                ],
              ),
            ),
          ),
          _buildPayButtons(),
        ],
      ),
    );
  }

  Widget _buildInfoTable() {
    final order = _order;
    final s = S.of(context);
    return Column(
      children: [
        Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.grey.shade200),
          ),
          columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
          children: [
            _tableRow(s.deviceId, widget.qrCode),
            if (widget.knownBattery >= 0)
              _tableRow(s.batteryLevel, '${widget.knownBattery}%'),
            if (order != null) ...[
              _tableRow(s.usageFee, s.currency(order.usageAmount)),
              _tableRow(s.deposit, s.currency(order.depositAmount)),
              _tableRowHighlight(s.total, s.currency(order.totalAmount)),
              _tableRow(s.depositValidity, s.depositValidityValue(order.depositExpiryMinutes)),
            ],
          ],
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey.shade200),
              bottom: BorderSide(color: Colors.grey.shade200),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.otherNotes, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
              const SizedBox(height: 6),
              Text('1. ${s.autoRefundOnReturn}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.5)),
              Text('2. ${s.depositForfeitNote}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  TableRow _tableRow(String label, String value) {
    return _tableRowWidget(label,
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)));
  }

  TableRow _tableRowWidget(String label, Widget valueWidget) {
    return TableRow(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: valueWidget,
      ),
    ]);
  }

  TableRow _tableRowHighlight(String label, String value) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFF0F7FF)),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w600)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1A73E8))),
        ),
      ],
    );
  }

  Widget _buildHint() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Color(0xFFF59E0B)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(S.of(context).payAfterUnlock,
                style: const TextStyle(fontSize: 13, color: Color(0xFFF59E0B))),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13))),
            ],
          ),
          if (_orderLoadFailed) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _loadOrder,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(S.read(context).retry),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPayButtons() {
    final disabled = _loading || _order == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 支付宝 + 微信支付 ──────────────────────────────────
          Row(
            children: [
              Expanded(child: _payBtn(
                onPressed: disabled ? null : _startAlipay,
                color: const Color(0xFF1677FF),
                icon: Icons.account_balance_wallet_outlined,
                label: S.of(context).alipay,
              )),
              const SizedBox(width: 10),
              Expanded(child: _payBtn(
                onPressed: disabled ? null : _startWxPay,
                color: const Color(0xFF07C160),
                icon: Icons.wechat,
                label: S.of(context).wechatPay,
              )),
            ],
          ),
          const SizedBox(height: 12),
          // ── 免费使用 ─ 突出显示 ────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: disabled ? null : _startFreePay,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),  // 琥珀色，醒目
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFF59E0B).withOpacity(0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              child: _loading
                  ? const SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.card_giftcard, size: 22, color: Colors.white),
                        const SizedBox(width: 10),
                        Text(S.of(context).freeUse,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                                color: Colors.white, letterSpacing: 0.3)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _payBtn({
    required VoidCallback? onPressed,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withOpacity(0.45),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: _loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 17),
                  const SizedBox(height: 2),
                  Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
      ),
    );
  }
}

class _UnlockDialog extends StatefulWidget {
  final String mac;
  final String qrCode;
  final String orderId;
  final String unlockToken;
  final int battery;
  const _UnlockDialog({required this.mac, required this.qrCode, required this.orderId, required this.unlockToken, this.battery = -1});

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> with SingleTickerProviderStateMixin {
  final SmartLockSdk _sdk = SmartLockSdk();
  final ApiService _api = ApiService();
  late AnimationController _animController;
  late Animation<double> _pulseAnim;

  String? _progressMsg;
  bool _failed = false;
  String? _errorMsg;
  // 开锁成功后是否启动了后台遥测（若是，disconnect 交由 _doTelemetry 负责）
  bool _telemetryStarted = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
    _performUnlock();
  }

  Future<void> _performUnlock() async {
    if (mounted) setState(() { _failed = false; _errorMsg = null; _progressMsg = null; });
    bool success = false;
    try {
      // ✅ SDK接口2：unlock — 连接并开锁，传入targetBleMac进行严格验证防止串锁
      await _sdk.unlock(
        widget.mac,  // 真实BLE MAC（来自后端resolveDeviceBleMac）
        '', // encryptedStr：当前版本暂不验证
        onProgress: (msg) {
          if (mounted) setState(() => _progressMsg = msg);
        },
        targetBleMac: widget.mac,  // ✅ 用同一个MAC进行双向验证
      );
      // 开锁成功后立即启动遥测（BLE连接仍活跃），与 confirmUnlocked 并发
      _telemetryStarted = true;
      unawaited(_doTelemetry());
      // ✅ 确认解锁时上报实际连接的BLE MAC
      await _confirmUnlockedWithRetry();
      success = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() { _failed = true; _errorMsg = e.toString(); });
    } finally {
      if (!success) await _sdk.disconnect();
    }
  }

  /// confirmUnlocked 含重试：Render 免费服务器可能 TCP 连接被重置（errno=104），最多重试3次
  Future<void> _confirmUnlockedWithRetry() async {
    const maxRetries = 3;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _api.confirmUnlocked(widget.orderId, widget.mac, battery: widget.battery);
        return;
      } on DioException catch (e) {
        final isConnErr = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            (e.type == DioExceptionType.unknown &&
                (e.error?.toString().contains('Connection reset') == true ||
                 e.error?.toString().contains('SocketException') == true));
        if (isConnErr && attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        rethrow;
      }
    }
  }

  /// 开锁成功后在活跃连接上采集遥测（§3.21-3.27），完成后断开
  Future<void> _doTelemetry() async {
    // SDK接口5：reportData — 采集遥测后通过回调上报
    await _sdk.reportData(
      widget.qrCode,
      '', // encryptedStr：当前版本暂不验证
      onReport: (data) => _api.reportTelemetryData(widget.qrCode, data),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    if (!_telemetryStarted) _sdk.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: _failed,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: _failed
                        ? Colors.red.shade50
                        : const Color(0xFF1A73E8).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _failed ? Icons.lock : Icons.bluetooth_searching,
                    size: 40,
                    color: _failed ? Colors.red : const Color(0xFF1A73E8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _failed ? s.unlockFailedTitle : s.unlockingTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _failed ? Colors.red : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _progressMsg ?? s.preparingMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              if (_failed && _errorMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  ),
                ),
              ],
              if (!_failed) ...[
                const SizedBox(height: 8),
                Text(s.keepPhoneNear,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
              ],
              if (_failed) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _performUnlock,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(s.retry),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(s.cancel,
                      style: const TextStyle(color: Color(0xFF6B7280))),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
