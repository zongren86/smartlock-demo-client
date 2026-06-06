import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartlockdemo_client/services/api_service.dart';
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';

class LocaleNotifier extends ChangeNotifier {
  static const _key = 'app_lang';
  String _lang = 'en';

  String get lang => _lang;
  bool get isEn => _lang == 'en';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString(_key) ?? 'en';
    ApiService.setLang(_lang);
    SmartLockSdk.setLang(_lang);
    notifyListeners();
  }

  Future<void> setLang(String lang) async {
    _lang = lang;
    ApiService.setLang(lang);
    SmartLockSdk.setLang(lang);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, lang);
  }
}

class S {
  final bool _en;
  const S._(this._en);

  static S of(BuildContext context) =>
      S._(context.watch<LocaleNotifier>().isEn);

  static S read(BuildContext context) =>
      S._(context.read<LocaleNotifier>().isEn);

  String _t(String zh, String en) => _en ? en : zh;

  // ── App wide ────────────────────────────────────────────────────
  String get appTitle => _t('智能锁', 'SmartLock');
  String get cancel => _t('取消', 'Cancel');
  String get confirm => _t('确认', 'Confirm');
  String get retry => _t('重试', 'Retry');
  String get back => _t('返回', 'Back');
  String get loading => _t('加载中...', 'Loading...');
  String get networkError => _t('网络请求失败，请重试', 'Network error, please retry');

  // ── Home ────────────────────────────────────────────────────────
  String get unlockTitle => _t('开锁使用', 'Unlock Device');
  String get tapToScan => _t('点击扫码开始使用', 'Tap to scan and use');
  String get paidPendingUnlock => _t('支付成功，待开锁', 'Payment received, unlocking soon');
  String get deviceInUse => _t('使用中', 'In Use');
  String get historyTitle => _t('使用记录', 'History');
  String get returnRefund => _t('上锁退款', 'Return & Refund');
  String get proxyReturn => _t('代关退款', 'Proxy Return');
  String get supportComingSoon => _t('客服功能即将上线', 'Support coming soon');
  String get noActiveDevice => _t('暂无使用中的设备', 'No active device');
  String orderLabel(String id) => _t('订单 $id', 'Order $id');
  String get fetchDeviceFailed => _t('获取设备信息失败', 'Failed to get device info');
  String get goUnlock => _t('去开锁', 'Unlock');
  String get howToUse => _t('使用说明', 'How to Use');
  String get step1 => _t('点击"开锁使用"扫描设备上的二维码', 'Tap "Unlock Device" to scan the QR code');
  String get step2 => _t('支付使用费及押金', 'Pay the usage fee and deposit');
  String get step3 => _t('支付成功后设备自动解锁', 'Device unlocks automatically after payment');
  String get step4 => _t('用完后扣合锁舌，点击"上锁退款"', 'Lock the trolley, then tap "Return & Refund"');

  // ── Proxy Return ─────────────────────────────────────────────────
  String get proxyLockQuerying => _t('正在查询订单...', 'Looking up order...');
  String get proxyLockCheckingStatus => _t('正在检测锁状态...', 'Checking lock status...');
  String get proxyLockNeedsLock => _t('设备未上锁', 'Trolley Not Locked');
  String get proxyLockAlreadyLocked => _t('设备已上锁', 'Trolley Already Locked');
  String get proxyLockSuccess => _t('关锁成功', 'Locked Successfully');
  String get proxyLockEngageLock => _t('设备尚未上锁，请将锁舌扣合后点击"已关锁"', 'Trolley is not locked. Please engage the lock, then tap "Confirm Locked".');
  String get proxyLockAlreadyLockedDesc => _t('设备已处于关锁状态，无需操作', 'The device is already locked. No action needed.');
  String get proxyLockSuccessDesc => _t('设备已成功关锁', 'The device has been locked successfully.');
  String get proxyLockConfirmBtn => _t('已关锁', 'Confirm Locked');
  String get proxyLockNoOrder => _t('该设备暂无使用中的订单', 'No active order found for this device');
  String freeDepositOf(String amount) => _t('免${amount}押金', 'Free Deposit $amount');

