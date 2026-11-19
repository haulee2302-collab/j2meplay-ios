import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../emu/game_screen.dart';
import '../emu/net.dart';
import '../emu/session.dart';
import '../emu/store.dart';
import '../icons.dart';
import '../theme.dart';
import 'floating.dart';
import 'sync_local.dart';
import '../widgets.dart';

/// Tab "Giả lập": giống bản Android — giả lập J2ME chạy ngay trên máy từ JAR trong Kho JAR thiết bị.
class EmulatorScreen extends StatefulWidget {
  final VoidCallback? onOpenRentals, onOpenJars;
  const EmulatorScreen({super.key, this.onOpenRentals, this.onOpenJars});
  @override
  State<EmulatorScreen> createState() => _EmulatorScreenState();
}

class _EmulatorScreenState extends State<EmulatorScreen> {
  List<LocalInstance> list = [];
  bool loaded = false;
  String? notice;
  Timer? _nt;

  @override
  void initState() {
    super.initState();
    _load();
    EmuRuntime.changed.addListener(_tick);
  }

  @override
  void dispose() {
    EmuRuntime.changed.removeListener(_tick);
    _nt?.cancel();
    super.dispose();
  }

  void _tick() { if (mounted) setState(() {}); }

  Future<void> _load() async {
    final l = await EmuStore.listInstances();
    if (mounted) setState(() { list = l; loaded = true; });
  }

  void _persist(List<LocalInstance> l) {
    setState(() => list = l);
    EmuStore.saveInstances(l);
  }

  void _notice(String m) {
    _nt?.cancel();
    setState(() => notice = m);
    _nt = Timer(const Duration(milliseconds: 3500), () { if (mounted) setState(() => notice = null); });
  }

