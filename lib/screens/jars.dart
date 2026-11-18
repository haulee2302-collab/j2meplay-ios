import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
        return UserJar('${o['id']}', '${o['name']}', n(o['size']), n(o['createdAt']));
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

  @override
  Widget build(BuildContext context) {
    final pct = quota > 0 ? (used / quota).clamp(0.0, 1.0) : 0.0;
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: EdgeInsets.zero, children: [
        HeroHeader(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.folder_zip_outlined, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Của bạn', style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12)),
                const Text('Kho JAR', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              ])),
              const ThemeToggle(),
            ]),
            const SizedBox(height: 14),
            Text('${fmtSize(used)} / ${fmtSize(quota)}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: pct.toDouble(), minHeight: 6, backgroundColor: Colors.white24, color: Jp.highlight)),
            const SizedBox(height: 6),
            Text('Tệp được giữ $retention ngày kể từ lần dùng gần nhất.', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12)),
            const SizedBox(height: 12),
            PrimaryButton('Tải JAR lên', busy == null ? pick : null, loading: busy != null, icon: Icons.upload_file, container: Colors.white, content: Jp.primary, height: 40, fontSize: 13),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 18, 16, 8), child: SectionTitle('Tệp JAR của bạn', count: jars.length)),
        if (busy != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(busy!, style: TextStyle(color: Jp.muted, fontSize: 13))),
        if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: Jp.primary)))
        else if (error != null) Padding(padding: const EdgeInsets.all(20), child: Text(error!, style: const TextStyle(color: Jp.danger)))
        else if (jars.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Chưa có JAR nào. Hãy tải một tệp .jar lên.', style: TextStyle(color: Jp.muted))))
        else for (final j in jars)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.all(12),
            decoration: cardDeco(),
            child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Jp.primarySoft, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.sports_esports, color: Jp.primary, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(j.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: Jp.text)),
                Text(fmtSize(j.size), style: TextStyle(fontSize: 12, color: Jp.muted)),
              ])),
              IconButton(onPressed: () => rename(j), icon: const Icon(Icons.edit_outlined, size: 19, color: Jp.primary)),
              IconButton(onPressed: () => remove(j), icon: const Icon(Icons.delete_outline, size: 19, color: Jp.danger)),
            ]),
          ),
        const SizedBox(height: 28),
      ]),
    );
  }
}
