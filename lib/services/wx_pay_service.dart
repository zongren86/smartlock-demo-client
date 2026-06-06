import 'dart:async';
import 'package:fluwx/fluwx.dart';
import 'package:smartlockdemo_client/config/app_config.dart';
import 'package:smartlockdemo_client/models/borrow_order.dart';

class WxPayService {
  static final WxPayService _instance = WxPayService._internal();
  factory WxPayService() => _instance;
  WxPayService._internal();

  final Fluwx _fluwx = Fluwx();
  bool _initialized = false;

  final _payResultController = StreamController<WeChatPaymentResponse>.broadcast();

  Stream<WeChatPaymentResponse> get payResultStream => _payResultController.stream;

  Future<void> init() async {
    if (_initialized) return;
    await _fluwx.registerApi(
      appId: AppConfig.wxAppId,
      doOnAndroid: true,
      doOnIOS: true,
      universalLink: 'https://your-domain.com/app/',
    );
    _fluwx.addSubscriber((response) {
      if (response is WeChatPaymentResponse) {
        _payResultController.add(response);
      }
    });
    _initialized = true;
  }

  Future<bool> isWeChatInstalled() async {
    return await _fluwx.isWeChatInstalled;
  }

  Future<bool> launchPay(BorrowOrderModel order) async {
    await init();

    final payReq = Payment(
      appId: order.appId,
      partnerId: order.partnerId,
      prepayId: order.prepayId,
      packageValue: order.packageValue,
      nonceStr: order.nonceStr,
      timestamp: int.tryParse(order.timeStamp) ?? 0,
      sign: order.sign,
    );

    return await _fluwx.pay(which: payReq);
  }

  void dispose() {
    _payResultController.close();
  }
}
