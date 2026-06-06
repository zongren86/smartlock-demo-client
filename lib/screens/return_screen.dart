import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/models/borrow_order.dart';
import 'package:smartlockdemo_client/services/api_service.dart';
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';

/// 退款确认页流程：
/// ready → (点击关锁退款) → checking(BLE) → waitingForLock(未上锁，轮询等待)
///                                        → submitting(API退款) → success / failed
enum _Phase { ready, checking, waitingForLock, submitting, success, failed }

class ReturnScreen extends StatefulWidget {
  final OrderHistory order;
  const ReturnScreen({super.key, required this.order});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final SmartLockSdk _sdk = SmartLockSdk();
  final ApiService _api = ApiService();

  _Phase _phase = _Phase.ready;
  String? _errorMsg;
  Timer? _pollTimer;
  Timer? _countdownTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.order.depositExpiresAt != null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _now = DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onReturnTapped() async {
    _pollTimer?.cancel();
    setState(() { _phase = _Phase.checking; _errorMsg = null; });

    try {
      final bleId = widget.order.bleMac ?? widget.order.mac;
      // SDK接口3：checkLocked — 连接并检查是否已上锁
      final isLocked = await _sdk.checkLocked(bleId, '');
      if (!mounted) return;
      if (!isLocked) {
        setState(() => _phase = _Phase.waitingForLock);
        _startLockPolling();
        return;
      }
    } catch (e) {
      // BLE unavailable — cannot confirm lock status, block refund
      if (mounted) setState(() {
        _phase = _Phase.failed;
        _errorMsg = S.read(context).bleConnectFailed;
      });
      return;
    }

    await _doRefund();
  }

  void _startLockPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _phase != _Phase.waitingForLock) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final bleId = widget.order.bleMac ?? widget.order.mac;
        // SDK接口3：checkLocked — 轮询检查锁状态
        final isLocked = await _sdk.checkLocked(bleId, '');
        if (isLocked && mounted && _phase == _Phase.waitingForLock) {
          _pollTimer?.cancel();
          await _doRefund();
        }
      } catch (_) {
        // BLE check failed — keep polling
      }
    });
  }

