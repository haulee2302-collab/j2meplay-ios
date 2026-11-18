import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'connection.dart';

/// Giao diện Native cho màn hình dạng MIDP của game (bản Dart của MidpUi.kt): TextBox, Form, List.
/// Gửi lại máy chủ bằng giao thức văn bản đặc biệt của web:  = TextBox,  = Form,  = List.
const _ed = '', _fm = '', _ls = '';

class MidpCommand {
  final int index, type, priority, order;
  final String label;
  MidpCommand(this.index, this.label, this.type, this.priority, this.order);
}

List<MidpCommand> _commandsOf(dynamic arr) {
  if (arr is! List) return [];
  final out = <MidpCommand>[];
  for (var i = 0; i < arr.length; i++) {
    final c = arr[i];
    if (c is! Map || !c.containsKey('index')) continue;
    var label = '${c['label'] ?? ''}';
    if (label.isEmpty) label = '${c['name'] ?? ''}';
    if (label.isEmpty) label = 'OK';
    out.add(MidpCommand((c['index'] as num).toInt(), label, ((c['type'] ?? 0) as num).toInt(), ((c['priority'] ?? 0) as num).toInt(), i));
  }
  out.sort((a, b) => a.priority != b.priority ? a.priority.compareTo(b.priority) : a.order.compareTo(b.order));
  return out;
}

bool _isPrimary(int type) => type == 1 || type == 4 || type == 8;

MidpCommand? _primaryOf(List<MidpCommand> cmds) {
  for (final c in cmds) {
    if (_isPrimary(c.type)) return c;
  }
  return null;
}

/// (loại, id) nếu runtime đang ở TextBox/Form/List; null nếu không.
(String, int)? runtimeNativeKind(Map<String, dynamic>? rt) {
  if (rt == null) return null;
  if (rt['browserEditor'] is Map) return ('editor', ((rt['browserEditor'] as Map)['id'] ?? 0) as int);
  if (rt['browserForm'] is Map) return ('form', ((rt['browserForm'] as Map)['id'] ?? 0) as int);
  if (rt['browserList'] is Map) return ('list', ((rt['browserList'] as Map)['id'] ?? 0) as int);
  return null;
}

TextInputType _keyboardFor(int constraints) {
  switch (constraints & 0xffff) {
    case 1: return TextInputType.emailAddress;
    case 2: return TextInputType.number;
    case 3: return TextInputType.phone;
    case 4: return TextInputType.url;
    case 5: return const TextInputType.numberWithOptions(decimal: true);
    default: return TextInputType.text;
  }
}

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : (int.tryParse('$v') ?? d);

class MidpOverlay extends StatefulWidget {
  final Map<String, dynamic> runtime;
  final GameConnection conn;
  final void Function(String) onError;
  const MidpOverlay({super.key, required this.runtime, required this.conn, required this.onError});
  @override
  State<MidpOverlay> createState() => _MidpOverlayState();
}

class _MidpOverlayState extends State<MidpOverlay> {
  bool busy = false;

  Future<void> act(Future<bool> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    bool ok;
    try { ok = await f(); } catch (_) { ok = false; }
    if (!ok) widget.onError('Không gửi được thao tác tới máy J2ME. Thử lại.');
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final rt = widget.runtime;
    final editor = rt['browserEditor'] as Map<String, dynamic>?;
    final form = rt['browserForm'] as Map<String, dynamic>?;
    final list = rt['browserList'] as Map<String, dynamic>?;
    final src = editor ?? form ?? list;
    var title = '${src?['title'] ?? ''}';
    if (title.isEmpty) title = editor != null ? 'Nhập nội dung' : (form != null ? 'Cài đặt' : 'Lựa chọn');
    return Material(
      color: Jp.surface,
      child: Column(children: [
        Container(
          width: double.infinity,
          color: Jp.primarySoft,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Jp.text))),
            if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Jp.primary)),
          ]),
        ),
        Expanded(
          child: editor != null
              ? _EditorView(editor, busy, widget.conn, act)
              : form != null
                  ? _FormView(form, busy, widget.conn, act)
                  : _ListView(list ?? {}, busy, widget.conn, act),
        ),
      ]),
    );
  }
}

typedef _Act = Future<void> Function(Future<bool> Function());

class _SoftKeys extends StatelessWidget {
  final MidpCommand? left, right;
  final List<MidpCommand> menu;
  final bool busy;
  final void Function(MidpCommand) onCommand;
  const _SoftKeys({required this.left, required this.right, required this.menu, required this.busy, required this.onCommand});