  // ── Payment ─────────────────────────────────────────────────────
  String get paymentTitle => _t('开锁确认', 'Payment');
  String get deviceId => _t('设备编号', 'Device ID');
  String get usageFee => _t('使用费', 'Usage Fee');
  String get deposit => _t('押金', 'Deposit');
  String get total => _t('合计', 'Total');
  String get depositValidity => _t('押金有效期', 'Deposit Validity');
  String depositValidityValue(int m) => _t('$m 分钟', '$m min');
  String get refundMethod => _t('退还方式', 'Refund');
  String get autoRefundOnReturn => _t('上锁后自动退款', 'Auto-refund after locking');
  String get otherNotes => _t('其他说明', 'Note');
  String get depositForfeitNote => _t('超时未还将扣押金', 'Deposit forfeited if overdue');
  String get batteryLevel => _t('当前电量', 'Battery');
  String get payAfterUnlock => _t('请您付款后设备将自动开锁', 'Device unlocks automatically after payment');
  String get alipay => _t('支付宝', 'Alipay');
  String get wechatPay => _t('微信支付', 'WeChat Pay');
  String get freeUse => _t('免费使用（0元）', 'Free to use（\$0.00）');
  String get loadOrderFailed => _t('加载订单失败', 'Failed to load order');
  String serverStarting(int attempt, int max) => _t(
    '服务器启动中，请稍候… ($attempt/$max)',
    'Server is starting up, please wait… ($attempt/$max)',
  );
  String get launchPayFailed => _t('唤起微信支付失败', 'Failed to launch WeChat Pay');
  String get payInitFailed => _t('发起支付失败', 'Payment initiation failed');
  String get alipayParamFailed => _t('获取支付宝订单参数失败', 'Failed to get Alipay order details');
  String alipayFailed(String msg) => _t('支付宝支付失败（$msg）', 'Alipay payment failed ($msg)');
  String get alipayLaunchFailed => _t('发起支付宝支付失败', 'Failed to launch Alipay');
  String get paymentCancelled => _t('已取消支付', 'Payment cancelled');
  String get paymentFailed => _t('支付失败，请重试', 'Payment failed, please retry');
  String get payConfirmTimeout => _t('支付结果确认超时，请联系客服', 'Payment timeout, contact support');

  // ── Return ──────────────────────────────────────────────────────
  String get returnTitle => _t('退款确认', 'Refund');
  String get totalPaid => _t('合计支付', 'Total Paid');
  String get usageTime => _t('使用时间', 'Usage Time');
  String get depositExpiry => _t('押金到期', 'Deposit Expiry');
  String get freeDepositTime => _t('免押金时间', 'Free Time Left');
  String get expectedRefund => _t('预计退款', 'Expected Refund');
  String currency(int fen) => _en ? '\$${(fen / 100).toStringAsFixed(2)}' : '¥${(fen / 100).toStringAsFixed(2)}';
  String get depositExpired => _t('¥0.00（押金已扣）', '\$0.00 (deposit forfeited)');
  String get noRefundNote => _t('超时未还将不退押金', 'Deposit forfeited if overdue');
  String get hint => _t('提示', 'Notice');
  String get lockAndRefund => _t('关锁退款', 'Lock & Refund');
  String get returnToHome => _t('返回首页', 'Back to Home');
  String get recheck => _t('重新检测', 'Retry Check');
  String get readyHint => _t('请您关锁并确认', 'Please lock the trolley to proceed');
  String get checkingHint => _t('正在检测锁状态...', 'Checking lock status...');
  String get waitingLockHint => _t('设备尚未上锁，请将锁舌扣合，检测到关锁后将自动退款',
      'Trolley not locked. Please engage the lock — refund will be processed automatically.');
  String get submittingHint => _t('正在发起退款...', 'Processing refund...');
  String get successHint => _t('关锁及退款成功，押金将原路退回', 'Trolley locked and refund processed. Deposit will be returned to your account.');
  String failedHint(String? msg) =>
      _t('退款失败（${msg ?? '请联系客服处理'}），请重试', 'Refund failed (${msg ?? 'contact support'}), please retry');
  String get waitingLockBtn => _t('正在等待关锁...', 'Waiting for lock...');
  String get processingBtn => _t('处理中...', 'Processing...');
  String get bleConnectFailed => _t('无法连接锁具，请靠近设备后重试', 'Cannot connect to lock. Please move closer to the trolley and retry.');
  String get expired => _t('已过期', 'Expired');
  String get calculating => _t('计算中...', 'Calculating...');

  // ── History ─────────────────────────────────────────────────────
  String deviceShortId(String suffix) => _t('设备 ...$suffix', 'Device ...$suffix');
  String get noHistory => _t('暂无使用记录', 'No usage history');
  String get depositDeducted => _t('扣押金', 'Deposit kept');
  String get actualPaid => _t('实付', 'Actual Paid');

  String statusLabel(String status) {
    switch (status) {
      case 'PENDING': return _t('待支付', 'Pending');
      case 'PAID': return _t('已支付', 'Paid');
      case 'UNLOCKED': return _t('使用中', 'In Use');
      case 'RETURNED': return _t('已归还', 'Returned');
      case 'REFUNDED': return _t('已退款', 'Refunded');
      case 'CANCELLED': return _t('已取消', 'Cancelled');
      default: return status;
    }
  }

