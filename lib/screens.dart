import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'core.dart';
import 'galaxy.dart';
import 'sounds.dart';

const _sheetBg = Color(0xFF120E2A);

String _size(int b) => b >= 1073741824 ? '${(b / 1073741824).toStringAsFixed(2)} GB' : '${(b / 1048576).toStringAsFixed(1)} MB';
String _short(String s) => s.length > 120 ? '${s.substring(0, 120)}...' : s;

Widget _sheetTile(IconData icon, String title, VoidCallback onTap) =>
    ListTile(leading: Icon(icon, color: kCyan), title: Text(title), onTap: onTap);

Future<bool> _isGguf(String path) async {
  final f = await File(path).open();
  try {
    final b = await f.read(4);
    return b.length == 4 && b[0] == 0x47 && b[1] == 0x47 && b[2] == 0x55 && b[3] == 0x46;
  } finally {
    await f.close();
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  final pages = const [ChatScreen(), ModelScreen(), ApiScreen(), DiagnosticsScreen()];
  final titles = ['المحادثة', 'مكتبة النماذج', 'اتصالات API', 'مركز الأخطاء'];

  @override
  Widget build(BuildContext context) {
    return GalaxyBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [kPurple, kPink]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: kPurple.withValues(alpha: 0.6), blurRadius: 14)],
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [kCyan, kPink, kGold]).createShader(r),
              child: const Text('DARK GPT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.4, color: Colors.white)),
            ),
          ]),
          actions: [
            Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Center(child: Text(titles[index], style: const TextStyle(color: kMuted, fontSize: 12))),
            ),
          ],
        ),
        body: pages[index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (v) => setState(() => index = v),
          backgroundColor: const Color(0xCC0B0820),
          indicatorColor: kPurple.withValues(alpha: 0.3),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat), label: 'الدردشة'),
            NavigationDestination(icon: Icon(Icons.memory), label: 'النماذج'),
            NavigationDestination(icon: Icon(Icons.cloud_outlined), label: 'API'),
            NavigationDestination(icon: Icon(Icons.bug_report_outlined), label: 'الأخطاء'),
          ],
        ),
      ),
    );
  }
}

class _Att {
  final String name, kind;
  final String? content;
  const _Att(this.name, this.kind, [this.content]);
  String get label => kind != 'image' && kind != 'audio' ? name : '$name (غير مدعوم بعد)';
}

