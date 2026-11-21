import 'dart:async';

import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

String _id(Rental r) => Uri.encodeComponent(r.id);

String _err(Map<String, dynamic>? j, int c, String fb) {
  final e = j?['error'] ?? j?['message'];
  return e is String && e.isNotEmpty ? e : '$fb (mã $c)';
}

class _Choice extends StatelessWidget {
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;
  const _Choice(this.title, this.sub, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? Jp.primarySoft : Jp.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? Jp.primary : Jp.line, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            JpIcon(selected ? JpIcons.radioOn : JpIcons.radioOff, size: 20, color: selected ? Jp.primary : Jp.muted),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text)),
              Text(sub, style: TextStyle(fontSize: 12, color: Jp.muted)),
            ])),
          ]),
        ),
      );
}


/// Khung hộp thoại giống JpDialog của Android: bo 24, lề 18, tiêu đề đậm, nút Hủy + nút chính.
class _Shell extends StatelessWidget {
  final String title, confirm;
  final Widget body;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool sending, danger;
  const _Shell(this.title, this.body, this.confirm, this.onConfirm, this.onCancel, {this.sending = false, this.danger = false});
  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Jp.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: Jp.text, fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 8),
            body,
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: sending ? null : onCancel, child: Text('Hủy', style: TextStyle(color: Jp.muted))),
              const SizedBox(width: 4),
              PrimaryButton(confirm, onConfirm, loading: sending, height: 44, container: danger ? Jp.danger : Jp.primary),
            ]),
          ]),
        ),
      );
}

/// Hộp thoại chức năng của một máy: đổi tên, kích thước màn hình, proxy, khởi động lại, tắt máy.
/// Trả về thông báo thành công (hoặc null nếu huỷ).
Future<String?> showRentalAction(BuildContext context, String kind, Rental r) =>
    showDialog<String>(context: context, builder: (_) => _ActionDialog(kind, r));

class _ActionDialog extends StatefulWidget {
  final String kind;
  final Rental r;
  const _ActionDialog(this.kind, this.r);
  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  late final TextEditingController name = TextEditingController(text: widget.r.deviceName);
  final proxy = TextEditingController();
  late String screen = (widget.r.screenWidth == 400 && widget.r.screenHeight == 350) ? '400x350' : '320x480';
  // Chỉ 2 chế độ: Tắt (hệ thống tự chọn proxy / IP server) và Bật (proxy riêng của người thuê cho cả phiên).
  late bool proxyOn = widget.r.proxyManual;
  late String proxyType = widget.r.proxyType;
  bool sending = false;
  String? err;