  // ── Settings ────────────────────────────────────────────────────
  String get settings => _t('设置', 'Settings');
  String get about => _t('关于', 'About');
  String get currentVersion => _t('当前版本', 'Current Version');
  String get updates => _t('更新', 'Updates');
  String get checkUpdate => _t('检查更新', 'Check for Updates');
  String get checkUpdateSub => _t('点击检查是否有新版本', 'Tap to check for new version');
  String get language => _t('语言', 'Language');
  String get switchLanguage => _t('切换语言', 'Language');
  String get chinese => _t('中文', '中文');
  String get english => _t('English', 'English');
  String get alreadyLatest => _t('已是最新版本', 'Already up to date');
  String get checkUpdateFailed => _t('检查更新失败，请稍后重试', 'Failed to check for updates');

  // ── Update dialog ────────────────────────────────────────────────
  String newVersionFound(String v) => _t('发现新版本 v$v', 'New Version v$v');
  String get forceUpdateNote => _t('此版本需要强制更新', 'This update is required');
  String get whatsNew => _t('更新内容：', "What's new:");
  String downloadProgress(int pct) => _t('下载中 $pct%', 'Downloading $pct%');
  String get downloadDone => _t('下载完成，点击安装', 'Downloaded, tap to install');
  String get installing => _t('正在唤起安装程序...', 'Opening installer...');
  String get updateLater => _t('稍后更新', 'Later');
  String get updateNow => _t('立即更新', 'Update Now');
  String get retryDownload => _t('重新下载', 'Retry');
  String get installNow => _t('立即安装', 'Install Now');
  String get installingBtn => _t('安装中...', 'Installing...');
  String get installPermissionDenied =>
      _t('请在设置中开启「安装未知来源应用」权限后重试', 'Please enable "Install unknown apps" in settings');
  String get cannotOpenInstaller => _t('无法打开安装程序', 'Cannot open installer');

  // ── Scan ────────────────────────────────────────────────────────
  String get scanTitle => _t('扫码开锁', 'Scan to Unlock');
  String get scanDeviceQr => _t('扫描设备二维码', 'Scan Device QR Code');
  String get alignQrHint => _t('将设备上的二维码对准框内', 'Align the QR code within the frame');
  String get cameraPermRequired => _t('需要相机权限才能扫码', 'Camera permission is required to scan');
  String get blePermRequired => _t('请在系统设置中允许蓝牙和位置权限，否则无法连接设备', 'Please grant Bluetooth and Location permissions in Settings to connect devices');
  String get bluetoothOffError => _t('请先开启手机蓝牙', 'Please enable Bluetooth on your phone');
  String get invalidQrCode => _t('无效的二维码', 'Invalid QR code');

  // ── Device Connect dialog ────────────────────────────────────────
  String get connectDeviceTitle => _t('连接设备', 'Connect Device');
  String get connectingDeviceStatus => _t('正在连接...', 'Connecting...');
  String get deviceReadyStatus => _t('设备已就绪', 'Device Ready');
  String get connectFailedStatus => _t('连接失败', 'Connection Failed');
  String get connectingDeviceMsg => _t('正在连接设备...', 'Connecting to device...');
  String deviceNoLabel(String id) => _t('设备编号：$id', 'Device: $id');
  String get confirmAndPayBtn => _t('确认使用，去支付', 'Confirm & Pay');
  String get wrongDeviceBtn => _t('不是这个设备，重新扫码', 'Wrong device, scan again');
  String get retryConnectBtn => _t('重新连接', 'Retry');
  String get skipBtBtn => _t('跳过蓝牙，直接支付', 'Skip Bluetooth, pay now');
  String get backRescanBtn => _t('返回重新扫码', 'Back & Rescan');

  // ── Success ──────────────────────────────────────────────────────
  String get unlockSuccessTitle => _t('解锁成功！', 'Unlocked!');
  String get unlockSuccessMsg => _t('购物车已解锁，祝您购物愉快', 'Trolley unlocked. Enjoy your shopping!');
  String get returnMethodLabel => _t('还车方式', 'How to Return');
  String get returnMethodDesc => _t('用完后扣合锁舌即还车', 'Engage the lock to return the trolley');
  String get depositReturnLabel => _t('押金退还', 'Deposit Refund');
  String get depositReturnDesc => _t('还车后自动原路退回', 'Refunded automatically after return');
  String get refundTimeLabel => _t('退款时间', 'Refund Time');
  String get refundTimeDesc => _t('通常不超过1小时', 'Usually within 1 hour');

  // ── Unlocking ────────────────────────────────────────────────────
  String get preparingMsg => _t('正在准备...', 'Preparing...');
  String get unlockFailedTitle => _t('开锁失败', 'Unlock Failed');
  String get unlockingTitle => _t('正在解锁...', 'Unlocking...');
  String get retryingMsg => _t('正在重试...', 'Retrying...');
  String get keepPhoneNear => _t('请保持手机靠近购物车', 'Keep your phone near the trolley');
}