  Future<void> _open(LocalInstance inst) async {
    final jars = await EmuStore.listJars();
    if (!jars.any((j) => j.id == inst.jarId)) {
      _notice('Chưa chọn file JAR. Hãy mở Kho JAR để chọn game.');
      return;
    }
    if (!EmuRuntime.sessions.containsKey(inst.id)) {
      _persist(list.map((e) => e.id == inst.id ? e.copy(lastPlayed: DateTime.now().millisecondsSinceEpoch) : e).toList());
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LocalGameScreen(inst: inst, onConfig: () => _config(inst))));
    if (mounted) setState(() {});
  }

  Future<LocalInstance?> _config(LocalInstance? inst) async {
    final r = await showModalBottomSheet<LocalInstance>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Jp.surface,
      builder: (_) => _ConfigSheet(initial: inst),
    );
    if (r == null || !mounted) return null;
    if (inst != null && inst.jarId != r.jarId) {
      // Đổi JAR: ảnh chụp màn hình cũ không còn đúng game
      try {
        final f = await EmuStore.shot(r.id);
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }
    if (EmuRuntime.sessions.containsKey(r.id)) {
      EmuRuntime.close(r.id); // cấu hình đổi (JAR/kích thước...) → chạy lại bằng cấu hình mới
      LocalFloats.close(r.id);
    }
    _persist(list.any((e) => e.id == r.id) ? list.map((e) => e.id == r.id ? r : e).toList() : [...list, r]);
    _notice(inst != null ? 'Đã lưu cấu hình ${r.name}' : 'Đã tạo ${r.name}');
    return r;
  }

  Future<void> _jarStore() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Jp.bgFaint,
      builder: (_) => _JarStoreSheet(instances: list, onChanged: _notice),
    );
  }

  Future<void> _menu(LocalInstance inst) async {
    final v = await showDialog<String>(
      context: context,
      builder: (c) {
        Widget entry(String key, String label, JpIconData icon, {bool danger = false}) => InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => Navigator.pop(c, key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
                child: Row(children: [
                  JpIcon(icon, size: 18, color: danger ? Jp.danger : Jp.primary),
                  const SizedBox(width: 12),
                  Text(label, style: TextStyle(fontSize: 14, color: danger ? Jp.danger : Jp.text)),
                ]),
              ),
            );
        return AlertDialog(
          backgroundColor: Jp.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inst.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
            Text('${inst.jarName} · ${inst.width}×${inst.height}', style: TextStyle(fontSize: 12, color: Jp.muted)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            entry('open', 'Mở giả lập', JpIcons.play),
            entry('config', 'Cấu hình (kích thước, JAR…)', JpIcons.tune),
            entry('proxy', inst.proxy != null ? 'Proxy (${inst.proxy!.label})' : 'Proxy', JpIcons.globe),
            entry('delete', 'Xóa giả lập', JpIcons.trash, danger: true),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text('Đóng', style: TextStyle(color: Jp.muted)))],
        );
      },
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'open':
        _open(inst);
        break;
      case 'config':
        _config(inst);
        break;
      case 'proxy':
        final r = await showDialog<_ProxyResult>(context: context, builder: (_) => _ProxyDialog(name: inst.name, current: inst.proxy));
        if (r == null || !mounted) return;
        _persist(list.map((e) => e.id == inst.id ? e.copy(proxy: r.proxy, clearProxy: r.proxy == null) : e).toList());
        _notice((r.proxy == null ? 'Đã xóa proxy của ${inst.name}' : 'Đã lưu proxy ${r.proxy!.label}') + (EmuRuntime.sessions.containsKey(inst.id) ? ' · áp dụng khi chạy lại game' : ''));
        break;
      case 'delete':
        final ok = await confirmDialog(context, 'Xóa giả lập?', 'Xóa "${inst.name}" cùng dữ liệu lưu game trên máy. Không thể hoàn tác.', ok: 'Xóa', danger: true);
        if (!ok || !mounted) return;
        EmuRuntime.close(inst.id);
        EmuStore.deleteInstance(inst.id);
        _persist(list.where((e) => e.id != inst.id).toList());
        _notice('Đã xóa ${inst.name}');
        break;
    }
  }

  final Set<String> checked = {};

  void _viewSync(List<String> ids) => Navigator.push(context, MaterialPageRoute(builder: (_) => LocalSyncScreen(ids: ids)));

  @override
  Widget build(BuildContext context) {
    final hiddenRunning = [for (final i in list) if (EmuRuntime.modeOf(i.id) == 'hidden') i];
    checked.removeWhere((id) => !hiddenRunning.any((i) => i.id == id));
    final picked = [for (final i in hiddenRunning) if (checked.contains(i.id)) i.id];
    final running = list.where((e) => EmuRuntime.sessions.containsKey(e.id)).length;
    final extent = (MediaQuery.of(context).size.width - 34) / 2 * 3 / 4 + 104;
    return Stack(children: [
      ListView(padding: EdgeInsets.zero, children: [
        HeroHeader(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42, alignment: Alignment.center, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const JpIcon(JpIcons.gamepad, size: 22, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Chạy trên máy', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                const Text('Giả lập J2ME', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ])),
              const ThemeToggle(),
            ]),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Giả lập', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13)),
                  Text('${list.length}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900)),
                  Text(running > 0 ? '$running đang chạy' : 'Chạy JAR trên máy', style: const TextStyle(color: Jp.highlight, fontSize: 12, fontWeight: FontWeight.w600)),
                ])),
                OutlineButton2('Kho JAR', _jarStore, icon: JpIcons.toolJar, height: 40, color: Colors.white),
                const SizedBox(width: 6),
                PrimaryButton('Tạo giả lập', () => _config(null), icon: JpIcons.add, container: Colors.white, content: Jp.primary, height: 40, fontSize: 12),
              ]),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            Text('Giả lập trên máy của bạn', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3), decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(99)), child: Text('${list.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.primary))),
          ]),
        ),
        if (hiddenRunning.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton(
                    onPressed: picked.isEmpty ? null : () => _viewSync(picked),
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10), side: BorderSide(color: Jp.lineStrong), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                    child: Text('Xem đã chọn (${picked.length})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Jp.primary)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: PrimaryButton('Xem tất cả (${hiddenRunning.length})', () => _viewSync([for (final i in hiddenRunning) i.id]), icon: JpIcons.toolExpand, height: 36, fontSize: 12)),
            ]),
          ),
        const SizedBox(height: 10),
        if (!loaded)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Jp.primary)))
        else if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
              decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Jp.line)),
              child: Column(children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(12)), child: const Center(child: JpIcon(JpIcons.gamepad, size: 24, color: Jp.primary))),
                const SizedBox(height: 10),
                Text('Chưa có giả lập nào', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text)),
                const SizedBox(height: 2),
                Text('Tạo giả lập, chọn file JAR trên máy và chơi ngay — không cần thuê phiên.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Jp.muted)),
                const SizedBox(height: 14),
                PrimaryButton('Tạo giả lập', () => _config(null), icon: JpIcons.add, height: 36, fontSize: 13),
              ]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, mainAxisExtent: extent),
              itemBuilder: (c, i) => _InstanceCard(list[i], onOpen: () => _open(list[i]), onMenu: () => _menu(list[i]), checked: checked.contains(list[i].id), onCheck: (v) => setState(() { if (v) { checked.add(list[i].id); } else { checked.remove(list[i].id); } })),
            ),
          ),
        const SizedBox(height: 28),
      ]),
      if (notice != null)
        Positioned(
          top: topInset(context) + 8, right: 10, left: 40,
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF14365D), borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)]),
              child: Text(notice!, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ),
        ),
    ]);
  }
}

