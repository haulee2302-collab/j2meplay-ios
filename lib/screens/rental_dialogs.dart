import 'dart:async';

import 'package:flutter/material.dart';

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
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: selected ? Jp.primary : Jp.muted),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text)),
              Text(sub, style: TextStyle(fontSize: 12, color: Jp.muted)),
            ])),
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
  String proxyMode = 'free', proxyType = 'socks5';
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
        body = TextField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Tên máy', hintText: 'VD: Acc chính'));
        break;
      case 'screen-size':
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('Máy sẽ khởi động lại với kích thước mới.', style: TextStyle(color: Jp.muted, fontSize: 13)))),
          _Choice('320 × 480', 'Màn hình dọc', screen == '320x480', () => setState(() => screen = '320x480')),
          _Choice('400 × 350', 'Màn hình ngang', screen == '400x350', () => setState(() => screen = '400x350')),
        ]);
        break;
      case 'proxy':
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          _Choice('Proxy miễn phí', 'Dùng proxy có sẵn của hệ thống', proxyMode == 'free', () => setState(() => proxyMode = 'free')),
          _Choice('Proxy riêng', 'Nhập proxy SOCKS5 / HTTP của bạn', proxyMode == 'custom', () => setState(() => proxyMode = 'custom')),
          _Choice('Tắt proxy', 'Dùng IP của máy chủ', proxyMode == 'off', () => setState(() => proxyMode = 'off')),
          if (proxyMode == 'custom') ...[
            Row(children: [
              for (final t in const [('socks5', 'SOCKS5'), ('http', 'HTTP')])
                Expanded(child: Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 8),
                  child: ChoiceChip(label: Center(child: Text(t.$2)), selected: proxyType == t.$1, onSelected: (_) => setState(() => proxyType = t.$1)),
                )),
            ]),
            TextField(controller: proxy, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Địa chỉ proxy', hintText: 'host:port[:user:pass]')),
          ],
        ]);
        break;
      case 'restart':
        body = Text('${r.deviceName} sẽ khởi động lại, game đang chạy sẽ mở lại từ đầu. Thời gian thuê không thay đổi.', style: TextStyle(color: Jp.muted, fontSize: 14));
        break;
      default:
        body = Text('${r.deviceName} sẽ tắt và game đang chạy bị đóng. Thời gian thuê vẫn tiếp tục tính. Bạn có thể bật lại bất cứ lúc nào.', style: TextStyle(color: Jp.muted, fontSize: 14));
    }
    final canSave = !sending && (k != 'name' || name.text.trim().isNotEmpty) && (k != 'proxy' || proxyMode != 'custom' || proxy.text.trim().isNotEmpty);
    return AlertDialog(
      backgroundColor: Jp.surface,
      title: Text(title, style: TextStyle(color: Jp.text, fontWeight: FontWeight.w700, fontSize: 18)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        body,
        if (err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(err!, style: const TextStyle(color: Jp.danger, fontSize: 13))),
      ])),
      actions: [
        TextButton(onPressed: sending ? null : () => Navigator.pop(context), child: Text('Hủy', style: TextStyle(color: Jp.muted))),
        TextButton(
          onPressed: !canSave
              ? null
              : () {
                  switch (k) {
                    case 'name': send('/api/site/rentals/$id/name', {'name': name.text.trim()}, 'Đã đổi tên máy'); break;
                    case 'screen-size':
                      final p = screen.split('x').map(int.parse).toList();
                      send('/api/site/rentals/$id/screen-size', {'width': p[0], 'height': p[1]}, 'Đang đổi màn hình ${p[0]} × ${p[1]}…');
                      break;
                    case 'proxy':
                      send('/api/site/rentals/$id/proxy', {'enabled': proxyMode != 'off', 'free': proxyMode == 'free', 'type': proxyType, 'address': proxy.text.trim()}, 'Đã lưu proxy');
                      break;
                    case 'restart': send('/api/site/rentals/$id/restart', {}, 'Đang khởi động lại ${r.deviceName}…'); break;
                    default: send('/api/site/rentals/$id/power-off', {}, 'Đang tắt ${r.deviceName}…');
                  }
                },
          child: sending
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text({'power-off': 'Tắt máy', 'restart': 'Khởi động lại'}[k] ?? 'Lưu', style: TextStyle(color: k == 'power-off' ? Jp.danger : Jp.primary, fontWeight: FontWeight.w600)),
        ),
      ],
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
    return AlertDialog(
      backgroundColor: Jp.surface,
      title: Text('Gia hạn ${r.deviceName}', style: TextStyle(color: Jp.text, fontWeight: FontWeight.w700, fontSize: 18)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hết hạn hiện tại: ${_fmt(r.endsAt)}', style: TextStyle(color: Jp.muted, fontSize: 13)),
        const SizedBox(height: 10),
        for (final p in widget.products) _Choice(p.name, '${p.durationDays} ngày · ${money(p.price)}', p.id == sel?.id, () { setState(() => sel = p); _preview(); }),
        Row(children: [
          Expanded(child: Text('Số chu kỳ ($days ngày)', style: TextStyle(color: Jp.muted, fontSize: 14))),
          IconButton(onPressed: cycles > 1 ? () { setState(() => cycles--); _preview(); } : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$cycles', style: TextStyle(fontWeight: FontWeight.w700, color: Jp.text)),
          IconButton(onPressed: () { setState(() => cycles++); _preview(); }, icon: const Icon(Icons.add_circle_outline)),
        ]),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Jp.bgFaint, borderRadius: BorderRadius.circular(10)),
          child: Opacity(opacity: calc && pv != null ? 0.55 : 1, child: Column(children: [
            _row('Thành tiền', pv == null ? '—' : money(((pv!['amount'] ?? 0) as num).toInt()), bold: true),
            _row('Số dư sau', pv == null ? '—' : money(((pv!['balanceAfter'] ?? 0) as num).toInt()), color: enough ? Jp.muted : Jp.danger),
            _row('Hạn mới', pv == null ? '—' : _fmt(pv!['targetEndsAt'])),
          ])),
        ),
        if (err != null || !enough) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err ?? 'Số dư không đủ để gia hạn.', style: const TextStyle(color: Jp.danger, fontSize: 13))),
      ])),
      actions: [
        TextButton(onPressed: sending ? null : () => Navigator.pop(context), child: Text('Hủy', style: TextStyle(color: Jp.muted))),
        TextButton(
          onPressed: (calc || err != null || !enough || pv == null || sending || sel == null)
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
          child: const Text('Gia hạn', style: TextStyle(color: Jp.primary, fontWeight: FontWeight.w600)),
        ),
      ],
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