  Future<void> send(String path, Map<String, dynamic> body, String fb) async {
    setState(() { sending = true; err = null; });
    final (c, j, _) = await Api.instance.rawPost(path, body);
    if (!mounted) return;
    if (c >= 200 && c < 300) {
      final m = '${j?['message'] ?? ''}';
      Navigator.pop(context, m.isEmpty ? fb : m);
    } else {
      setState(() { sending = false; err = _err(j, c, 'Thao tác thất bại'); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.kind, r = widget.r, id = _id(r);
    final title = {'name': 'Đổi tên máy', 'screen-size': 'Đổi kích thước', 'proxy': 'Proxy', 'restart': 'Khởi động lại?'}[k] ?? 'Tắt J2ME?';
    Widget body;
    switch (k) {
      case 'name':
        body = JpField('Tên máy', name, JpIcons.edit, placeholder: 'VD: Acc chính', maxLen: 80, onChanged: (_) => setState(() {}), action: TextInputAction.done);
        break;
      case 'screen-size':
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Máy sẽ khởi động lại với kích thước mới.', style: TextStyle(color: Jp.muted, fontSize: 13)))),
          _Choice('320 × 480', 'Màn hình dọc', screen == '320x480', () => setState(() => screen = '320x480')),
          _Choice('400 × 350', 'Màn hình ngang', screen == '400x350', () => setState(() => screen = '400x350')),
        ]);
        break;
      case 'proxy':
        final manualNow = r.proxyManual;
        final labelColor = manualNow ? Jp.success : Jp.primary;
        body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Nhãn hiện tại: Tắt · IP x (tím) / Proxy riêng · IP x (xanh).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: labelColor.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text('${manualNow ? 'Proxy riêng' : 'Tắt'}${r.proxyIp.isNotEmpty ? ' · IP ${r.proxyIp}' : ''}',
                style: TextStyle(color: labelColor, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dùng proxy riêng', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text)),
              Text('Bật: dùng proxy bạn nhập cho cả phiên thuê.', style: TextStyle(fontSize: 12, color: Jp.muted)),
            ])),
            Switch(value: proxyOn, activeColor: Jp.primary, onChanged: sending ? null : (v) => setState(() => proxyOn = v)),
          ]),
          if (proxyOn) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Row(children: [
                for (final t in const [('socks5', 'SOCKS5'), ('http', 'HTTP')]) ...[
                  Expanded(child: GestureDetector(
                    onTap: () => setState(() => proxyType = t.$1),
                    child: Container(
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: proxyType == t.$1 ? Jp.primarySoft : Jp.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: proxyType == t.$1 ? Jp.primary : Jp.line, width: proxyType == t.$1 ? 1.5 : 1),
                      ),
                      child: Text(t.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: proxyType == t.$1 ? Jp.primaryDark : Jp.muted)),
                    ),
                  )),
                  if (t.$1 == 'socks5') const SizedBox(width: 8),
                ],
              ]),
            ),
            JpField('Địa chỉ proxy', proxy, JpIcons.globe, placeholder: 'host:port[:user:pass]', keyboard: TextInputType.url, onChanged: (_) => setState(() {}), action: TextInputAction.done),
          ],
        ]);
        break;
      case 'restart':
        body = Text('${r.deviceName} sẽ khởi động lại, game đang chạy sẽ mở lại từ đầu. Thời gian thuê không thay đổi.', style: TextStyle(color: Jp.muted, fontSize: 14));
        break;
      default:
        body = Text('${r.deviceName} sẽ tắt và game đang chạy bị đóng. Thời gian thuê vẫn tiếp tục tính. Bạn có thể bật lại bất cứ lúc nào.', style: TextStyle(color: Jp.muted, fontSize: 14));
    }
    final canSave = !sending && (k != 'name' || name.text.trim().isNotEmpty) && (k != 'proxy' || !proxyOn || proxy.text.trim().isNotEmpty);
    void go() {
      switch (k) {
        case 'name': send('/api/site/rentals/$id/name', {'name': name.text.trim()}, 'Đã đổi tên máy'); break;
        case 'screen-size':
          final p = screen.split('x').map(int.parse).toList();
          send('/api/site/rentals/$id/screen-size', {'width': p[0], 'height': p[1]}, 'Đang đổi màn hình ${p[0]} × ${p[1]}…');
          break;
        case 'proxy':
          send('/api/site/rentals/$id/proxy', {'enabled': proxyOn, 'type': proxyType, 'address': proxy.text.trim()}, 'Đã lưu proxy');
          break;
        case 'restart': send('/api/site/rentals/$id/restart', {}, 'Đang khởi động lại ${r.deviceName}…'); break;
        default: send('/api/site/rentals/$id/power-off', {}, 'Đang tắt ${r.deviceName}…');
      }
    }
    return _Shell(
      title,
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        body,
        if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: MessageBanner(err!)),
      ]),
      {'power-off': 'Tắt máy', 'restart': 'Khởi động lại'}[k] ?? 'Lưu',
      canSave ? go : null,
      () => Navigator.pop(context),
      sending: sending,
      danger: k == 'power-off',
    );
  }
}

/// Gia hạn một phiên: chọn gói + số chu kỳ, xem giá (extension-preview), xác nhận (extend).
Future<String?> showExtend(BuildContext context, Rental r, List<Product> products) =>
    showDialog<String>(context: context, builder: (_) => _ExtendDialog(r, products));

class _ExtendDialog extends StatefulWidget {
  final Rental r;
  final List<Product> products;
  const _ExtendDialog(this.r, this.products);
  @override
  State<_ExtendDialog> createState() => _ExtendDialogState();
}