class _InstanceCard extends StatefulWidget {
  final LocalInstance inst;
  final VoidCallback onOpen, onMenu;
  final bool checked;
  final void Function(bool) onCheck;
  const _InstanceCard(this.inst, {required this.onOpen, required this.onMenu, this.checked = false, required this.onCheck});
  @override
  State<_InstanceCard> createState() => _InstanceCardState();
}

class _InstanceCardState extends State<_InstanceCard> {
  File? icon;
  Uint8List? shot;

  @override
  void initState() {
    super.initState();
    _files();
    EmuRuntime.changed.addListener(_files);
  }

  @override
  void dispose() {
    EmuRuntime.changed.removeListener(_files);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _InstanceCard old) {
    super.didUpdateWidget(old);
    if (old.inst.jarId != widget.inst.jarId) {
      shot = null;
      imageCache.clear();
      imageCache.clearLiveImages();
      _files();
    }
  }

  Future<void> _files() async {
    final i = widget.inst;
    final s = await EmuStore.shot(i.id);
    final ic = i.jarId.isEmpty ? null : await EmuStore.iconFile(i.jarId);
    Uint8List? bytes;
    try { bytes = s.existsSync() ? await s.readAsBytes() : null; } catch (_) {}
    if (mounted) setState(() { shot = bytes; icon = (ic != null && ic.existsSync()) ? ic : null; });
  }

  @override
  Widget build(BuildContext context) {
    final inst = widget.inst;
    final mode = EmuRuntime.modeOf(inst.id);
    final status = mode == 'hidden' ? 'Chạy ẩn' : (mode == 'foreground' ? 'Đang chạy' : 'Đã dừng');
    Widget badge(String t, {double fs = 10}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(5)),
          child: Text(t, maxLines: 1, style: TextStyle(color: Colors.white, fontSize: fs, fontWeight: FontWeight.w600)),
        );
    return Container(
      decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Jp.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: Jp.gameBg),
            if (shot != null)
              Image.memory(shot!, fit: BoxFit.cover, filterQuality: FilterQuality.none, gaplessPlayback: true)
            else if (icon != null)
              Center(child: Image.file(icon!, width: 56, height: 56, filterQuality: FilterQuality.none))
            else
              Center(child: JpIcon(JpIcons.toolJar, size: 36, color: Colors.white.withOpacity(0.6))),
            if (shot != null && icon != null)
              Positioned(left: 6, bottom: 6, child: Container(width: 28, height: 28, padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(6)), child: Image.file(icon!, filterQuality: FilterQuality.none))),
            Positioned(left: 6, top: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatusPill(status, mode.isNotEmpty ? Jp.success : Jp.muted, white: true),
              if (inst.proxy != null) Padding(padding: const EdgeInsets.only(top: 3), child: badge(inst.proxy!.label, fs: 9)),
            ])),
            if (mode == 'hidden')
              Positioned(
                right: 8, top: 8,
                child: GestureDetector(
                  onTap: () => widget.onCheck(!widget.checked),
                  child: Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(color: widget.checked ? Jp.primary : Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(4), border: Border.all(color: widget.checked ? Jp.primary : Jp.muted)),
                    child: widget.checked ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                  ),
                ),
              ),
            Positioned(right: 6, bottom: 6, child: badge('${inst.width}×${inst.height}')),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inst.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Jp.text)),
            Padding(padding: const EdgeInsets.only(top: 2, bottom: 8), child: Text(inst.jarName.isEmpty ? 'Chưa chọn JAR' : inst.jarName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Jp.muted))),
            Row(children: [
              Expanded(child: PrimaryButton(mode.isEmpty ? 'Khởi chạy' : 'Xem', widget.onOpen, height: 30, fontSize: 12)),
              const SizedBox(width: 6),
              SizedBox(
                width: 30, height: 30,
                child: OutlinedButton(
                  onPressed: widget.onMenu,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, side: BorderSide(color: Jp.lineStrong), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  child: const JpIcon(JpIcons.more, size: 16, color: Jp.primary),
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

Widget _chip(String text, bool on, VoidCallback f, {bool fill = false}) => GestureDetector(
      onTap: f,
      child: Container(
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: fill ? 2 : 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: on ? Jp.primary : Jp.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? Jp.primary : Jp.lineStrong)),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: fill ? 11 : 12, fontWeight: FontWeight.w600, color: on ? Colors.white : Jp.primary)),
      ),
    );