class _Working extends StatefulWidget {
  const _Working();
  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final dots = '.' * (1 + (c.value * 3).floor() % 3);
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xCC17123A),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: kCyan.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kCyan)),
              const SizedBox(width: 10),
              Text('جاري العمل$dots', style: const TextStyle(color: kCyan)),
            ]),
          ),
        );
      },
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final local = LocalEngine();
  List<ChatLine> lines = [];
  final List<_Att> attached = [];
  bool busy = false;
  String? activeModel;
  String mode = 'local';
  ChatLine? replyTo;
  int _gen = 0;
  int _prevLen = 0;
  static const int _fileWords = 120;
  int _words(String s) => RegExp(r'\S+').allMatches(s).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await Store.chat();
      final id = await Store.activeId();
      final ms = await Store.models();
      String? name;
      for (final m in ms) {
        if (m.id == id) name = m.name;
      }
      if (!mounted) return;
      setState(() {
        lines = h;
        activeModel = name;
      });
      _scrollDown();
    } catch (e, st) {
      await _error('Chat init', 'تعذر تحميل المحادثة', e, st);
    }
  }

  Future<void> _error(String area, String title, Object e, StackTrace st) async {
    await Store.log(Diagnostic(area, title, e.toString(), st.toString()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title: $e')));
  }

  void _plus() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _sheetBg,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetTile(Icons.description_outlined, 'رفع ملف', () {
            Navigator.pop(c);
            _attach(FileType.any, 'file');
          }),
          _sheetTile(Icons.image_outlined, 'رفع صورة', () {
            Navigator.pop(c);
            _attach(FileType.image, 'image');
          }),
          _sheetTile(Icons.audiotrack_outlined, 'رفع صوتية', () {
            Navigator.pop(c);
            _attach(FileType.audio, 'audio');
          }),
        ]),
      ),
    );
  }

  Future<void> _attach(FileType type, String kind) async {
    try {
      final r = await FilePicker.platform.pickFiles(type: type, allowMultiple: true, withData: kind == 'file');
      if (r == null) return;
      for (final f in r.files) {
        if (kind != 'file') {
          attached.add(_Att(f.name, kind));
          continue;
        }
        final ext = (f.extension ?? '').toLowerCase();
        final bytes = f.bytes;
        if (bytes == null) continue;
        if (['txt', 'md', 'json', 'csv', 'dart', 'yaml', 'yml', 'xml', 'html', 'css', 'js', 'py', 'java', 'kt', 'sql'].contains(ext)) {
          final text = utf8.decode(bytes, allowMalformed: true);
          attached.add(_Att(f.name, 'file', text.length > 18000 ? text.substring(0, 18000) : text));
        } else {
          attached.add(_Att('${f.name} (استخراج نص هذا النوع غير مدعوم)', 'other'));
        }
      }
      if (kind != 'file' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الإرفاق، لكن النموذج الحالي نصي فقط ولن يرى الصورة أو الصوت.')));
      }
      if (mounted) setState(() {});
    } catch (e, st) {
      await _error('Attachments', 'تعذر قراءة المرفق', e, st);
    }
  }

  void _onInputChanged(String v) {
    final jump = v.length - _prevLen;
    _prevLen = v.length;
    // لصق نص طويل مباشرة: يتحول إلى ملف txt
    if (jump >= 60 && _words(v) > _fileWords) {
      _toFile(v);
    }
  }

  void _toFile(String text) {
    final n = attached.where((a) => a.content != null).length + 1;
    attached.add(_Att('text_$n.txt', 'file', text.trim()));
    input.clear();
    _prevLen = 0;
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    if (busy) return;
    var text = input.text.trim();
    // كتابة نص طويل ثم إرسال: يتحول إلى ملف txt
    if (text.isNotEmpty && _words(text) > _fileWords) {
      final n = attached.where((a) => a.content != null).length + 1;
      attached.add(_Att('text_$n.txt', 'file', text));
      text = '';
    }
    final blocks = attached.where((a) => a.content != null).map((a) => '[FILE: ${a.name}]\n${a.content}\n[/FILE]').toList();
    if (text.isEmpty && blocks.isEmpty) return;
    var prompt = [if (text.isNotEmpty) text, ...blocks].join('\n\n');
    if (replyTo != null) prompt = '> ${_short(replyTo!.text)}\n\n$prompt';
    final history = List<ChatLine>.from(lines);
    setState(() {
      lines.add(ChatLine('user', prompt, DateTime.now()));
      replyTo = null;
      attached.clear();
    });
    input.clear();
    _prevLen = 0;
    Sfx.send();
    await _generate(prompt, history);
  }

  Future<void> _generate(String prompt, List<ChatLine> history) async {
    final my = ++_gen;
    setState(() => busy = true);
    _scrollDown();
    var answer = '';
    var failed = false;
    try {
      if (mode == 'api') {
        final api = await ApiConfig.load();
        if (api == null) throw Exception('أضف اتصال API أولاً من تبويب API.');
        answer = await ApiChat().send(api, history, prompt);
      } else {
        final id = await Store.activeId();
        final models = await Store.models();
        final selected = models.where((m) => m.id == id).toList();
        if (selected.isEmpty) throw Exception('اختر نموذج GGUF من مكتبة النماذج أولاً.');
        if (!await _isGguf(selected.first.path)) throw Exception('ملف النموذج تالف أو ليس بصيغة GGUF.');
        if (local.loadedPath != selected.first.path) await local.load(selected.first.path);
        answer = await local.send(history, prompt);
      }
    } catch (e, st) {
      failed = true;
      answer = 'حدث خطأ أثناء التنفيذ:\n${e.toString()}\n\nافتح مركز الأخطاء لنسخ التقرير.';
      if (my == _gen) await Store.log(Diagnostic('Chat generation', 'فشل توليد الرد', e.toString(), st.toString()));
    }
    if (my != _gen || !mounted) return;
    setState(() {
      lines.add(ChatLine('assistant', answer, DateTime.now()));
      busy = false;
    });
    await Store.saveChat(lines);
    if (failed) {
      Sfx.tap();
    } else {
      Sfx.receive();
    }
    _scrollDown();
  }

  void _cancel() {
    _gen++;
    setState(() => busy = false);
    Store.saveChat(lines);
    Sfx.tap();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الرد.')));
  }

  Future<void> _edit(int i) async {
    final c = TextEditingController(text: lines[i].text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('تعديل الرسالة'),
        content: TextField(controller: c, maxLines: 6, minLines: 1),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حفظ وإعادة الإرسال')),
        ],
      ),
    );
    final prompt = c.text.trim();
    c.dispose();
    if (ok != true || prompt.isEmpty || !mounted) return;
    final history = lines.sublist(0, i);
    setState(() => lines = [...history, ChatLine('user', prompt, DateTime.now())]);
    Sfx.send();
    await _generate(prompt, history);
  }

  void _menu(int i) {
    if (busy) return;
    final m = lines[i];
    final user = m.role == 'user';
    showModalBottomSheet(
      context: context,
      backgroundColor: _sheetBg,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetTile(Icons.copy, 'نسخ', () {
            Navigator.pop(c);
            Clipboard.setData(ClipboardData(text: m.text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النسخ.')));
          }),
          _sheetTile(Icons.reply, 'رد على هذه الرسالة', () {
            Navigator.pop(c);
            setState(() => replyTo = m);
          }),
          if (user)
            _sheetTile(Icons.edit_outlined, 'تعديل وإعادة الإرسال', () {
              Navigator.pop(c);
              _edit(i);
            }),
          _sheetTile(Icons.delete_outline, 'حذف', () {
            Navigator.pop(c);
            setState(() => lines.removeAt(i));
            Store.saveChat(lines);
          }),
        ]),
      ),
    );
  }

  Future<void> _pickModel() async {
    final ms = await Store.models();
    final id = await Store.activeId();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: _sheetBg,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Padding(padding: EdgeInsets.all(14), child: Text('تغيير النموذج', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              ListTile(
                leading: const Icon(Icons.cloud_outlined, color: kCyan),
                title: const Text('API'),
                trailing: mode == 'api' ? const Icon(Icons.check, color: kCyan) : null,
                onTap: () {
                  Navigator.pop(c);
                  setState(() => mode = 'api');
                },
              ),
              if (ms.isEmpty)
                const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد نماذج محلية. أضفها من تبويب النماذج.', style: TextStyle(color: kMuted))),
              ...ms.map((m) => ListTile(
                    leading: const Icon(Icons.memory, color: kPink),
                    title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_size(m.bytes)),
                    trailing: (mode == 'local' && m.id == id) ? const Icon(Icons.check, color: kCyan) : null,
                    onTap: () async {
                      Navigator.pop(c);
                      await Store.setActive(m.id);
                      if (mounted) {
                        setState(() {
                          mode = 'local';
                          activeModel = m.name;
                        });
                      }
                    },
                  )),
            ]),
          ),
        ),
      ),
    );
  }

  void _newChat() {
    if (busy) return;
    setState(() {
      lines = [];
      replyTo = null;
    });
    Store.saveChat(lines);
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scroll.hasClients) {
          scroll.animateTo(scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _makeTextFile() async {
    final name = TextEditingController(text: 'dark_gpt_note.txt');
    final body = TextEditingController(text: lines.isEmpty ? '' : lines.last.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إنشاء ملف نصي'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الملف')),
          const SizedBox(height: 8),
          TextField(controller: body, maxLines: 6, decoration: const InputDecoration(labelText: 'المحتوى')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إنشاء')),
        ],
      ),
    );
    final fileName = name.text;
    final content = body.text;
    name.dispose();
    body.dispose();
    if (ok != true) return;
    try {
      final f = await FileTools.createText(fileName, content);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تم إنشاء الملف'),
          content: Text(f.path),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق')),
            FilledButton(
              onPressed: () async {
                await Share.shareXFiles([XFile(f.path)]);
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('مشاركة / تنزيل'),
            ),
          ],
        ),
      );
    } catch (e, st) {
      await _error('File creation', 'تعذر إنشاء الملف', e, st);
    }
  }

  @override
  void dispose() {
    _gen++;
    input.dispose();
    scroll.dispose();
    local.unload();
    super.dispose();
  }

  Widget _content(String t) {
    final re = RegExp(r'\[FILE: (.*?)\]\n([\s\S]*?)\n\[/FILE\]');
    final ms = re.allMatches(t).toList();
    if (ms.isEmpty) return Text(t, style: const TextStyle(height: 1.5));
    final rest = t.replaceAll(re, '').trim();
    final kids = <Widget>[];
    if (rest.isNotEmpty) kids.add(Text(rest, style: const TextStyle(height: 1.5)));
    for (final m in ms) {
      if (kids.isNotEmpty) kids.add(const SizedBox(height: 8));
      kids.add(_fileCard(m.group(1) ?? 'file.txt', m.group(2) ?? ''));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: kids);
  }

  Widget _fileCard(String name, String body) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openFile(name, body),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.description_outlined, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${_words(body)} كلمة', style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _openFile(String name, String body) async {
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(name, style: const TextStyle(fontSize: 16)),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(body))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إغلاق')),
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: body));
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('نسخ'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final f = await FileTools.createText(name, body);
                await Share.shareXFiles([XFile(f.path)]);
              } catch (e, st) {
                await _error('File share', 'تعذر مشاركة الملف', e, st);
              }
              if (c.mounted) Navigator.pop(c);
            },
            child: const Text('مشاركة / تنزيل'),
          ),
        ],
      ),
    );
  }

  Widget _bubble(int i) {
    final m = lines[i];
    final user = m.role == 'user';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _menu(i),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: user ? const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFFDB2777)]) : null,
            color: user ? null : const Color(0xCC17123A),
            borderRadius: BorderRadius.circular(18),
            border: user ? null : Border.all(color: kCyan.withValues(alpha: 0.25)),
            boxShadow: [BoxShadow(color: (user ? kPink : kCyan).withValues(alpha: 0.12), blurRadius: 12)],
          ),
          child: _content(m.text),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Row(children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ActionChip(
                avatar: Icon(mode == 'api' ? Icons.cloud_outlined : Icons.memory, size: 18, color: kCyan),
                label: Text(
                  mode == 'api' ? 'API' : (activeModel ?? 'اختر نموذجاً'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: _pickModel,
              ),
            ),
          ),
          IconButton(
            tooltip: 'الصوت',
            onPressed: () => setState(() => Sfx.enabled = !Sfx.enabled),
            icon: Icon(Sfx.enabled ? Icons.volume_up_outlined : Icons.volume_off_outlined),
          ),
          IconButton(tooltip: 'محادثة جديدة', onPressed: _newChat, icon: const Icon(Icons.add_comment_outlined)),
          IconButton(tooltip: 'إنشاء ملف', onPressed: _makeTextFile, icon: const Icon(Icons.note_add_outlined)),
        ]),
      ),
      Expanded(
        child: lines.isEmpty && !busy
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, color: kCyan, size: 46),
                  SizedBox(height: 12),
                  Text('مرحباً بك في Dark GPT', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('اختر نموذجاً أو اربط API وابدأ المحادثة.', style: TextStyle(color: kMuted)),
                ]),
              )
            : ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.all(14),
                itemCount: lines.length + (busy ? 1 : 0),
                itemBuilder: (c, i) => i == lines.length ? const _Working() : _bubble(i),
              ),
      ),
      if (replyTo != null)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xAA1A1440), borderRadius: BorderRadius.circular(12), border: Border.all(color: kCyan.withValues(alpha: 0.3))),
          child: Row(children: [
            const Icon(Icons.reply, size: 18, color: kCyan),
            const SizedBox(width: 8),
            Expanded(child: Text(_short(replyTo!.text), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kMuted, fontSize: 12))),
            IconButton(onPressed: () => setState(() => replyTo = null), icon: const Icon(Icons.close, size: 18)),
          ]),
        ),
      if (attached.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            children: attached.map((a) => Chip(label: Text(a.label, style: const TextStyle(fontSize: 11)), onDeleted: () => setState(() => attached.remove(a)))).toList(),
          ),
        ),
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            IconButton.filledTonal(onPressed: busy ? null : _plus, icon: const Icon(Icons.add)),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: input,
                onChanged: _onInputChanged,
                minLines: 1,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'اكتب رسالتك إلى Dark GPT...', contentPadding: EdgeInsets.all(14)),
              ),
            ),
            const SizedBox(width: 6),
            if (busy)
              IconButton.filled(onPressed: _cancel, style: IconButton.styleFrom(backgroundColor: Colors.redAccent), icon: const Icon(Icons.stop))
            else
              IconButton.filled(onPressed: _send, style: IconButton.styleFrom(backgroundColor: kPurple), icon: const Icon(Icons.arrow_upward)),
          ]),
        ),
      ),
    ]);
  }
}

