import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../icons.dart';
import '../theme.dart';

/// Giao diện List / Form / TextBox / Alert của lõi C: lõi gửi mô tả JSON, widget này vẽ và gửi thao tác về qua [act]:
/// K<lệnh> · L<mục> · M<bits> · E<chữ> · T<mục>:<chữ> · S<mục>:<bits> · G<mục>:<giá trị> · D.
class CoreScreenView extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(String) act;
  const CoreScreenView({super.key, required this.data, required this.act});
  @override
  State<CoreScreenView> createState() => _CoreScreenViewState();
}

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : (int.tryParse('$v') ?? d);

class _Cmd {
  final int index, type, priority;
  final String label;
  _Cmd(this.index, this.label, this.type, this.priority);
}

List<_Cmd> _cmds(dynamic raw) {
  final out = <_Cmd>[];
  if (raw is List) {
    for (final c in raw) {
      if (c is! Map) continue;
      var l = '${c['label'] ?? ''}';
      if (l.isEmpty) l = 'OK';
      out.add(_Cmd(_int(c['index']), l, _int(c['type']), _int(c['priority'])));
    }
  }
  out.sort((a, b) => a.priority != b.priority ? a.priority.compareTo(b.priority) : a.index.compareTo(b.index));
  return out;
}

TextInputType _kb(int cons) {
  switch (cons & 0xffff) {
    case 1: return TextInputType.emailAddress;
    case 2: return TextInputType.number;
    case 3: return TextInputType.phone;
    case 4: return TextInputType.url;
    case 5: return const TextInputType.numberWithOptions(decimal: true);
    default: return TextInputType.text;
  }
}

class _CoreScreenViewState extends State<CoreScreenView> {
  String sig = '';
  final Map<int, TextEditingController> texts = {};
  final Map<int, List<bool>> sels = {};
  final Map<int, int> gauges = {};
  TextEditingController? editor;
  List<bool> listSel = [];

  Map<String, dynamic> get d => widget.data;
  List get options => (d['options'] as List?) ?? const [];
  List get items => (d['items'] as List?) ?? const [];

  String _sig() {
    final k = '${d['kind']}', id = d['id'];
    if (k == 'list') return '$id|${options.map((o) => (o as Map)['label']).join('\u0001')}';
    if (k == 'form') return '$id|${jsonEncode(items.map((i) => i is Map ? {...i, 'value': null, 'selected': null} : i).toList())}';
    return '$id|${d['value']}|${d['text']}';
  }

  void _reset() {
    sig = _sig();
    for (final t in texts.values) { t.dispose(); }
    texts.clear();
    sels.clear();
    gauges.clear();
    editor?.dispose();
    editor = null;
    listSel = [for (final o in options) o is Map && o['selected'] == true];
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant CoreScreenView old) {
    super.didUpdateWidget(old);
    if (_sig() != sig) _reset();
  }

  @override
  void dispose() {
    for (final t in texts.values) { t.dispose(); }
    editor?.dispose();
    super.dispose();
  }

  String _bits(List<bool> b) => b.map((x) => x ? '1' : '0').join();