/// Hộp tạo / sửa giả lập: tên, JAR trong kho thiết bị, kích thước màn hình, hình/giây, âm thanh.
class _ConfigSheet extends StatefulWidget {
  final LocalInstance? initial;
  const _ConfigSheet({this.initial});
  @override
  State<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<_ConfigSheet> {
  late final TextEditingController name, w, h, proxyText;
  String proxyType = '';
  bool proxyBusy = false;
  String? proxyMsg;

  Future<void> _testProxy() async {
    final px = LocalProxy.parse(proxyText.text, proxyType);
    if (px == null) {
      setState(() => proxyMsg = 'Proxy sai định dạng. Dùng ip:port hoặc ip:port:user:pass');
      return;
    }
    setState(() { proxyBusy = true; proxyMsg = null; });
    String r;
    try { r = await testProxy(px); } catch (e) { r = 'Lỗi: $e'; }
    if (mounted) setState(() { proxyBusy = false; proxyMsg = r; });
  }
  String jarId = '', jarName = '';
  int fps = 30;
  bool sound = true;
  String? error;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    name = TextEditingController(text: i?.name ?? '');
    w = TextEditingController(text: '${i?.width ?? 350}');
    h = TextEditingController(text: '${i?.height ?? 400}');
    jarId = i?.jarId ?? '';
    jarName = i?.jarName ?? '';
    fps = i?.fps ?? 30;
    sound = i?.sound ?? true;
    proxyText = TextEditingController(text: LocalProxy.format(i?.proxy));
    proxyType = i?.proxy?.type ?? '';
  }