class ModelScreen extends StatefulWidget {
  const ModelScreen({super.key});
  @override
  State<ModelScreen> createState() => _ModelScreenState();
}

class _ModelScreenState extends State<ModelScreen> {
  List<ModelEntry> models = [];
  String? active;
  bool busy = false;
  double progress = 0;
  String status = '';
  final url = TextEditingController();
  final name = TextEditingController();

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    url.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final m = await Store.models();
    final a = await Store.activeId();
    if (mounted) {
      setState(() {
        models = m;
        active = a;
      });
    }
  }

  Future<void> _log(String title, Object e, StackTrace st) async {
    await Store.log(Diagnostic('Model library', title, e.toString(), st.toString()));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title: $e')));
  }

  Future<void> importModel() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['gguf'], withData: false);
      if (r == null || r.files.single.path == null) return;
      final f = File(r.files.single.path!);
      final dest = await Store.modelsDir();
      final target = File('${dest.path}/${r.files.single.name}');
      await f.copy(target.path);
      if (!await _isGguf(target.path)) {
        await target.delete();
        throw Exception('الملف تالف أو ليس بصيغة GGUF.');
      }
      await ModelManager().register(target.path, r.files.single.name, await target.length());
      await refresh();
    } catch (e, st) {
      await _log('فشل استيراد النموذج', e, st);
    }
  }

  Future<void> downloadModel() async {
    final u = url.text.trim();
    if (u.isEmpty) return;
    final filename = name.text.trim().isEmpty ? Uri.parse(u).pathSegments.last : name.text.trim();
    setState(() {
      busy = true;
      progress = 0;
      status = 'بدء التنزيل...';
    });
    try {
      final path = await ModelManager().download(u, filename, (received, total) {
        if (mounted) {
          setState(() {
            progress = total > 0 ? received / total : 0;
            status = total > 0 ? '${(received / total * 100).toStringAsFixed(1)}%' : '${(received / 1024 / 1024).toStringAsFixed(1)} MB';
          });
        }
      });
      if (!await _isGguf(path)) {
        await File(path).delete();
        throw Exception('الملف المنزّل تالف أو ليس بصيغة GGUF.');
      }
      await ModelManager().register(path, filename, await File(path).length());
      await refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتمل تنزيل النموذج وإضافته إلى المكتبة.')));
    } catch (e, st) {
      await _log('فشل تنزيل النموذج', e, st);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _downloadDialog() async {
    url.clear();
    name.clear();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('تنزيل نموذج GGUF'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: url, decoration: const InputDecoration(labelText: 'رابط التنزيل المباشر', hintText: 'https://.../model.gguf')),
          const SizedBox(height: 8),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'اسم الملف (اختياري)')),
          const SizedBox(height: 8),
          const Text('استخدم رابط ملف GGUF مباشر. قد تكون الملفات عدة جيجابايت.', style: TextStyle(color: kMuted, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              downloadModel();
            },
            child: const Text('تنزيل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(14), children: [
      Row(children: [
        Expanded(child: Text('النماذج المحمّلة (${models.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        IconButton(tooltip: 'استيراد ملف', onPressed: importModel, icon: const Icon(Icons.file_open)),
        FilledButton.icon(onPressed: busy ? null : _downloadDialog, icon: const Icon(Icons.download), label: const Text('تنزيل')),
      ]),
      if (busy) ...[
        const SizedBox(height: 12),
        LinearProgressIndicator(value: progress == 0 ? null : progress, color: kCyan),
        const SizedBox(height: 5),
        Text(status, style: const TextStyle(color: kMuted)),
      ],
      if (models.isEmpty && !busy)
        const Padding(
          padding: EdgeInsets.all(28),
          child: Text('لا توجد نماذج بعد. استورد ملف GGUF أو نزّله من رابط مباشر.', textAlign: TextAlign.center, style: TextStyle(color: kMuted)),
        ),
      ...models.map((m) => Card(
            child: ListTile(
              leading: const Icon(Icons.memory, color: kPink, size: 30),
              title: Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${_size(m.bytes)} • GGUF${active == m.id ? ' • نشط' : ''}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  try {
                    if (v == 'active') {
                      await Store.setActive(m.id);
                    } else if (v == 'delete') {
                      await ModelManager().delete(m);
                    }
                    await refresh();
                  } catch (e, st) {
                    await _log('فشل تعديل النموذج', e, st);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'active', child: Text('اختيار كنموذج نشط')),
                  PopupMenuItem(value: 'delete', child: Text('حذف النموذج من الجهاز')),
                ],
              ),
            ),
          )),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('ملاحظة: تشغيل نموذج كبير يحتاج ذاكرة RAM كافية. صيغة التشغيل المحلي المدعومة هنا هي GGUF.', style: TextStyle(color: kMuted, fontSize: 12)),
      ),
    ]);
  }
}

