import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../jvm/midp.dart';
import '../jvm/vm.dart';
import '../theme.dart';

/// Hiển thị màn hình MIDP không phải Canvas: TextBox, Form, List, Alert, kèm các nút lệnh.
class MidpScreenView extends StatefulWidget {
  final Midp midp;
  const MidpScreenView({super.key, required this.midp});
  @override
  State<MidpScreenView> createState() => _MidpScreenViewState();
}

class _MidpScreenViewState extends State<MidpScreenView> {
  Midp get m => widget.midp;
  JObject get o => m.screen!;
  String str(dynamic x) => x == null ? '' : ((x as JObject).native as String? ?? '');
  String? _key;
  final Map<Object, TextEditingController> _ctl = {};

  TextEditingController _c(JObject owner) => _ctl.putIfAbsent(owner, () => TextEditingController(text: str(owner.f['\$text'])));

  Widget _field(JObject owner, {int lines = 1}) {
    final cons = (owner.f['\$cons'] ?? 0) as int;
    final max = (owner.f['\$max'] ?? 0) as int;
    final kind = cons & 0xFFFF;
    return TextField(
      controller: _c(owner),
      maxLength: max > 0 ? max : null,
      maxLines: lines,
      obscureText: (cons & 0x10000) != 0,
      keyboardType: kind == 2 || kind == 3 ? TextInputType.number : (kind == 1 ? TextInputType.emailAddress : (kind == 4 ? TextInputType.url : TextInputType.text)),
      inputFormatters: kind == 2 ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))] : null,
      decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), counterText: ''),
      onChanged: (v) => owner.f['\$text'] = m.vm.str(v),
    );
  }

  Widget _body() {
    final name = o.cls.name.split('/').last;
    switch (name) {
      case 'TextBox':
        return Padding(padding: const EdgeInsets.all(14), child: _field(o, lines: 6));
      case 'Alert':
        return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text(str(o.f['\$text']), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Jp.text))));
      case 'List':
        final els = (o.f['\$els'] as List?) ?? const [];
        final type = (o.f['\$ltype'] ?? 3) as int;
        return ListView.separated(
          itemCount: els.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Jp.line),
          itemBuilder: (_, i) => ListTile(
            dense: true,
            title: Text(str(els[i]), style: TextStyle(fontSize: 14, color: Jp.text)),
            trailing: type == 3 ? null : Icon(((o.f['\$sel'] ?? 0) == i) ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: Jp.primary),
            onTap: () { m.selectListItem(i); setState(() {}); },
          ),
        );
      default:
        final items = (o.f['\$items'] as List?) ?? const [];
        return ListView(padding: const EdgeInsets.all(12), children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _item(it as JObject),
            ),
        ]);
    }
  }

  Widget _item(JObject it) {
    final n = it.cls.name.split('/').last;
    final label = str(it.f['\$label']);
    final head = label.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.text)));
    if (n == 'TextField') return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, _field(it)]);
    if (n == 'ChoiceGroup') {
      final els = (it.f['\$els'] as List?) ?? const [];
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        head,
        for (var i = 0; i < els.length; i++)
          InkWell(
            onTap: () => setState(() => it.f['\$sel'] = i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon((it.f['\$sel'] ?? 0) == i ? Icons.radio_button_checked : Icons.radio_button_off, size: 18, color: Jp.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(str(els[i]), style: TextStyle(fontSize: 13, color: Jp.text))),
              ]),
            ),
          ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, Text(str(it.f['\$text']), style: TextStyle(fontSize: 13, color: Jp.text))]);
  }

  @override
  Widget build(BuildContext context) {
    if (m.screen == null) return const SizedBox.shrink();
    final k = '${identityHashCode(o)}';
    if (_key != k) {
      _key = k;
      for (final c in _ctl.values) {
        c.dispose();
      }
      _ctl.clear();
    }
    final cmds = [for (final c in ((o.f['\$cmds'] as List?) ?? const [])) c as JObject];
    cmds.sort((a, b) => ((a.f['\$p'] ?? 0) as int).compareTo((b.f['\$p'] ?? 0) as int));
    final isAlert = o.cls.name.endsWith('Alert');
    return Material(
      color: Jp.surface,
      child: Column(children: [
        Container(
          width: double.infinity,
          color: Jp.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(str(o.f['\$title']).isEmpty ? 'Game' : str(o.f['\$title']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        Expanded(child: _body()),
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Jp.line))),
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            if (cmds.isEmpty && isAlert) Expanded(child: FilledButton(onPressed: m.dismissAlert, child: const Text('OK'))),
            for (final c in cmds)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 6)),
                    onPressed: () => m.fireCommand(c),
                    child: Text(str(c.f['\$l']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }
}
