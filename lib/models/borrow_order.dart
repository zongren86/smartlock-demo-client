class BorrowOrderModel {
  final String orderId;
  final String mac;
  final int depositAmount;
  final int usageAmount;
  final int depositExpiryMinutes;
  final bool isMock;
  final String appId;
  final String partnerId;
  final String prepayId;
  final String packageValue;
  final String nonceStr;
  final String timeStamp;
  final String sign;

  int get totalAmount => usageAmount + depositAmount;

  BorrowOrderModel({
    required this.orderId,
    required this.mac,
    required this.depositAmount,
    this.usageAmount = 0,
    this.depositExpiryMinutes = 5,
    required this.isMock,
    this.appId = '',
    this.partnerId = '',
    this.prepayId = '',
    this.packageValue = 'Sign=WXPay',
    this.nonceStr = '',
    this.timeStamp = '',
    this.sign = '',
  });

  factory BorrowOrderModel.fromJson(Map<String, dynamic> json) => BorrowOrderModel(
        orderId: json['orderId'] ?? '',
        mac: json['mac'] ?? '',
        depositAmount: json['depositAmount'] ?? 0,
        usageAmount: json['usageAmount'] ?? 0,
        depositExpiryMinutes: json['depositExpiryMinutes'] ?? 5,
        isMock: json['mock'] == true,
        appId: json['appId'] ?? '',
        partnerId: json['partnerId'] ?? '',
        prepayId: json['prepayId'] ?? '',
        packageValue: json['packageValue'] ?? 'Sign=WXPay',
        nonceStr: json['nonceStr'] ?? '',
        timeStamp: json['timeStamp'] ?? '',
        sign: json['sign'] ?? '',
      );

  /// 创建副本并修改指定字段
  BorrowOrderModel copyWith({
    int? depositAmount,
    int? usageAmount,
  }) => BorrowOrderModel(
    orderId: orderId,
    mac: mac,
    depositAmount: depositAmount ?? this.depositAmount,
    usageAmount: usageAmount ?? this.usageAmount,
    depositExpiryMinutes: depositExpiryMinutes,
    isMock: isMock,
    appId: appId,
    partnerId: partnerId,
    prepayId: prepayId,
    packageValue: packageValue,
    nonceStr: nonceStr,
    timeStamp: timeStamp,
    sign: sign,
  );
}

class OrderStatus {
  final String orderId;
  final String status;
  final String mac;
  final String? unlockToken;
  final int? usageAmount;
  final DateTime? depositExpiresAt;

  OrderStatus({
    required this.orderId,
    required this.status,
    required this.mac,
    this.unlockToken,
    this.usageAmount,
    this.depositExpiresAt,
  });

  bool get isPaid => status == 'PAID';
  bool get isUnlocked => status == 'UNLOCKED';

  factory OrderStatus.fromJson(Map<String, dynamic> json) => OrderStatus(
        orderId: json['orderId'] ?? '',
        status: json['status'] ?? 'PENDING',
        mac: json['mac'] ?? '',
        unlockToken: json['unlockToken'],
        usageAmount: json['usageAmount'],
        depositExpiresAt: json['depositExpiresAt'] != null
            ? DateTime.tryParse(json['depositExpiresAt'])?.toLocal()
            : null,
      );
}

class OrderHistory {
  final String orderId;
  final String mac;
  final String? bleMac;
  final String? customId;
  final int amount;
  final int? usageAmount;
  final int? refundAmount;
  final DateTime? depositExpiresAt;
  final String status;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? returnedAt;

  OrderHistory({
    required this.orderId,
    required this.mac,
    this.bleMac,
    this.customId,
    required this.amount,
    this.usageAmount,
    this.refundAmount,
    this.depositExpiresAt,
    required this.status,
    required this.createdAt,
    this.paidAt,
    this.returnedAt,
  });

  bool get isActive => status == 'PAID' || status == 'UNLOCKED';
  bool get isReturned => status == 'RETURNED' || status == 'REFUNDED';

  int get depositAmount => usageAmount != null ? amount - usageAmount! : amount;

  int get expectedRefund {
    if (depositExpiresAt == null) return amount;
    return DateTime.now().isBefore(depositExpiresAt!) ? depositAmount : 0;
  }

  /// Deducted = deposit portion not returned
  bool get depositDeducted {
    if (refundAmount == null) return false;
    return depositAmount - refundAmount! > 0;
  }

  String get statusLabel {
    switch (status) {
      case 'PENDING': return '待支付';
      case 'PAID': return '已支付';
      case 'UNLOCKED': return '使用中';
      case 'RETURNED': return '已归还';
      case 'REFUNDED': return '已退款';
      case 'CANCELLED': return '已取消';
      default: return status;
    }
  }

  factory OrderHistory.fromJson(Map<String, dynamic> json) => OrderHistory(
        orderId: json['orderId'] ?? '',
        mac: json['mac'] ?? '',
        bleMac: json['bleMac'],
        customId: json['customId'],
        amount: json['amount'] ?? 0,
        usageAmount: json['usageAmount'],
        refundAmount: json['refundAmount'],
        depositExpiresAt: json['depositExpiresAt'] != null
            ? DateTime.tryParse(json['depositExpiresAt'])?.toLocal()
            : null,
        status: json['status'] ?? 'PENDING',
        createdAt: (DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now()).toLocal(),
        paidAt: json['paidAt'] != null ? DateTime.tryParse(json['paidAt'])?.toLocal() : null,
        returnedAt: json['returnedAt'] != null ? DateTime.tryParse(json['returnedAt'])?.toLocal() : null,
      );
}
