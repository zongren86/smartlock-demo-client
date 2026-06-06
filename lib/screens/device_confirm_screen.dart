import 'package:flutter/material.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/screens/payment_screen.dart';
import 'package:smartlockdemo_client/services/api_service.dart';
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';

/// 扫码后：BLE搜索设备 → 连接 → 发送闪灯指令 → 用户确认 → 支付
class DeviceConfirmScreen extends StatefulWidget {
  final String deviceId;

  const DeviceConfirmScreen({super.key, required this.deviceId});

  @override
  State<DeviceConfirmScreen> createState() => _DeviceConfirmScreenState();
}

class _DeviceConfirmScreenState extends State<DeviceConfirmScreen>
    with SingleTickerProviderStateMixin {
  final SmartLockSdk _sdk = SmartLockSdk();
  final ApiService _api = ApiService();
  late AnimationController _anim;

  _Phase _phase = _Phase.scanning;
  String? _statusMsg;
  String? _foundMac;
  int _foundBattery = -1;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _startConnect();
  }

  Future<void> _startConnect() async {
    setState(() { _phase = _Phase.scanning; _errorMsg = null; });
    try {
      String? macHint;
      try { macHint = await _api.resolveDevice(widget.deviceId); } catch (_) {}

      final result = await _sdk.connect(
        widget.deviceId,
        '',
        macHint: macHint,
        onProgress: (msg) {
          if (mounted) setState(() => _statusMsg = msg);
        },
      );
      _foundMac = result.mac;
      _foundBattery = result.battery;
      if (mounted) setState(() => _phase = _Phase.confirmed);
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) _proceedToPayment();
    } catch (e) {
      if (mounted) setState(() { _phase = _Phase.error; _errorMsg = e.toString(); });
    }
  }

  void _proceedToPayment() {
    _sdk.disconnect();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentScreen(
          qrCode: widget.deviceId,
          knownMac: _foundMac,
          knownBattery: _foundBattery,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    _sdk.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(s.connectDeviceTitle),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIcon(),
              const SizedBox(height: 32),
              _buildTitle(s),
              const SizedBox(height: 12),
              Text(
                _statusMsg ?? s.connectingDeviceMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
              ),
              if (_phase == _Phase.confirmed) ...[
                const SizedBox(height: 8),
                Text(
                  s.deviceNoLabel(widget.deviceId),
                  style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
              ],
              if (_errorMsg != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _errorMsg!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade700),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              _buildButtons(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (_phase) {
      case _Phase.scanning:
        return AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Transform.scale(
            scale: 0.9 + _anim.value * 0.2,
            child: Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bluetooth_searching, size: 60, color: Color(0xFF1A73E8)),
            ),
          ),
        );
      case _Phase.confirmed:
        return Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.lock, size: 60, color: Color(0xFF10B981)),
        );
      case _Phase.error:
        return Container(
          width: 120, height: 120,
          decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
          child: Icon(Icons.bluetooth_disabled, size: 60, color: Colors.red.shade400),
        );
    }
  }

  Widget _buildTitle(S s) {
    switch (_phase) {
      case _Phase.scanning:
        return Text(s.connectingDeviceStatus,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold));
      case _Phase.confirmed:
        return Text(s.deviceReadyStatus,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF10B981)));
      case _Phase.error:
        return Text(s.connectFailedStatus,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red));
    }
  }

  Widget _buildButtons(S s) {
    switch (_phase) {
      case _Phase.scanning:
        return const SizedBox.shrink();
      case _Phase.confirmed:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _proceedToPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(s.confirmAndPayBtn,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.backRescanBtn,
                  style: const TextStyle(color: Color(0xFF6B7280))),
            ),
          ],
        );
      case _Phase.error:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _startConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(s.retryConnectBtn, style: const TextStyle(fontSize: 17)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _proceedToPayment,
              child: Text(s.skipBtBtn,
                  style: const TextStyle(color: Color(0xFF9CA3AF))),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.backRescanBtn,
                  style: const TextStyle(color: Color(0xFF6B7280))),
            ),
          ],
        );
    }
  }
}

enum _Phase { scanning, confirmed, error }