  Future<void> _pickJar() async {
    final r = await showModalBottomSheet<DeviceJar>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Jp.bgFaint,
      builder: (_) => _JarStoreSheet(instances: const [], selectedId: jarId, selecting: true, onChanged: (_) {}),
    );
    if (r == null) return;
    setState(() {
      jarId = r.id;
      jarName = r.name;
      error = null;
      if (name.text.trim().isEmpty) name.text = r.name.replaceFirst(RegExp(r'\.[^.]*$'), '');
    });
  }

  Future<void> _save() async {
    final ww = int.tryParse(w.text) ?? 0, hh = int.tryParse(h.text) ?? 0;
    final jars = await EmuStore.listJars();
    String? e;
    if (name.text.trim().isEmpty) {
      e = 'Nhập tên giả lập';
    } else if (!jars.any((j) => j.id == jarId && j.compiled)) {
      e = 'Chọn JAR hợp lệ trong kho thiết bị hoặc tải file mới';
    } else if (ww < 96 || ww > 1080 || hh < 96 || hh > 1920) {
      e = 'Kích thước từ 96×96 đến 1080×1920';
    }
    LocalProxy? px;
    if (e == null && proxyType != '' && proxyText.text.trim().isNotEmpty) {
      px = LocalProxy.parse(proxyText.text, proxyType);
      if (px == null) e = 'Proxy sai định dạng. Dùng ip:port hoặc ip:port:user:pass';
    }
    if (e != null) {
      setState(() => error = e);
      return;
    }
    final i = widget.initial;
    if (!mounted) return;
    Navigator.pop(context, LocalInstance(i?.id ?? newId(), name.text.trim(), jarName, ww, hh, fps, sound, i?.joystick ?? true, i?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        lastPlayed: i?.lastPlayed ?? 0, jarId: jarId, proxy: px));
  }

  Widget _label(String t) => Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Jp.muted)));

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.initial == null ? 'Tạo giả lập' : 'Cấu hình giả lập', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
                const SizedBox(height: 10),
                TextField(controller: name, maxLength: 40, decoration: _dec('Tên giả lập').copyWith(counterText: '')),
                _label('JAR trong kho thiết bị'),
                InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: _pickJar,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(border: Border.all(color: Jp.lineStrong), borderRadius: BorderRadius.circular(9)),
                    child: Row(children: [
                      const JpIcon(JpIcons.toolJar, size: 17, color: Jp.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(jarName.isEmpty ? 'Chọn JAR từ kho thiết bị' : jarName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: jarName.isEmpty ? Jp.muted : Jp.text))),
                      Text('›', style: TextStyle(color: Jp.muted, fontSize: 20)),
                    ]),
                  ),
                ),
                _label('Kích thước màn hình'),
                Row(children: [
                  Expanded(child: TextField(controller: w, keyboardType: TextInputType.number, maxLength: 4, decoration: _dec('Rộng').copyWith(counterText: ''))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('×', style: TextStyle(color: Jp.muted))),
                  Expanded(child: TextField(controller: h, keyboardType: TextInputType.number, maxLength: 4, decoration: _dec('Cao').copyWith(counterText: ''))),
                ]),
                _label('Giới hạn hình / giây'),
                Row(children: [
                  for (final f in [15, 30, 60, 0]) ...[
                    if (f != 15) const SizedBox(width: 6),
                    Expanded(child: _chip(f == 0 ? 'Không giới hạn' : '$f', fps == f, () => setState(() => fps = f), fill: true)),
                  ],
                ]),
                _label('Proxy'),
                Row(children: [
                  Expanded(child: _chip('Không', proxyType == '', () => setState(() => proxyType = ''), fill: true)),
                  const SizedBox(width: 6),
                  Expanded(child: _chip('HTTP', proxyType == 'http', () => setState(() => proxyType = 'http'), fill: true)),
                  const SizedBox(width: 6),
                  Expanded(child: _chip('SOCKS5', proxyType == 'socks5', () => setState(() => proxyType = 'socks5'), fill: true)),
                ]),
                if (proxyType != '') ...[
                  const SizedBox(height: 8),
                  TextField(controller: proxyText, maxLength: 250, decoration: _dec('ip:port hoặc ip:port:user:pass').copyWith(counterText: '')),
                  const SizedBox(height: 6),
                  Row(children: [
                    SizedBox(
                      height: 30,
                      child: OutlinedButton(
                        onPressed: proxyBusy ? null : _testProxy,
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), side: BorderSide(color: Jp.lineStrong), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text(proxyBusy ? 'Đang kiểm tra...' : 'Kiểm tra proxy', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Jp.primary)),
                      ),
                    ),
                  ]),
                  if (proxyMsg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(proxyMsg!, style: TextStyle(fontSize: 12, color: proxyMsg!.startsWith('Proxy hoạt động') ? Jp.success : Jp.danger))),
                  if (proxyType == 'socks5') Padding(padding: const EdgeInsets.only(top: 6), child: Text('SOCKS5 áp dụng cho kết nối socket của game. Yêu cầu HTTP của game chỉ đi qua proxy kiểu HTTP.', style: TextStyle(fontSize: 11, color: Jp.muted))),
                ],
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => setState(() => sound = !sound),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Âm thanh', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Jp.text)),
                      Text('Phát nhạc và hiệu ứng của game', style: TextStyle(fontSize: 11, color: Jp.muted)),
                    ])),
                    Switch(value: sound, onChanged: (v) => setState(() => sound = v), activeColor: Colors.white, activeTrackColor: Jp.primary),
                  ]),
                ),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(color: Jp.danger, fontSize: 12))),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + MediaQuery.of(context).padding.bottom),
            child: Row(children: [
              Expanded(child: OutlineButton2('Hủy', () => Navigator.pop(context), height: 40)),
              const SizedBox(width: 10),
              Expanded(child: PrimaryButton(widget.initial == null ? 'Tạo giả lập' : 'Lưu', _save, height: 40, fontSize: 13)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Kho JAR riêng của thiết bị: thêm JAR, kiểm tra hợp lệ, xóa; hoặc chọn một JAR cho giả lập.
class _JarStoreSheet extends StatefulWidget {
  final List<LocalInstance> instances;
  final String selectedId;
  final bool selecting;
  final void Function(String) onChanged;
  const _JarStoreSheet({required this.instances, this.selectedId = '', this.selecting = false, required this.onChanged});
  @override
  State<_JarStoreSheet> createState() => _JarStoreSheetState();
}

class _JarStoreSheetState extends State<_JarStoreSheet> {
  List<DeviceJar> jars = [];
  String? busy, error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await EmuStore.listJars();
    if (mounted) setState(() => jars = l);
  }

  Future<void> _add() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    if (!f.name.toLowerCase().endsWith('.jar')) {
      setState(() => error = 'Chỉ chọn tệp có đuôi .JAR');
      return;
    }
    setState(() { busy = 'Đang thêm ${f.name}…'; error = null; });
    final item = await EmuStore.importJar(f.name, f.bytes!);
    await _load();
    if (!mounted) return;
    setState(() {
      busy = null;
      if (!item.compiled) error = item.error.isEmpty ? 'Biên dịch thất bại' : item.error;
    });
    if (item.compiled) widget.onChanged('Đã thêm và biên dịch ${item.name}');
  }

  Future<void> _delete(DeviceJar j) async {
    final used = widget.instances.where((e) => e.jarId == j.id).length;
    final ok = await confirmDialog(context, 'Xóa JAR khỏi thiết bị?', 'Xóa file "${j.name}" khỏi kho.${used > 0 ? ' Có $used giả lập đang dùng JAR này và sẽ cần chọn JAR khác.' : ''}', ok: 'Xóa', danger: true);
    if (!ok) return;
    await EmuStore.deleteJar(j.id);
    await _load();
    widget.onChanged('Đã xóa ${j.name} khỏi kho thiết bị');
  }

  String _size(int b) => b >= 1048576 ? '${(b / 1048576).toStringAsFixed(2)} MB' : (b >= 1024 ? '${(b / 1024).toStringAsFixed(1)} KB' : '$b B');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Container(width: 38, height: 38, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(10)), child: const Center(child: JpIcon(JpIcons.toolJar, size: 20, color: Jp.primary))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.selecting ? 'Chọn JAR' : 'Kho JAR thiết bị', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
              Text('JAR được dùng chung cho các giả lập', style: TextStyle(fontSize: 11, color: Jp.muted)),
            ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(width: double.infinity, child: PrimaryButton(busy ?? 'Thêm file JAR', busy == null ? _add : null, loading: busy != null, icon: JpIcons.navUpload, height: 40, fontSize: 13)),
        ),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text(error!, style: const TextStyle(color: Jp.danger, fontSize: 12))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text('JAR đã thêm', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Jp.text)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(99)), child: Text('${jars.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.primary))),
          ]),
        ),
        Expanded(
          child: jars.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Jp.line)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      JpIcon(JpIcons.toolJar, size: 34, color: Jp.muted),
                      const SizedBox(height: 10),
                      Text('Kho JAR thiết bị đang trống', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text)),
                      const SizedBox(height: 3),
                      Text('Nhấn Thêm file JAR để chọn từ thư mục trên máy', style: TextStyle(fontSize: 12, color: Jp.muted)),
                    ]),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: jars.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final j = jars[i];
                    final used = widget.instances.where((e) => e.jarId == j.id).length;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: widget.selecting && j.compiled ? () => Navigator.pop(context, j) : null,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Jp.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: j.id == widget.selectedId ? Jp.primary : Jp.line)),
                        child: Row(children: [
                          _JarIcon(j.id),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Jp.text)),
                            Text('${_size(j.size)} · ${j.compiled ? 'Thành công' : (j.error.isNotEmpty ? 'Lỗi biên dịch' : 'Đang chờ biên dịch')}', style: TextStyle(fontSize: 11, color: j.error.isNotEmpty ? Jp.danger : Jp.muted)),
                            if (used > 0) Text('Đang dùng cho $used giả lập', style: const TextStyle(fontSize: 10, color: Jp.primary)),
                          ])),
                          if (widget.selecting)
                            JpIcon(j.id == widget.selectedId ? JpIcons.check : JpIcons.chevronRight, size: 19, color: j.id == widget.selectedId ? Jp.success : Jp.primary)
                          else
                            IconButton(onPressed: busy == null ? () => _delete(j) : null, icon: const JpIcon(JpIcons.trash, size: 19, color: Jp.danger)),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _JarIcon extends StatefulWidget {
  final String id;
  const _JarIcon(this.id);
  @override
  State<_JarIcon> createState() => _JarIconState();
}