class ApiScreen extends StatefulWidget {
  const ApiScreen({super.key});
  @override
  State<ApiScreen> createState() => _ApiScreenState();
}

class _ApiScreenState extends State<ApiScreen> {
  final n = TextEditingController(), b = TextEditingController(text: 'https://api.openai.com/v1'), m = TextEditingController(), k = TextEditingController();
  bool obscure = true, hasConfig = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await ApiConfig.load();
    if (c != null) {
      n.text = c.name;
      b.text = c.baseUrl;
      m.text = c.model;
      k.text = c.key;
      if (mounted) setState(() => hasConfig = true);
    }
  }

  Future<void> save() async {
    if (b.text.trim().isEmpty || m.text.trim().isEmpty || k.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أكمل عنوان API واسم النموذج والمفتاح.')));
      return;
    }
    try {
      await ApiConfig.save(ApiConfig(name: n.text.trim().isEmpty ? 'My API' : n.text.trim(), baseUrl: b.text.trim(), model: m.text.trim(), key: k.text.trim()));
      if (mounted) {
        setState(() => hasConfig = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ اتصال API بأمان.')));
      }
    } catch (e, st) {
      await Store.log(Diagnostic('API', 'فشل حفظ الإعدادات', e.toString(), st.toString()));
    }
  }

  Future<void> clear() async {
    await ApiConfig.clear();
    n.clear();
    m.clear();
    k.clear();
    if (mounted) setState(() => hasConfig = false);
  }

  @override
  void dispose() {
    n.dispose();
    b.dispose();
    m.dispose();
    k.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('ربط مزود ذكاء اصطناعي', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('يدعم المزودين الذين يقدمون واجهة متوافقة مع OpenAI Chat Completions.', style: TextStyle(color: kMuted)),
      const SizedBox(height: 18),
      TextField(controller: n, decoration: const InputDecoration(labelText: 'اسم الاتصال')),
      const SizedBox(height: 10),
      TextField(controller: b, decoration: const InputDecoration(labelText: 'Base URL', hintText: 'https://api.example.com/v1')),
      const SizedBox(height: 10),
      TextField(controller: m, decoration: const InputDecoration(labelText: 'اسم النموذج')),
      const SizedBox(height: 10),
      TextField(
        controller: k,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: 'API Key',
          suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: save, icon: const Icon(Icons.save), label: const Text('حفظ الاتصال')),
      if (hasConfig) TextButton.icon(onPressed: clear, icon: const Icon(Icons.delete_outline), label: const Text('حذف الاتصال المحفوظ')),
      const SizedBox(height: 14),
      const Text('مفاتيح API تحفظ باستخدام التخزين الآمن في الجهاز. لا تشارك المفتاح ولا ترفعه إلى GitHub.', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
    ]);
  }
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<Map<String, dynamic>> errors = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final e = await Store.errors();
    if (mounted) setState(() => errors = e);
  }

  Future<void> copy() async {
    final report = jsonEncode({
      'app': 'Dark GPT',
      'version': '1.0.0',
      'platform': Platform.operatingSystem,
      'createdAt': DateTime.now().toIso8601String(),
      'errors': errors,
    });
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ تقرير الأخطاء. أرسله للمساعدة في التشخيص.')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(child: Text('سجل الأخطاء (${errors.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(onPressed: copy, tooltip: 'نسخ التقرير', icon: const Icon(Icons.copy_all)),
          IconButton(
            onPressed: () async {
              await Store.clearErrors();
              await load();
            },
            tooltip: 'مسح السجل',
            icon: const Icon(Icons.delete_outline),
          ),
        ]),
      ),
      Expanded(
        child: errors.isEmpty
            ? const Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline, color: Colors.green, size: 44),
                  SizedBox(height: 8),
                  Text('لا توجد أخطاء مسجلة'),
                ]),
              )
            : ListView.builder(
                itemCount: errors.length,
                itemBuilder: (c, i) {
                  final e = errors[i];
                  return Card(
                    child: ExpansionTile(
                      leading: const Icon(Icons.error_outline, color: Colors.orange),
                      title: Text('${e['title'] ?? 'Error'}'),
                      subtitle: Text('${e['area']} • ${e['time']}'),
                      childrenPadding: const EdgeInsets.all(14),
                      children: [Align(alignment: Alignment.centerLeft, child: SelectableText('${e['message']}\n\n${e['stack'] ?? ''}'))],
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}
