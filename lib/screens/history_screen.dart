import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartlockdemo_client/l10n/strings.dart';
import 'package:smartlockdemo_client/main.dart';
import 'package:smartlockdemo_client/models/borrow_order.dart';
import 'package:smartlockdemo_client/services/api_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiService _api = ApiService();
  List<OrderHistory> _orders = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = context.read<AppState>().userId;
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _api.getUserHistory(userId);
      if (mounted) setState(() { _orders = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(S.of(context).historyTitle),
        backgroundColor: const Color(0xFF1A73E8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _load, child: Text(S.of(context).retry)),
                  ],
                ))
              : _orders.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.history, size: 64, color: Color(0xFFCCCCCC)),
                          const SizedBox(height: 12),
                          Text(S.of(context).noHistory,
                              style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 16)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _orders.length,
                        itemBuilder: (_, i) => _buildCard(_orders[i]),
                      ),
                    ),
    );
  }

  Widget _buildCard(OrderHistory order) {
    final statusColor = _statusColor(order.status);
    final deducted = order.depositDeducted;
    final yuan = (int fen) => S.of(context).currency(fen);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Line 1: order ID + status (+ 扣押金 badge if applicable)
          Row(
            children: [
              Expanded(
                child: Text(order.orderId,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                    overflow: TextOverflow.ellipsis),
              ),
              if (deducted)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(S.of(context).depositDeducted,
                      style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(S.of(context).statusLabel(order.status),
                  style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Line 2: MAC | customId
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 14, color: Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Expanded(child: Text(S.of(context).deviceShortId(order.mac.length > 4 ? order.mac.substring(order.mac.length - 4) : order.mac), style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
              if (order.customId != null)
                Text(order.customId!, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
            ],
          ),
          const SizedBox(height: 4),
          // Line 3: payment time | payment amount
          Row(
            children: [
              const Icon(Icons.payment, size: 14, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  order.paidAt != null ? _formatDate(order.paidAt!) : _formatDate(order.createdAt),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                ),
              ),
              Text(yuan(order.amount),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
            ],
          ),
          // Line 4: refund time | refund amount (only if returned/refunded)
          if (order.isReturned) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.undo, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    order.returnedAt != null ? _formatDate(order.returnedAt!) : '-',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF10B981)),
                  ),
                ),
                Text(
                  order.refundAmount != null ? yuan(order.refundAmount!) : yuan(order.expectedRefund),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF10B981)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.receipt_outlined, size: 14, color: Color(0xFF6B7280)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(S.of(context).actualPaid,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                ),
                Text(
                  yuan(order.amount - (order.refundAmount ?? 0)),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'PENDING': return Colors.orange;
      case 'PAID': return const Color(0xFF1A73E8);
      case 'UNLOCKED': return const Color(0xFF1A73E8);
      case 'RETURNED': return const Color(0xFF10B981);
      case 'REFUNDED': return const Color(0xFF10B981);
      case 'CANCELLED': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
