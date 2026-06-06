import 'package:flutter/material.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/screens/success_screen.dart';
import 'package:smartlockdemo_client/services/api_service.dart';
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';

/// 独立开锁页（保留作备用入口，主流程已改用 payment_screen 内嵌弹窗）
class UnlockingScreen extends StatefulWidget {
  final String mac;
  final String orderId;
  final String unlockToken;

  const UnlockingScreen({
    super.key,
    required this.mac,
    required this.orderId,
    required this.unlockToken,
  });

  @override
  State<UnlockingScreen> createState() => _UnlockingScreenState();
}

class _UnlockingScreenState extends State<UnlockingScreen>
    with SingleTickerProviderStateMixin {
  final SmartLockSdk _sdk = SmartLockSdk();
  final ApiService _api = ApiService();
  late AnimationController _animController;
  late Animation<double> _pulseAnim;

  String? _progressMsg;
  bool _failed = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
    _performUnlock();
  }

  Future<void> _performUnlock() async {
    if (mounted) setState(() { _failed = false; _errorMsg = null; _progressMsg = null; });
    try {
      await _sdk.unlock(
        widget.mac,
        '',
        onProgress: (msg) {
          if (mounted) setState(() => _progressMsg = msg);
        },
      );
      await _api.confirmUnlocked(widget.orderId, widget.mac);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SuccessScreen(mac: widget.mac, orderId: widget.orderId),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() { _failed = true; _errorMsg = e.toString(); });
    } finally {
      await _sdk.disconnect();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _sdk.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _pulseAnim,
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: _failed
                          ? Colors.red.shade50
                          : const Color(0xFF1A73E8).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _failed ? Icons.lock : Icons.bluetooth_searching,
                      size: 60,
                      color: _failed ? Colors.red : const Color(0xFF1A73E8),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                Text(
                  _failed ? s.unlockFailedTitle : s.unlockingTitle,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _failed ? Colors.red : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 12),

                Text(
                  _progressMsg ?? s.preparingMsg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF6B7280)),
                ),

                if (_failed && _errorMsg != null) ...[
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

                if (_failed) ...[
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      setState(() { _progressMsg = s.retryingMsg; });
                      _performUnlock();
                    },
                    child: Text(s.retry),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                    child: Text(s.cancel,
                        style: const TextStyle(color: Color(0xFF6B7280))),
                  ),
                ],

                if (!_failed) ...[
                  const SizedBox(height: 32),
                  Text(s.keepPhoneNear,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