class _JarIconState extends State<_JarIcon> {
  File? f;
  @override
  void initState() {
    super.initState();
    EmuStore.iconFile(widget.id).then((x) { if (mounted && x.existsSync()) setState(() => f = x); });
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 42, height: 42,
        decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(9)),
        child: Center(child: f != null ? Image.file(f!, width: 34, height: 34, filterQuality: FilterQuality.none) : const JpIcon(JpIcons.toolJar, size: 21, color: Jp.primary)),
      );
}

class _ProxyResult {
  final LocalProxy? proxy;
  _ProxyResult(this.proxy);
}

class _ProxyDialog extends StatefulWidget {
  final String name;
  final LocalProxy? current;
  const _ProxyDialog({required this.name, this.current});
  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final TextEditingController text = TextEditingController(text: LocalProxy.format(widget.current));
  late String type = widget.current?.type ?? 'http';
  String? error, result;
  bool testing = false;

  Future<void> _test() async {
    final p = LocalProxy.parse(text.text, type);
    if (p == null) {
      setState(() => error = 'Sai định dạng. Dùng ip:port hoặc ip:port:user:pass');
      return;
    }
    setState(() { testing = true; result = null; });
    String r;
    try { r = await testProxy(p); } catch (e) { r = 'Lỗi: $e'; }
    if (mounted) setState(() { testing = false; result = r; });
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.current;
    return AlertDialog(
      backgroundColor: Jp.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Proxy · ${widget.name}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Jp.text)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: cur != null ? Jp.success : Jp.muted, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(cur != null ? 'Đang dùng ${cur.label} (${cur.type == 'socks5' ? 'SOCKS5' : 'HTTP'})' : 'Chưa dùng proxy', style: TextStyle(fontSize: 13, color: Jp.text))),
        ]),
        const SizedBox(height: 8),
        Row(children: [_chip('HTTP', type == 'http', () => setState(() => type = 'http')), const SizedBox(width: 6), _chip('SOCKS5', type == 'socks5', () => setState(() => type = 'socks5'))]),
        const SizedBox(height: 8),
        TextField(
          controller: text,
          maxLength: 250,
          onChanged: (_) => setState(() => error = null),
          decoration: InputDecoration(labelText: 'ip:port:user:pass hoặc ip:port', isDense: true, counterText: '', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
        ),
        const SizedBox(height: 6),
        Text('Để trống rồi Lưu để tắt proxy. Đổi proxy sẽ chạy lại game đang mở.', style: TextStyle(fontSize: 11, color: Jp.muted)),
        const SizedBox(height: 6),
        SizedBox(
          height: 32,
          child: OutlinedButton(
            onPressed: testing ? null : _test,
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), side: BorderSide(color: Jp.lineStrong), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: Text(testing ? 'Đang kiểm tra…' : 'Kiểm tra', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Jp.primary)),
          ),
        ),
        if (result != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(result!, style: TextStyle(fontSize: 12, color: result!.startsWith('Proxy hoạt động') ? Jp.success : Jp.danger))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(fontSize: 12, color: Jp.danger))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Đóng', style: TextStyle(color: Jp.muted))),
        TextButton(
          onPressed: () {
            if (text.text.trim().isEmpty) {
              Navigator.pop(context, _ProxyResult(null));
              return;
            }
            final p = LocalProxy.parse(text.text, type);
            if (p == null) {
              setState(() => error = 'Sai định dạng. Dùng ip:port hoặc ip:port:user:pass');
            } else {
              Navigator.pop(context, _ProxyResult(p));
            }
          },
          child: const Text('Lưu', style: TextStyle(color: Jp.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