  @override
  Widget build(BuildContext context) {
    Widget leftW = const SizedBox();
    if (menu.isNotEmpty) {
      leftW = PopupMenuButton<MidpCommand>(
        enabled: !busy,
        onSelected: onCommand,
        itemBuilder: (_) => [for (final c in menu) PopupMenuItem(value: c, child: Text(c.label))],
        child: _box('Menu'),
      );
    } else if (left != null) {
      leftW = InkWell(onTap: busy ? null : () => onCommand(left!), child: _box(left!.label));
    }
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Jp.line))),
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        Expanded(child: leftW),
        const SizedBox(width: 10),
        Expanded(
          child: right == null
              ? const SizedBox()
              : InkWell(onTap: busy ? null : () => onCommand(right!), child: _box(right!.label, primary: true)),
        ),
      ]),
    );
  }

  Widget _box(String label, {bool primary = false}) => Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? Jp.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: primary ? null : Border.all(color: Jp.lineStrong),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: primary ? Colors.white : Jp.text)),
      );
}

InputDecoration _dec() => InputDecoration(
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Jp.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Jp.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Jp.primary)),
    );

// ---------------- TextBox ----------------
class _EditorView extends StatefulWidget {
  final Map<String, dynamic> editor;
  final bool busy;
  final GameConnection conn;
  final _Act act;
  const _EditorView(this.editor, this.busy, this.conn, this.act);
  @override
  State<_EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<_EditorView> {
  late TextEditingController c;
  late int maxSize, constraints;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    constraints = _int(widget.editor['constraints']);
    maxSize = _int(widget.editor['maxSize'], 256).clamp(1, 4096);
    var v = '${widget.editor['value'] ?? ''}';
    if (v.length > maxSize) v = v.substring(0, maxSize);
    c = TextEditingController(text: v);
  }

  @override
  void didUpdateWidget(covariant _EditorView old) {
    super.didUpdateWidget(old);
    if (_int(old.editor['id']) != _int(widget.editor['id'])) {
      c.dispose();
      _init();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final password = constraints & 0x10000 != 0;
    final e = widget.editor;
    final cancel = '${e['cancelLabel'] ?? ''}'.isEmpty ? 'Hủy' : '${e['cancelLabel']}';
    final ok = '${e['okLabel'] ?? ''}'.isEmpty ? 'OK' : '${e['okLabel']}';
    return Column(children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            TextField(
              controller: c,
              autofocus: true,
              obscureText: password,
              maxLines: password ? 1 : 6,
              minLines: password ? 1 : 4,
              maxLength: maxSize,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => Text('$currentLength/$maxLength', style: TextStyle(fontSize: 11, color: Jp.muted)),
              keyboardType: password ? TextInputType.visiblePassword : _keyboardFor(constraints),
              decoration: _dec(),
            ),
          ]),
        ),
      ),
      _SoftKeys(
        left: MidpCommand(-1, cancel, 2, 0, 0),
        right: MidpCommand(0, ok, 1, 0, 1),
        menu: const [],
        busy: widget.busy,
        onCommand: (cmd) {
          final conn = widget.conn;
          if (cmd.index < 0) {
            widget.act(() => conn.keyTap('BACK'));
          } else {
            final value = c.text;
            widget.act(() async {
              var ok = await conn.text('${_ed}C');
              var off = 0;
              while (ok && off < value.length) {
                ok = await conn.text('${_ed}A${value.substring(off, (off + 254).clamp(0, value.length))}');
                off += 254;
              }
              return ok && await conn.keyTap('OK');
            });
          }
        },
      ),
    ]);
  }
}

// ---------------- Form ----------------
class _FormView extends StatefulWidget {
  final Map<String, dynamic> form;
  final bool busy;
  final GameConnection conn;
  final _Act act;
  const _FormView(this.form, this.busy, this.conn, this.act);
  @override
  State<_FormView> createState() => _FormViewState();
}

class _FormViewState extends State<_FormView> {
  final Map<int, TextEditingController> texts = {};
  final Map<int, List<bool>> choices = {};
  final Map<int, int> gauges = {};
  String sig = '';

  List get items => (widget.form['items'] as List?) ?? const [];

  String _signature() => '${widget.form['id']}|${jsonEncode(items)}';

  @override
  void initState() {
    super.initState();
    sig = _signature();
  }

  @override
  void didUpdateWidget(covariant _FormView old) {
    super.didUpdateWidget(old);
    final s = _signature();
    if (s != sig) {
      sig = s;
      for (final t in texts.values) { t.dispose(); }
      texts.clear();
      choices.clear();
      gauges.clear();
    }
  }

  @override
  void dispose() {
    for (final t in texts.values) { t.dispose(); }
    super.dispose();
  }

