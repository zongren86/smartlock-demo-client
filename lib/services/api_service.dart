import 'package:dio/dio.dart';
import 'package:smartlockdemo_client/config/app_config.dart';
import 'package:smartlockdemo_client/models/borrow_order.dart';
import 'package:smartlock_ble_sdk/smartlock_ble_sdk.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _dio.interceptors.add(_LangInterceptor());
  }

  static String _lang = 'zh';

  static void setLang(String lang) {
    _lang = lang;
  }

  final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: {'Content-Type': 'application/json'},
  ));

  /// 发起借用，创建支付订单（qrCode: 设备二维码ID或MAC地址）
  Future<BorrowOrderModel> createOrder(String qrCode, String userId, {bool isFreeUse = false}) async {
    final resp = await _dio.post('/api/orders', data: {
      'qrCode': qrCode,
      'userId': userId,
      if (isFreeUse) 'isFreeUse': true,  // 标记为免费使用
    });
    return BorrowOrderModel.fromJson(resp.data);
  }

  /// 查询订单状态
  Future<OrderStatus> getOrderStatus(String orderId) async {
    final resp = await _dio.get('/api/orders/$orderId');
    return OrderStatus.fromJson(resp.data);
  }

  /// 通知服务端已完成BLE解锁，同时上报真实BLE MAC地址和电量
  Future<void> confirmUnlocked(String orderId, String bleMac, {int battery = -1}) async {
    final data = <String, dynamic>{'bleMac': bleMac};
    if (battery >= 0) data['batteryLevel'] = battery;
    await _dio.post('/api/orders/$orderId/unlocked', data: data);
  }

  /// 归还设备并申请退款
  Future<OrderHistory> returnDevice(String orderId) async {
    final resp = await _dio.post('/api/orders/$orderId/return');
    return OrderHistory.fromJson(resp.data);
  }

  /// 获取用户使用记录
  Future<List<OrderHistory>> getUserHistory(String userId) async {
    final resp = await _dio.get('/api/orders/user/$userId');
    final list = resp.data as List<dynamic>;
    return list.map((e) => OrderHistory.fromJson(e)).toList();
  }

  /// 查询用户当前进行中的订单
  Future<OrderHistory?> getActiveOrder(String userId) async {
    final resp = await _dio.get('/api/orders/user/$userId/active');
    final data = resp.data as Map<String, dynamic>;
    if (data['hasActive'] == false) return null;
    return OrderHistory.fromJson(data);
  }

  /// Mock支付（微信支付未配置时调试用）
  Future<OrderStatus> mockPay(String orderId) async {
    final resp = await _dio.post('/api/orders/$orderId/mock-pay');
    return OrderStatus.fromJson(resp.data);
  }

  /// 创建支付宝订单，返回 orderString（沙箱或正式）
  /// 返回 {'mock': bool, 'orderString': String?}
  Future<Map<String, dynamic>> createAlipayOrder(String orderId) async {
    final resp = await _dio.post('/api/pay/alipay/create/$orderId');
    return Map<String, dynamic>.from(resp.data);
  }

  /// 通过二维码解析设备信息（设备ID和真实BLE MAC）
  /// 返回 {'deviceId': 'AKSJ...', 'bleMac': 'fc:b7:c2:...'} （bleMac可能不存在）
  Future<Map<String, dynamic>> resolveDeviceInfo(String qrCode) async {
    final resp = await _dio.get('/api/orders/resolve', queryParameters: {'qrCode': qrCode});
    return Map<String, dynamic>.from(resp.data);
  }

  /// 获取真实BLE MAC（用于BLE精确匹配，防止串锁）
  /// 返回真实BLE MAC（带冒号格式，如 fc:b7:c2:00:5d:8d），或null
  Future<String?> resolveDeviceBleMac(String qrCode) async {
    try {
      final info = await resolveDeviceInfo(qrCode);
      final bleMac = info['bleMac'] as String?;
      return bleMac?.isNotEmpty == true ? bleMac : null;
    } catch (_) {
      return null;
    }
  }

  /// 通过二维码解析设备ID（AKSJ开头）
  /// 兼容旧API，现在从新的resolveDeviceInfo获取
  Future<String> resolveDevice(String qrCode) async {
    final info = await resolveDeviceInfo(qrCode);
    return info['deviceId'] as String? ?? qrCode;
  }

  /// 上报 SDK 遥测数据（§3.21-3.27）到设备监控
  Future<void> reportTelemetryData(String deviceCode, SdkTelemetryData t) async {
    final data = <String, dynamic>{};
    if (t.workMode    != null) data['workMode']    = t.workMode;
    if (t.workStatus  != null) data['workStatus']  = t.workStatus;
    if (t.gsmId       != null) data['gsmId']       = t.gsmId;
    if (t.gsmVersion  != null) data['gsmVersion']  = t.gsmVersion;
    if (t.iccid       != null) data['iccid']       = t.iccid;
    if (t.domain      != null) data['domain']      = t.domain;
    if (t.ipAddress   != null) data['ipAddress']   = t.ipAddress;
    if (t.networkPort != null) data['networkPort'] = t.networkPort;
    await _dio.post('/api/devices/${deviceCode.toUpperCase()}/telemetry', data: data);
  }

  /// 查询设备最后一条进行中的订单（PAID/UNLOCKED），用于代关退款
  Future<OrderHistory?> getDeviceActiveOrder(String qrCode) async {
    final resp = await _dio.get('/api/orders/device-active', queryParameters: {'qrCode': qrCode});
    final data = resp.data as Map<String, dynamic>;
    if (data['hasActive'] == false) return null;
    return OrderHistory.fromJson(data);
  }
}

/// 自动添加 Accept-Language 头，并将后端错误 message 字段提取为 Exception
class _LangInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Accept-Language'] = ApiService._lang;
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final data = err.response?.data;
    if (data is Map && data['message'] != null) {
      handler.reject(
        err.copyWith(message: data['message'].toString()),
      );
    } else {
      handler.next(err);
    }
  }
}
