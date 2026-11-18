import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../icons.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets.dart';

class JarsScreen extends StatefulWidget {
  const JarsScreen({super.key});
  @override
  State<JarsScreen> createState() => _JarsScreenState();
}

class _JarsScreenState extends State<JarsScreen> {
  List<UserJar> jars = [];
  int used = 0, quota = 10 * 1024 * 1024, retention = 3;
  bool loading = true;
  String? busy, error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final j = await Api.instance.jars();
      int n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      final list = ((j['jars'] as List?) ?? []).map((e) {
        final o = e as Map<String, dynamic>;
        return UserJar('${o['id']}', '${o['name']}', n(o['size']), n(o['createdAt']), '${o['iconDataUrl'] ?? ''}');
      }).toList();
      if (!mounted) return;
      setState(() {
        jars = list;
        used = n(j['usedBytes']);
        final q = n(j['quotaBytes']);
        if (q > 0) quota = q;
        retention = n(j['retentionDays']) > 0 ? n(j['retentionDays']) : retention;
        loading = false;
        error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() { loading = false; error = e.message; });
    }
  }

  Future<void> pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.single;
    if (f == null || f.bytes == null) return;
    if (!f.name.toLowerCase().endsWith('.jar')) {
      toast(context, 'Chỉ chấp nhận tệp .JAR', error: true);
      return;
    }
    setState(() => busy = 'Đang tải ${f.name} lên…');
    try {
      await Api.instance.uploadJar(f.name, f.bytes!);
      if (mounted) toast(context, 'Đã tải ${f.name} lên');
      await load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => busy = null);
  }

  Future<void> rename(UserJar j) async {
    final c = TextEditingController(text: j.name);
    final name = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Jp.surface,
        title: Text('Đổi tên JAR', style: TextStyle(color: Jp.text, fontWeight: FontWeight.w700)),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Hủy', style: TextStyle(color: Jp.muted))),
          TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Lưu', style: TextStyle(color: Jp.primary, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == j.name) return;
    try {
      await Api.instance.renameJar(j.id, name);
      load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> remove(UserJar j) async {
    if (!await confirmDialog(context, 'Xóa JAR?', 'Xóa "${j.name}" khỏi kho. Không thể hoàn tác.', ok: 'Xóa', danger: true)) return;
    try {
      await Api.instance.deleteJar(j.id);
      load();
    } on ApiError catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  static String _fmtDate(int ms) {
    if (ms <= 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(ms < 100000000000 ? ms * 1000 : ms);
    String t(int n) => n.toString().padLeft(2, '0');
    return '${t(d.day)}/${t(d.month)}/${d.year}';
  }

  Widget _icon(UserJar j) {
    final i = j.iconDataUrl.indexOf('base64,');
    if (i > 0) {
      try {
        return Image.memory(base64Decode(j.iconDataUrl.substring(i + 7)), width: 32, height: 32, filterQuality: FilterQuality.none, fit: BoxFit.contain);
      } catch (_) {}
    }
    return const JpIcon(JpIcons.toolJar, color: Jp.primary, size: 20);
  }

  @override
  Widget build(BuildContext context) {
    final frac = quota > 0 ? (used / quota).clamp(0.0, 1.0) : 0.0;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.only(bottom: 20), children: [
        const PageHead('ỨNG DỤNG JAVA', 'Kho JAR của tôi', 'Một kho chung cho mọi phiên thuê của bạn. Tải lên ở đây hoặc ngay trên màn hình thiết bị, chọn chạy ở bất kỳ máy J2ME nào.'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SectionCard('Tải JAR lên', sub: 'Chỉ nhận tệp .JAR, tổng tối đa ${fmtSize(quota)} cho cả kho.', children: [
            Row(children: [
              Expanded(child: Text('Đã dùng ${fmtSize(used)} / ${fmtSize(quota)}', style: TextStyle(fontSize: 12, color: Jp.text))),
              Text('${(frac * 100).toInt()}%', style: TextStyle(fontSize: 12, color: Jp.muted)),
            ]),
            Container(
              margin: const EdgeInsets.only(top: 6),
              height: 6,
              decoration: BoxDecoration(color: const Color(0xFFE4E9F2), borderRadius: BorderRadius.circular(3)),
              child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: frac.toDouble(), child: Container(decoration: BoxDecoration(color: frac > 0.9 ? Jp.danger : Jp.primary, borderRadius: BorderRadius.circular(3)))),
            ),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: PrimaryButton(busy ?? 'Chọn tệp .JAR và tải lên', busy == null ? pick : null, loading: busy != null, height: 40, fontSize: 13, icon: JpIcons.navUpload)),
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Lưu ý: JAR trong kho sẽ tự xóa sau $retention ngày không có phiên thuê.', style: TextStyle(fontSize: 11, color: Jp.muted, height: 1.35))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(children: [
            Text('JAR của tôi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Jp.text)),
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(99)), child: Text('${jars.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Jp.primary))),
          ]),
        ),
        if (loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: Jp.primary, strokeWidth: 2)))
        else if (error != null) Padding(padding: const EdgeInsets.all(20), child: Text(error!, style: const TextStyle(color: Jp.danger)))
        else if (jars.isEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: cardDeco(radius: 12),
            child: Column(children: [
              Container(width: 44, height: 44, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(10)), child: const Center(child: JpIcon(JpIcons.toolJar, color: Jp.primary, size: 22))),
              Padding(padding: const EdgeInsets.only(top: 10), child: Text('Kho trống', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text))),
              Padding(padding: const EdgeInsets.only(top: 2), child: Text('Tải JAR lên để chạy trên mọi máy J2ME của bạn.', style: TextStyle(fontSize: 12, color: Jp.muted))),
            ]),
          )
        else
          for (final j in jars)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.all(10),
              decoration: cardDeco(radius: 12),
              child: Row(children: [
                Container(width: 40, height: 40, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(9)), child: Center(child: _icon(j))),
                Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Jp.text)),
                    Text('${fmtSize(j.size)} · ${_fmtDate(j.createdAt)}', style: TextStyle(fontSize: 11, color: Jp.muted)),
                  ]),
                )),
                GestureDetector(
                  onTap: () => rename(j),
                  child: Container(width: 30, height: 30, decoration: BoxDecoration(border: Border.all(color: Jp.lineStrong), borderRadius: BorderRadius.circular(8)), child: const Center(child: JpIcon(JpIcons.edit, size: 15, color: Jp.primary))),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => remove(j),
                  child: Container(width: 30, height: 30, decoration: BoxDecoration(color: Jp.danger, borderRadius: BorderRadius.circular(8)), child: const Center(child: JpIcon(JpIcons.trash, size: 15, color: Colors.white))),
                ),
              ]),
            ),
      ]),
    );
  }
}
