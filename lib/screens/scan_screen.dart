import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/screens/payment_screen.dart';
import 'package:smartlockdemo_client/services/api_service.dart';
import 'package:smartlockdemo_client/utils/toast.dart';
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';

/// Parses device code from raw QR value. Returns null if invalid.
String? parseQrDeviceCode(String raw) {
  final cleaned = raw.trim();
  if (cleaned.isEmpty) return null;

  if (cleaned.startsWith('http://') || cleaned.startsWith('https://')) {
    try {
      final uri = Uri.parse(cleaned);
      final id = uri.queryParameters['id'];
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return null;
  }

  if (cleaned.startsWith('smartlock://')) {
    return cleaned.substring('smartlock://'.length);
  }

  return cleaned;
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // autoStart: false — 权限授予前不启动相机，避免首次安装时相机进入错误态（黑屏/! 图标）
  // 权限确认后由 _checkPermissions 显式调用 start()
  MobileScannerController _controller = MobileScannerController(autoStart: false);
  final ApiService _api = ApiService();
  bool _scanned = false;
  bool _controllerDisposed = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted && mounted) {
      showCenterToast(context, S.read(context).cameraPermRequired);
    }
    // BLE 权限批量申请
    final bleResults = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final allBleGranted = bleResults.values.every(
        (s) => s == PermissionStatus.granted || s == PermissionStatus.limited);
    if (!allBleGranted && mounted) {
      showCenterToast(context, S.read(context).blePermRequired);
    }

    // 权限弹窗关闭后启动相机：
    // controller 使用 autoStart:false，因此无论首次还是后续安装，
    // 权限确认后统一在此显式 start()，相机从不处于"错误状态"。
    // 不再跳转新 ScanScreen，避免 ScanScreen 被替换导致 mounted=false，
    // 从而修复"设备已就绪后跳回扫码页"的问题。
    if (cameraStatus.isGranted && mounted && !_controllerDisposed) {
      try { await _controller.start(); } catch (_) {}
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final raw = barcode!.rawValue!;

    final deviceCode = parseQrDeviceCode(raw);


    if (deviceCode == null) {
      showCenterToast(context, '${S.read(context).invalidQrCode}：$raw');
      return;
    }

    // 先 stop+dispose controller，再 setState 触发重建移除 MobileScanner widget
    // 顺序重要：dispose 完成后才允许 Flutter 重建，避免 widget 尝试用已销毁的 controller
    await _controller.stop();
    try { await _controller.dispose(); } catch (_) {}
    _controllerDisposed = true;
    if (!mounted) return;

    // setState(_scanned=true) → build 里条件移除 MobileScanner → AndroidView 销毁 → Camera2 session 释放
    setState(() => _scanned = true);

    // 等一帧，确保 AndroidView native 层彻底销毁后再启动 BLE 扫描
    final postFrame = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => postFrame.complete());
    await postFrame.future;

    if (mounted) _showDeviceConnectDialog(deviceCode);
  }

  Future<void> _showDeviceConnectDialog(String deviceCode) async {
    // connectResult 由 onSuccess 回调在 Navigator.pop 之前写入，
    // 从而不依赖 showDialog 返回值——华为系统手势可能在 dialog 仍显示时
    // 触发返回导致 dialog 以 null 关闭，导致原流程误跳扫码页。
    _DeviceConnectResult? connectResult;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeviceConnectDialog(
        deviceCode: deviceCode,
        api: _api,
        onSuccess: (r) { connectResult = r; },
      ),
    );

    if (!mounted) return;
    if (connectResult != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            qrCode: deviceCode,
            knownMac: connectResult!.mac,
            knownBattery: connectResult!.battery,
          ),
        ),
      );
    } else {
      // 用户点了"重新扫码"或 dialog 被意外关闭：用新 ScanScreen 替换当前页
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      );
    }
  }

  @override
  void dispose() {
    if (!_controllerDisposed) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(S.of(context).scanDeviceQr),
      ),
      body: Stack(
        children: [
          // 扫到 QR 后从 widget tree 移除，触发 AndroidView 销毁以释放 Camera2 session
          if (!_scanned)
            MobileScanner(controller: _controller, onDetect: _onDetect)
          else
            const SizedBox.expand(),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1A73E8), width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0, right: 0,
            child: Text(
              S.of(context).alignQrHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal scan page that pops with a device code — used by proxy return flow.
class ProxyScanPage extends StatefulWidget {
  const ProxyScanPage({super.key});

  @override
  State<ProxyScanPage> createState() => _ProxyScanPageState();
}

class _ProxyScanPageState extends State<ProxyScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.camera.request();
    if (!status.isGranted && mounted) {
      showCenterToast(context, S.read(context).cameraPermRequired);
    }
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final raw = barcode!.rawValue!;
    final deviceCode = parseQrDeviceCode(raw);

    if (deviceCode == null) {
      showCenterToast(context, '${S.read(context).invalidQrCode}：$raw');
      return;
    }

    setState(() => _scanned = true);
    await _controller.stop();
    if (mounted) Navigator.pop(context, deviceCode);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(S.of(context).scanDeviceQr),
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1A73E8), width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 80,
            left: 0, right: 0,
            child: Text(
              S.of(context).alignQrHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceConnectResult {
  final String? mac;
  final int battery; // -1 if unavailable
  _DeviceConnectResult({this.mac, this.battery = -1});
}

class _DeviceConnectDialog extends StatefulWidget {
  final String deviceCode;
  final ApiService api;
  /// 连接成功时在 Navigator.pop 之前调用，确保父页面拿到结果，不受 dialog 关闭方式影响
  final void Function(_DeviceConnectResult) onSuccess;
  const _DeviceConnectDialog({required this.deviceCode, required this.api, required this.onSuccess});

  @override
  State<_DeviceConnectDialog> createState() => _DeviceConnectDialogState();
}

class _DeviceConnectDialogState extends State<_DeviceConnectDialog>
    with SingleTickerProviderStateMixin {
  final SmartLockSdk _sdk = SmartLockSdk();
  late AnimationController _anim;

  _ConnectPhase _phase = _ConnectPhase.connecting;
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
    setState(() { _phase = _ConnectPhase.connecting; _errorMsg = null; _statusMsg = null; });
    if (!mounted) return;
    try {
      // ✅ 获取真实BLE MAC用于macHint（防止串锁）
      String? macHint;
      try {
        // 调用 resolveDeviceInfo 获取完整设备信息，包括真实BLE MAC
        final info = await widget.api.resolveDeviceInfo(widget.deviceCode);
        final bleMac = info['bleMac'] as String?;
        if (bleMac != null && bleMac.isNotEmpty) {
          macHint = bleMac;  // ✅ 优先使用真实BLE MAC加速连接
        } else {
          macHint = widget.deviceCode;  // 降级到设备ID（首次连接时后端还未知晓MAC）
        }
      } catch (_) {
        // API调用失败时，降级到设备ID进行扫描
        macHint = widget.deviceCode;
      }

      // SDK接口1：connect — 扫描+连接+握手+闪灯
      final result = await _sdk.connect(
        widget.deviceCode,
        '', // encryptedStr：当前版本暂不验证
        macHint: macHint,
        onProgress: (msg) {
          if (mounted) setState(() => _statusMsg = msg);
        },
      );
      _foundMac = result.mac;
      _foundBattery = result.battery;
      if (mounted) {
        setState(() => _phase = _ConnectPhase.connected);
        // onSuccess 在 pop 之前调用，确保父页面写入 connectResult 后 dialog 才关闭
        widget.onSuccess(_DeviceConnectResult(mac: _foundMac, battery: _foundBattery));
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() {
        _phase = _ConnectPhase.failed;
        _errorMsg = e.toString().replaceFirst('Exception: ', '');
      });
    }
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
    return PopScope(
      canPop: _phase == _ConnectPhase.failed,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(height: 16),
              _buildTitle(s),
              const SizedBox(height: 8),
              Text(
                _statusMsg ?? s.connectingDeviceMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
              ),
              if (_errorMsg != null) ...[
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
              if (_phase == _ConnectPhase.failed) ...[
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _startConnect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A73E8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(s.retryConnectBtn),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          // 跳过蓝牙：无 MAC，仍进支付页（服务端返回 MAC）
                          widget.onSuccess(_DeviceConnectResult(mac: null));
                          Navigator.pop(context);
                        },
                        child: Text(s.skipBtBtn,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        // 重新扫码：不设 onSuccess → connectResult=null → 父页面跳新扫码页
                        onPressed: () => Navigator.pop(context),
                        child: Text(s.backRescanBtn,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    switch (_phase) {
      case _ConnectPhase.connecting:
        return AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Transform.scale(
            scale: 0.9 + _anim.value * 0.2,
            child: Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF1A73E8).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bluetooth_searching, size: 40, color: Color(0xFF1A73E8)),
            ),
          ),
        );
      case _ConnectPhase.connected:
        return Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle, size: 40, color: Color(0xFF10B981)),
        );
      case _ConnectPhase.failed:
        return Container(
          width: 80, height: 80,
          decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
          child: Icon(Icons.bluetooth_disabled, size: 40, color: Colors.red.shade400),
        );
    }
  }

  Widget _buildTitle(S s) {
    switch (_phase) {
      case _ConnectPhase.connecting:
        return Text(s.connectingDeviceStatus,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
      case _ConnectPhase.connected:
        return Text(s.deviceReadyStatus,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF10B981)));
      case _ConnectPhase.failed:
        return Text(s.connectFailedStatus,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red));
    }
  }
}

enum _ConnectPhase { connecting, connected, failed }