  List<bool> _sel(Map item, int idx) {
    final opts = (item['options'] as List?) ?? const [];
    final sel = item['selected'] as List?;
    return choices[idx] ?? List<bool>.generate(opts.length, (k) => sel != null && k < sel.length && sel[k] == true);
  }

  Future<bool> _push() async {
    final conn = widget.conn;
    for (final raw in items) {
      if (raw is! Map) continue;
      final idx = _int(raw['index']);
      switch ('${raw['type']}') {
        case 'text':
          final v = texts[idx]?.text ?? '${raw['value'] ?? ''}';
          if (!await conn.text('${_fm}C$idx')) return false;
          var off = 0;
          while (off < v.length) {
            if (!await conn.text('${_fm}A$idx:${v.substring(off, (off + 220).clamp(0, v.length))}')) return false;
            off += 220;
          }
          break;
        case 'choice':
          if (!await conn.text('${_fm}S$idx:${_sel(raw, idx).map((b) => b ? '1' : '0').join()}')) return false;
          break;
        case 'gauge':
          if (raw['interactive'] == true) {
            final v = gauges[idx] ?? _int(raw['value']);
            if (!await conn.text('${_fm}G$idx:$v')) return false;
          }
          break;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final item = raw;
      final idx = _int(item['index']);
      final label = '${item['label'] ?? ''}';
      final body = <Widget>[];
      if (label.isNotEmpty) {
        body.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Jp.primaryDark))));
      }
      switch ('${item['type']}') {
        case 'text':
          final cons = _int(item['constraints']);
          final max = _int(item['maxSize'], 256).clamp(1, 4096);
          final ctl = texts.putIfAbsent(idx, () {
            var v = '${item['value'] ?? ''}';
            if (v.length > max) v = v.substring(0, max);
            return TextEditingController(text: v);
          });
          body.add(TextField(
            controller: ctl,
            obscureText: cons & 0x10000 != 0,
            keyboardType: cons & 0x10000 != 0 ? TextInputType.visiblePassword : _keyboardFor(cons),
            inputFormatters: [_MaxLen(max)],
            decoration: _dec(),
          ));
          break;
        case 'choice':
          final opts = (item['options'] as List?) ?? const [];
          final multiple = _int(item['choiceType']) == 2;
          final sel = _sel(item, idx);
          for (var o = 0; o < opts.length; o++) {
            final on = o < sel.length && sel[o];
            body.add(InkWell(
              onTap: widget.busy
                  ? null
                  : () {
                      final next = multiple ? [for (var k = 0; k < sel.length; k++) k == o ? !sel[k] : sel[k]] : List<bool>.generate(opts.length, (k) => k == o);
                      setState(() => choices[idx] = next);
                      widget.conn.text('${_fm}S$idx:${next.map((b) => b ? '1' : '0').join()}');
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Icon(multiple ? (on ? Icons.check_box : Icons.check_box_outline_blank) : (on ? Icons.radio_button_checked : Icons.radio_button_unchecked), color: on ? Jp.primary : Jp.muted, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${opts[o]}', style: TextStyle(fontSize: 14, color: Jp.text))),
                ]),
              ),
            ));
          }
          break;
        case 'gauge':
          final max = _int(item['maxValue'], 1).clamp(1, 1 << 30);
          final v = (gauges[idx] ?? _int(item['value'])).clamp(0, max);
          body.add(Row(children: [
            Expanded(
              child: item['interactive'] == true
                  ? Slider(value: v.toDouble(), min: 0, max: max.toDouble(), divisions: max <= 100 ? max : null, activeColor: Jp.primary, onChanged: (d) => setState(() => gauges[idx] = d.round()))
                  : LinearProgressIndicator(value: v / max, color: Jp.primary, backgroundColor: Jp.line),
            ),
            const SizedBox(width: 10),
            Text('$v', style: TextStyle(fontSize: 13, color: Jp.muted)),
          ]));
          break;
        case 'string':
          body.add(Text('${item['value'] ?? ''}', style: TextStyle(fontSize: 14, color: Jp.text)));
          break;
        default:
          body.add(Text('${item['className'] ?? ''}'.isEmpty ? 'Mục MIDP chưa hỗ trợ' : '${item['className']}', style: TextStyle(fontSize: 13, color: Jp.muted)));
      }
      children.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body)));
    }

    final cmds = _commandsOf(widget.form['commands']);
    final primary = _primaryOf(cmds);
    final secondary = cmds.where((c) => c != primary).toList();
    return Column(children: [
      Expanded(child: ListView(padding: const EdgeInsets.all(14), children: children)),
      _SoftKeys(
        left: secondary.length == 1 ? secondary[0] : null,
        right: primary ?? (cmds.isEmpty ? MidpCommand(-1, 'Đóng', 2, 0, 0) : null),
        menu: secondary.length > 1 ? secondary : const [],
        busy: widget.busy,
        onCommand: (cmd) => widget.act(() async => await _push() && (cmd.index < 0 ? await widget.conn.keyTap('BACK') : await widget.conn.text('${_fm}K${cmd.index}'))),
      ),
    ]);
  }
}