class _ExtendDialogState extends State<_ExtendDialog> {
  Product? sel;
  int cycles = 1;
  Map<String, dynamic>? pv;
  bool calc = false, sending = false;
  String? err;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    sel = widget.products.isNotEmpty ? widget.products.first : null;
    _preview();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _preview() {
    _t?.cancel();
    final p = sel;
    if (p == null) return;
    setState(() => calc = true);
    _t = Timer(const Duration(milliseconds: 250), () async {
      final (c, j, _) = await Api.instance.rawPost('/api/site/rentals/${_id(widget.r)}/extension-preview', {'productId': p.id, 'quantity': cycles});
      if (!mounted) return;
      setState(() {
        calc = false;
        if (c >= 200 && c < 300 && j != null) { pv = j; err = null; } else { err = _err(j, c, 'Không tính được giá gia hạn'); }
      });
    });
  }

  String _fmt(dynamic ms) {
    final v = (ms is num) ? ms.toInt() : 0;
    if (v <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(v < 100000000000 ? v * 1000 : v);
    String t(int n) => n.toString().padLeft(2, '0');
    return '${t(d.hour)}:${t(d.minute)} ${t(d.day)}/${t(d.month)}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final enough = pv?['enoughBalance'] != false;
    final days = (sel?.durationDays ?? 1) * cycles;
    return _Shell(
      'Gia hạn ${r.deviceName.isEmpty ? 'phiên' : r.deviceName}',
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hết hạn hiện tại: ${_fmt(r.endsAt)}', style: TextStyle(color: Jp.muted, fontSize: 14)),
        const SizedBox(height: 10),
        for (final p in widget.products) _Choice(p.name, '${p.durationDays} ngày · ${money(p.price)}', p.id == sel?.id, () { setState(() => sel = p); _preview(); }),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Số chu kỳ', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Jp.text)),
              Text('$days ngày', style: TextStyle(fontSize: 12, color: Jp.muted)),
            ])),
            Container(
              height: 34,
              decoration: BoxDecoration(border: Border.all(color: Jp.line), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                InkWell(onTap: cycles > 1 ? () { setState(() => cycles--); _preview(); } : null, child: SizedBox(width: 34, height: 34, child: Center(child: JpIcon(JpIcons.remove, size: 18, color: cycles > 1 ? Jp.primary : Jp.lineStrong)))),
                ConstrainedBox(constraints: const BoxConstraints(minWidth: 36), child: Text('$cycles', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text))),
                InkWell(onTap: () { setState(() => cycles++); _preview(); }, child: SizedBox(width: 34, height: 34, child: Center(child: JpIcon(JpIcons.add, size: 18, color: Jp.primary)))),
              ]),
            ),
          ]),
        ),
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Jp.bgFaint, borderRadius: BorderRadius.circular(10)),
          child: Opacity(opacity: calc && pv != null ? 0.55 : 1, child: Column(children: [
            _row('Thành tiền', pv == null ? '—' : money(((pv!['amount'] ?? 0) as num).toInt()), bold: true),
            _row('Số dư sau', pv == null ? '—' : money(((pv!['balanceAfter'] ?? 0) as num).toInt()), color: enough ? Jp.muted : Jp.danger),
            _row('Hạn mới', pv == null ? '—' : _fmt(pv!['targetEndsAt'])),
          ])),
        ),
        if (err != null || !enough) Padding(padding: const EdgeInsets.only(top: 6), child: Text(err ?? 'Số dư không đủ để gia hạn.', style: const TextStyle(color: Jp.danger, fontSize: 13))),
      ]),
      'Gia hạn',
      (calc || err != null || !enough || pv == null || sending || sel == null)
          ? null
          : () async {
              setState(() => sending = true);
              final (c, j, _) = await Api.instance.rawPost('/api/site/rentals/${_id(r)}/extend', {'productId': sel!.id, 'quantity': cycles});
              if (!mounted) return;
              if (c >= 200 && c < 300) {
                final m = '${j?['message'] ?? ''}';
                Navigator.pop(context, m.isEmpty ? 'Đã gia hạn ${r.deviceName}.' : m);
              } else {
                setState(() { sending = false; err = _err(j, c, 'Gia hạn thất bại'); });
              }
            },
      () => Navigator.pop(context),
      sending: sending,
    );
  }

  Widget _row(String l, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(l, style: TextStyle(color: Jp.muted, fontSize: 14))),
          Text(v, style: TextStyle(color: color ?? Jp.text, fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.w700 : FontWeight.w600)),
        ]),
      );
}