  @override
  Widget build(BuildContext context) {
    final kind = '${d['kind']}';
    var title = '${d['title'] ?? ''}';
    final cmds = _cmds(d['commands']);
    Widget body;
    switch (kind) {
      case 'list': body = _list(); break;
      case 'form': body = _form(); break;
      case 'editor': body = _editor(); break;
      default: body = _alert();
    }
    if (title.isEmpty && kind == 'alert') title = 'Thông báo';
    return Material(
      color: Jp.surface,
      child: Column(children: [
        if (title.isNotEmpty)
          Container(
            width: double.infinity,
            color: Jp.primarySoft,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text)),
          ),
        Expanded(child: body),
        _bar(kind, cmds),
      ]),
    );
  }

  Widget _bar(String kind, List<_Cmd> cmds) {
    if (cmds.isEmpty) {
      if (kind == 'alert') return _barRow([_btn('OK', true, () => widget.act('D'))]);
      return const SizedBox.shrink();
    }
    final primary = cmds.firstWhere((c) => c.type == 1 || c.type == 4 || c.type == 8, orElse: () => cmds.first);
    final others = cmds.where((c) => c != primary).toList();
    if (others.length <= 2) {
      return _barRow([
        for (final c in others) _btn(c.label, false, () => widget.act('K${c.index}')),
        _btn(primary.label, true, () => widget.act('K${primary.index}')),
      ]);
    }
    return _barRow([
      PopupMenuButton<int>(
        onSelected: (i) => widget.act('K$i'),
        itemBuilder: (_) => [for (final c in others) PopupMenuItem(value: c.index, child: Text(c.label))],
        child: _boxLabel('Menu', false),
      ),
      _btn(primary.label, true, () => widget.act('K${primary.index}')),
    ]);
  }

  Widget _barRow(List<Widget> c) => Container(
        color: Jp.bgFaint,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [for (var i = 0; i < c.length; i++) ...[if (i > 0) const SizedBox(width: 8), c[i]]]),
      );

  Widget _boxLabel(String t, bool primary) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: primary ? Jp.primary : Jp.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: primary ? Jp.primary : Jp.lineStrong)),
        child: Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: primary ? Colors.white : Jp.primary)),
      );

  Widget _btn(String t, bool primary, VoidCallback f) => InkWell(borderRadius: BorderRadius.circular(8), onTap: f, child: _boxLabel(t, primary));

  InputDecoration _dec() => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Jp.line)),
      );

  // ---- List ----
  Widget _list() {
    final type = _int(d['choiceType'], 3);
    final implicit = type == 3, multiple = type == 2;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: options.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final o = options[i] as Map;
        final on = i < listSel.length && listSel[i];
        Widget lead = implicit
            ? Container(width: 26, height: 26, alignment: Alignment.center, decoration: BoxDecoration(color: Jp.bgFaint, borderRadius: BorderRadius.circular(6)), child: Text('${i + 1}', style: TextStyle(fontSize: 12, color: Jp.muted)))
            : JpIcon(multiple ? (on ? JpIcons.boxOn : JpIcons.boxOff) : (on ? JpIcons.radioOn : JpIcons.radioOff), color: on ? Jp.primary : Jp.muted, size: 22);
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (implicit) {
              setState(() => listSel = [for (var k = 0; k < listSel.length; k++) k == i]);
              widget.act('L$i');
            } else {
              setState(() => listSel = multiple ? [for (var k = 0; k < listSel.length; k++) k == i ? !listSel[k] : listSel[k]] : [for (var k = 0; k < listSel.length; k++) k == i]);
              widget.act('M${_bits(listSel)}');
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(color: on ? Jp.primarySoft : Jp.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? Jp.primary : Jp.line)),
            child: Row(children: [lead, const SizedBox(width: 10), Expanded(child: Text('${o['label'] ?? ''}', style: TextStyle(fontSize: 14, color: Jp.text)))]),
          ),
        );
      },
    );
  }

  // ---- TextBox ----
  Widget _editor() {
    final cons = _int(d['constraints']);
    final max = _int(d['maxSize'], 256).clamp(1, 8192);
    editor ??= TextEditingController(text: '${d['value'] ?? ''}');
    final pw = cons & 0x10000 != 0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: editor,
        autofocus: true,
        obscureText: pw,
        maxLines: pw ? 1 : 8,
        minLines: pw ? 1 : 4,
        inputFormatters: [LengthLimitingTextInputFormatter(max)],
        keyboardType: pw ? TextInputType.visiblePassword : _kb(cons),
        onChanged: (v) => widget.act('E$v'),
        decoration: _dec(),
      ),
    );
  }

  // ---- Form ----
  Widget _form() {
    final children = <Widget>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final idx = _int(raw['index']);
      final label = '${raw['label'] ?? ''}';
      final body = <Widget>[];
      if (label.isNotEmpty) body.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Jp.primaryDark))));
      switch ('${raw['type']}') {
        case 'text':
          final cons = _int(raw['constraints']);
          final max = _int(raw['maxSize'], 256).clamp(1, 8192);
          final ctl = texts.putIfAbsent(idx, () => TextEditingController(text: '${raw['value'] ?? ''}'));
          body.add(TextField(
            controller: ctl,
            obscureText: cons & 0x10000 != 0,
            keyboardType: cons & 0x10000 != 0 ? TextInputType.visiblePassword : _kb(cons),
            inputFormatters: [LengthLimitingTextInputFormatter(max)],
            onChanged: (v) => widget.act('T$idx:$v'),
            decoration: _dec(),
          ));
          break;
        case 'choice':
          final opts = (raw['options'] as List?) ?? const [];
          final multiple = _int(raw['choiceType']) == 2;
          final sel = sels.putIfAbsent(idx, () => [for (final o in opts) o is Map && o['selected'] == true]);
          for (var o = 0; o < opts.length; o++) {
            final on = o < sel.length && sel[o];
            body.add(InkWell(
              onTap: () {
                setState(() => sels[idx] = multiple ? [for (var k = 0; k < sel.length; k++) k == o ? !sel[k] : sel[k]] : [for (var k = 0; k < sel.length; k++) k == o]);
                widget.act('S$idx:${_bits(sels[idx]!)}');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  JpIcon(multiple ? (on ? JpIcons.boxOn : JpIcons.boxOff) : (on ? JpIcons.radioOn : JpIcons.radioOff), color: on ? Jp.primary : Jp.muted, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${(opts[o] as Map)['label'] ?? ''}', style: TextStyle(fontSize: 14, color: Jp.text))),
                ]),
              ),
            ));
          }
          break;
        case 'gauge':
          final max = _int(raw['maxValue'], 1).clamp(1, 1 << 30);
          final v = (gauges[idx] ?? _int(raw['value'])).clamp(0, max);
          body.add(Row(children: [
            Expanded(
              child: raw['interactive'] == true
                  ? Slider(value: v.toDouble(), min: 0, max: max.toDouble(), divisions: max <= 100 ? max : null, activeColor: Jp.primary, onChanged: (x) => setState(() => gauges[idx] = x.round()), onChangeEnd: (x) => widget.act('G$idx:${x.round()}'))
                  : LinearProgressIndicator(value: v / max, color: Jp.primary, backgroundColor: Jp.line),
            ),
            const SizedBox(width: 10),
            Text('$v', style: TextStyle(fontSize: 13, color: Jp.muted)),
          ]));
          break;
        case 'string':
          body.add(Text('${raw['value'] ?? ''}', style: TextStyle(fontSize: 14, color: Jp.text)));
          break;
        default:
          continue;
      }
      children.add(Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: body)));
    }
    return ListView(padding: const EdgeInsets.all(14), children: children);
  }

  // ---- Alert ----
  Widget _alert() => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('${d['text'] ?? ''}', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Jp.text)),
        ),
      );
}
