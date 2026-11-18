import 'dart:async';

import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

/// Nạp tiền bằng chuyển khoản VietQR (cùng API như bản Android / trang /account/deposit).
Future<bool> showDeposit(BuildContext context) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Jp.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => FractionallySizedBox(heightFactor: 0.92, child: const _DepositSheet()),
  );
  return r == true;
}

class _DepositSheet extends StatefulWidget {
  const _DepositSheet();
  @override
  State<_DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends State<_DepositSheet> {
  Map<String, dynamic>? data;
  String? error, copied;
  bool creating = true;
  int remaining = 0;
  String status = 'pending';
  Map<String, dynamic>? success;
  Timer? _t;
  bool paid = false;

  @override
  void initState() {
    super.initState();
    _create(false);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _create(bool force) async {
    setState(() { creating = true; error = null; success = null; });
    final (c, j, _) = await Api.instance.rawPost('/api/site/deposit/bank/create', {'forceNew': force});
    if (!mounted) return;
    if (c < 200 || c >= 300 || j == null) {
      setState(() { creating = false; error = '${j?['error'] ?? 'Không tạo được mã nạp tiền (mã $c)'}'; });
      return;
    }
    setState(() {
      creating = false;
      data = j;
      status = '${j['status'] ?? 'pending'}';
      remaining = ((j['remainingSeconds'] ?? 0) as num).toInt();
    });
    _startTimer();
  }

  void _startTimer() {
    _t?.cancel();
    var tick = 0;
    _t = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted || status != 'pending' || success != null) { t.cancel(); return; }
      tick++;
      setState(() { if (remaining > 0) remaining--; });
      if (tick % 5 == 0) {
        final id = data?['depositId'];
        final (c, j, _) = await Api.instance.rawPost('/api/site/deposit/bank/check', {'depositId': id});
        if (!mounted || j == null || c < 200 || c >= 300) return;
        setState(() => status = '${j['status'] ?? status}');
        if (j['success'] == true) {
          paid = true;
          setState(() => success = j);
          t.cancel();
        }
      }
    });
  }

  Future<void> _copy(String label, String v) async {
    await Clipboard.setData(ClipboardData(text: v));
    if (!mounted) return;
    setState(() => copied = label);
    Future.delayed(const Duration(milliseconds: 1500), () { if (mounted && copied == label) setState(() => copied = null); });
  }

  Widget _row(String label, String v, {bool canCopy = false, bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: Jp.muted))),
          Flexible(child: Text(v.isEmpty ? '—' : v, style: TextStyle(fontSize: 13, fontWeight: strong ? FontWeight.w900 : FontWeight.w600, color: strong ? Jp.primary : Jp.text))),
          if (canCopy && v.isNotEmpty)
            InkWell(
              onTap: () => _copy(label, v),
              child: Padding(padding: const EdgeInsets.only(left: 8), child: JpIcon(copied == label ? JpIcons.check : JpIcons.copy, size: 16, color: copied == label ? Jp.success : Jp.primary)),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final d = data;
    final bank = (d?['bank'] as Map?)?.cast<String, dynamic>() ?? {};
    final qrUrl = '${bank['qrUrl'] ?? ''}';
    final st = status == 'pending'
        ? 'Chờ chuyển khoản · ${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}'
        : (status == 'paid' || status == 'success' || status == 'completed' ? 'Đã thanh toán' : 'Mã đã hết hạn — tạo mã mới');
    final promo = bank['promo'];
    return Stack(children: [
      Column(children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Jp.lineStrong, borderRadius: BorderRadius.circular(2))),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
            const Text('VÍ J2ME PLAY', style: TextStyle(color: Jp.primary, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            Text('Nạp tiền', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Jp.text)),
            Text('Chuyển đúng nội dung, hệ thống tự cộng số dư.', style: TextStyle(fontSize: 12, color: Jp.muted)),
            const SizedBox(height: 12),
            if (creating && d == null) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Jp.primary)))
            else if (error != null) Text(error!, style: const TextStyle(color: Jp.danger, fontSize: 13))
            else if (d != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(border: Border.all(color: Jp.line), borderRadius: BorderRadius.circular(14)),
                child: Column(children: [
                  const Text('ATM TỰ ĐỘNG · VietQR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Jp.primary, letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  Container(
                    width: 220,
                    height: 220,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Jp.line), borderRadius: BorderRadius.circular(10)),
                    child: qrUrl.isEmpty
                        ? Center(child: Text('Không tải được QR', style: TextStyle(fontSize: 12, color: Jp.muted)))
                        : Image.network(qrUrl, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Center(child: Text('Không tải được QR', style: TextStyle(fontSize: 12, color: Jp.muted)))),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(st, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: status == 'pending' ? Jp.infoBlue : Jp.danger)),
                    Text(' · ', style: TextStyle(color: Jp.muted)),
                    InkWell(onTap: creating ? null : () => _create(true), child: Text(creating ? 'Đang tạo…' : 'Làm mới', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.primary))),
                  ]),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Jp.bgFaint, borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  _row('Ngân hàng', '${bank['bankName'] ?? ''}'),
                  _row('Số tài khoản', '${bank['accountNumber'] ?? ''}', canCopy: true),
                  _row('Chủ tài khoản', '${bank['accountName'] ?? ''}'),
                  _row('Nội dung', '${d['transferCode'] ?? ''}', canCopy: true, strong: true),
                  _row('Nạp tối thiểu', money(((bank['minDeposit'] ?? 0) as num).toInt())),
                ]),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFFFF8E6), border: Border.all(color: const Color(0xFFFBE3A6)), borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Ghi chú', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF8A5A00))),
                  if (promo is Map) Padding(padding: const EdgeInsets.only(top: 4), child: Text('🎁 Khuyến mãi: ${promo['label'] ?? promo['name'] ?? 'đang áp dụng'}', style: const TextStyle(fontSize: 12, color: Jp.success, fontWeight: FontWeight.w600))),
                  if ('${bank['notice'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${bank['notice']}', style: const TextStyle(fontSize: 12, color: Color(0xFF6B4E16)))),
                  const Padding(padding: EdgeInsets.only(top: 4), child: Text('• Chuyển đúng số tài khoản và nội dung, giao dịch hợp lệ được cộng vào ví tự động.', style: TextStyle(fontSize: 12, color: Color(0xFF6B4E16)))),
                  const Padding(padding: EdgeInsets.only(top: 2), child: Text('• Mã nạp tự hủy sau 30 phút nếu chưa thanh toán.', style: TextStyle(fontSize: 12, color: Color(0xFF6B4E16)))),
                ]),
              ),
            ],
          ]),
        ),
      ]),
      if (success != null)
        Positioned.fill(
          child: Container(
            color: const Color(0x8017172F),
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.all(28),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Jp.lineStrong)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 56, height: 56, decoration: const BoxDecoration(color: Jp.success, shape: BoxShape.circle), child: const JpIcon(JpIcons.check, color: Colors.white, size: 30)),
                const SizedBox(height: 12),
                Text('Nạp tiền thành công', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Jp.text)),
                Text('+${money((((success!['totalAmount'] ?? success!['amount']) ?? 0) as num).toInt())}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Jp.success)),
                const SizedBox(height: 8),
                _row('Số dư mới', money(((success!['balance'] ?? 0) as num).toInt()), strong: true),
                const SizedBox(height: 10),
                PrimaryButton('Tiếp tục', () => Navigator.pop(context, true), height: 40, fontSize: 14),
              ]),
            ),
          ),
        ),
    ]);
  }
}
