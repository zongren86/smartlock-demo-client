class AppConfig {
  static const String baseUrl = 'https://smartlock.loopcarttech.com';

  // ========== 蓝牙锁硬件参数 ==========
  // AES-128 密钥（十六进制）：来自设备供应商
  static const List<int> aesKey = [
    0x3A, 0x60, 0x43, 0x2A, 0x5C, 0x01, 0x21, 0x1F,
    0x29, 0x1E, 0x0F, 0x4E, 0x0C, 0x13, 0x28, 0x25,
  ];

  // 初始开锁密码（ASCII '000000'）
  static const List<int> defaultPassword = [
    0x30, 0x30, 0x30, 0x30, 0x30, 0x30,
  ];

  // BLE Service UUID
  static const String bleServiceUuid = '0000FEE7-0000-1000-8000-00805F9B34FB';
  // 写特征值（App → 锁）
  static const String bleWriteCharUuid = '000036F5-0000-1000-8000-00805F9B34FB';
  // 读/通知特征值（锁 → App）
  static const String bleNotifyCharUuid = '000036F6-0000-1000-8000-00805F9B34FB';

  // BLE 扫描超时（秒）
  static const int bleScanTimeoutSeconds = 5;
  // BLE 连接操作超时（秒）
  static const int bleOperationTimeoutSeconds = 15;
  // BLE 单条指令响应超时（秒）
  static const int bleCommandTimeoutSeconds = 5;

  // ========== 微信支付 ==========
  // 微信开放平台 AppID（需替换为真实值）
  static const String wxAppId = 'wx_your_app_id';

  // ========== 业务参数 ==========
  // 支付轮询间隔（毫秒）
  static const int payPollingIntervalMs = 2000;
  // 支付轮询最大次数
  static const int payPollingMaxTimes = 30;
}