class _MaxLen extends TextInputFormatter {
  final int max;
  _MaxLen(this.max);
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) => n.text.length <= max ? n : o;
}

// ---------------- List ----------------
class _ListView extends StatefulWidget {
  final Map<String, dynamic> list;
  final bool busy;
  final GameConnection conn;
  final _Act act;
  const _ListView(this.list, this.busy, this.conn, this.act);
  @override
  State<_ListView> createState() => _ListViewState();
}

class _ListViewState extends State<_ListView> {
  late List<bool> selected;
  String sig = '';

  List get options => (widget.list['options'] as List?) ?? const [];
  int get choiceType => _int(widget.list['choiceType'], 3);

  List<bool> _initial() {
    final implicit = choiceType == 3;
    return [
      for (final o in options)
        implicit
            ? (_int(widget.list['selectedIndex'], -1) >= 0 ? (o is Map && _int(o['index']) == _int(widget.list['selectedIndex'])) : (o is Map && o['selected'] == true))
            : (o is Map && o['selected'] == true)
    ];
  }

  @override
  void initState() {
    super.initState();
    sig = '${widget.list['id']}|${options.length}';
    selected = _initial();
  }

  @override
  void didUpdateWidget(covariant _ListView old) {
    super.didUpdateWidget(old);
    final s = '${widget.list['id']}|${options.length}';
    if (s != sig) {
      sig = s;
      selected = _initial();
    }
  }

  Uint8List? _icon(String? url) {
    if (url == null || !url.startsWith('data:image') || !url.contains('base64,')) return null;
    try { return base64Decode(url.substring(url.indexOf('base64,') + 7)); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final implicit = choiceType == 3, multiple = choiceType == 2;
    final cmds = _commandsOf(widget.list['commands']);
    final primary = _primaryOf(cmds);
    final secondary = cmds.where((c) => c != primary).toList();
    return Column(children: [
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (_, i) {
            final o = (options[i] is Map ? options[i] : <String, dynamic>{}) as Map;
            final index = o.containsKey('index') ? _int(o['index']) : i;
            final sel = i < selected.length && selected[i];
            final icon = _icon('${o['icon'] ?? ''}');
            Widget lead;
            if (!implicit) {
              lead = Icon(multiple ? (sel ? Icons.check_box : Icons.check_box_outline_blank) : (sel ? Icons.radio_button_checked : Icons.radio_button_unchecked), color: sel ? Jp.primary : Jp.muted, size: 22);
            } else if (icon != null) {
              lead = Image.memory(icon, width: 28, height: 28, filterQuality: FilterQuality.none);
            } else {
              lead = Container(width: 26, height: 26, alignment: Alignment.center, decoration: BoxDecoration(color: Jp.bgFaint, borderRadius: BorderRadius.circular(6)), child: Text('${index + 1}', style: TextStyle(fontSize: 12, color: Jp.muted, fontWeight: FontWeight.w600)));
            }
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.busy
                  ? null
                  : () {
                      if (implicit) {
                        setState(() => selected = List<bool>.generate(options.length, (k) => k == i));
                        widget.act(() => widget.conn.text('${_ls}A$index'));
                      } else {
                        setState(() => selected = multiple ? [for (var k = 0; k < selected.length; k++) k == i ? !selected[k] : selected[k]] : List<bool>.generate(options.length, (k) => k == i));
                      }
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: sel ? Jp.primarySoft : Jp.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: sel ? Jp.primary : Jp.line)),
                child: Row(children: [lead, const SizedBox(width: 10), Expanded(child: Text('${o['label'] ?? ''}', style: TextStyle(fontSize: 15, color: Jp.text)))]),
              ),
            );
          },
        ),
      ),
      if (cmds.isNotEmpty)
        _SoftKeys(
          left: secondary.length == 1 ? secondary[0] : null,
          right: primary,
          menu: secondary.length > 1 ? secondary : const [],
          busy: widget.busy,
          onCommand: (cmd) => widget.act(() async {
            final pushed = implicit || await widget.conn.text('${_ls}S:${selected.map((b) => b ? '1' : '0').join()}');
            return pushed && await widget.conn.text('${_ls}K${cmd.index}');
          }),
        ),
    ]);
  }
}