Future<void> _doRefund() async {
    if (!mounted) return;
    setState(() { _phase = _Phase.submitting; _errorMsg = null; });
    try {
      await _returnDeviceWithRetry();
      if (mounted) setState(() => _phase = _Phase.success);
    } catch (e) {
      final msg = e is DioException && (e.message?.isNotEmpty ?? false)
          ? e.message!
          : e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() { _phase = _Phase.failed; _errorMsg = msg; });
    }
  }

  /// returnDevice 含重试：服务器冷启动或长时间等待后 TCP 连接被重置，最多重试 4 次
  Future<void> _returnDeviceWithRetry() async {
    const maxRetries = 4;
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await _api.returnDevice(widget.order.orderId);
        return;
      } on DioException catch (e) {
        final isConnErr = e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            (e.type == DioExceptionType.unknown &&
                (e.error?.toString().contains('Connection reset') == true ||
                 e.error?.toString().contains('SocketException') == true ||
                 e.error?.toString().contains('HandshakeException') == true));
        if (isConnErr && attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 4));
          continue;
        }
        rethrow;
      }
    }
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${_p(dt.month)}-${_p(dt.day)} '
      '${_p(dt.hour)}:${_p(dt.minute)}';

  String _p(int v) => v.toString().padLeft(2, '0');

  /// Returns HH:MM:SS remaining, or null if expired / no expiry
  String? _countdownText() {
    final expiry = widget.order.depositExpiresAt;
    if (expiry == null) return null;
    final diff = expiry.difference(_now);
    if (diff.isNegative) return null;
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    final s = diff.inSeconds % 60;
    return '${_p(h)}:${_p(m)}:${_p(s)}';
  }

  // ── build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(S.of(context).returnTitle),
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: Colors.black87,
      ),
      body: Column(
        children: [
          _buildHintRow(),
          Expanded(
            child: SingleChildScrollView(
              child: _buildTable(),
            ),
          ),
          _buildButtons(),
        ],
      ),
    );
  }

  // ── 信息表格 ───────────────────────────────────────────────────────

  Widget _buildTable() {
    final o = widget.order;
    final usedAt = o.paidAt ?? o.createdAt;
    final countdown = _countdownText();
    final depositExpired = o.depositExpiresAt != null && !_now.isBefore(o.depositExpiresAt!);
    final refund = o.expectedRefund;

    final s = S.of(context);
    return Table(
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade200),
        bottom: BorderSide(color: Colors.grey.shade200),
      ),
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        if (o.usageAmount != null) _row(s.usageFee, s.currency(o.usageAmount!)),
        _row(s.deposit, s.currency(o.depositAmount)),
        _row(s.totalPaid, s.currency(o.amount)),
        _row(s.usageTime, _formatDate(usedAt)),
        if (o.depositExpiresAt != null)
          _row(s.depositExpiry, _formatDate(o.depositExpiresAt!)),
        if (o.depositExpiresAt != null)
          _rowWidget(s.freeDepositTime, _buildCountdownCell(countdown, depositExpired)),
        _row(s.expectedRefund, depositExpired ? s.depositExpired : s.currency(refund)),
        _row(s.otherNotes, s.noRefundNote),
      ],
    );
  }

  Widget _buildCountdownCell(String? countdown, bool expired) {
    if (expired) {
      return Text(S.of(context).expired,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.red));
    }
    return Text(
      countdown ?? S.of(context).calculating,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1A73E8),
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }

  TableRow _row(String label, String value) => _rowWidget(label,
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)));

  TableRow _rowWidget(String label, Widget valueWidget) => TableRow(children: [
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: valueWidget,
    ),
  ]);

  // ── 提示行（随状态变化）────────────────────────────────────────────

  IconData _phaseIcon(_Phase phase) {
    switch (phase) {
      case _Phase.ready:        return Icons.info_outline;
      case _Phase.checking:     return Icons.bluetooth_searching;
      case _Phase.waitingForLock: return Icons.lock_open;
      case _Phase.submitting:   return Icons.hourglass_top;
      case _Phase.success:      return Icons.check_circle_outline;
      case _Phase.failed:       return Icons.error_outline;
    }
  }

  Widget _buildHintRow() {
    String text;
    Color color;

    switch (_phase) {
      case _Phase.ready:
        text = S.of(context).readyHint;
        color = const Color(0xFFF59E0B);
        break;
      case _Phase.checking:
        text = S.of(context).checkingHint;
        color = const Color(0xFF1A73E8);
        break;
      case _Phase.waitingForLock:
        text = S.of(context).waitingLockHint;
        color = const Color(0xFFF59E0B);
        break;
      case _Phase.submitting:
        text = S.of(context).submittingHint;
        color = const Color(0xFF1A73E8);
        break;
      case _Phase.success:
        text = S.of(context).successHint;
        color = const Color(0xFF10B981);
        break;
      case _Phase.failed:
        text = S.of(context).failedHint(_errorMsg);
        color = Colors.red;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_phaseIcon(_phase), size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // ── 按钮区 ────────────────────────────────────────────────────────

  Widget _buildButtons() {
    switch (_phase) {
      case _Phase.ready:
        return _primaryBtn(S.of(context).lockAndRefund, const Color(0xFF1677FF), _onReturnTapped);

      case _Phase.checking:
      case _Phase.submitting:
        return _primaryBtn(S.of(context).processingBtn, const Color(0xFF1677FF), null, loading: true);

      case _Phase.waitingForLock:
        // 必须等待锁舌检测成功才可退款，不提供取消入口
        return _primaryBtn(S.of(context).waitingLockBtn, const Color(0xFF1677FF), null, loading: true);

      case _Phase.success:
        return _primaryBtn(S.of(context).returnToHome, const Color(0xFF1677FF),
            () => Navigator.popUntil(context, (r) => r.isFirst));

      case _Phase.failed:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _primaryBtn(S.of(context).recheck, const Color(0xFF1677FF), _onReturnTapped),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: Text(S.of(context).returnToHome,
                    style: const TextStyle(color: Color(0xFF6B7280))),
              ),
            ),
          ],
        );
    }
  }

  Widget _primaryBtn(String label, Color color, VoidCallback? onTap, {bool loading = false}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            disabledBackgroundColor: color.withOpacity(0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: loading
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ])
              : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}
