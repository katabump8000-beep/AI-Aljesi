import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'core.dart';

const _red=Color(redColorValue);
const _muted=Color(0xFF9A9AA4);

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState()=>_MainShellState();
}
class _MainShellState extends State<MainShell> {
  int index=0;
  final pages=const [ChatScreen(),ModelScreen(),ApiScreen(),DiagnosticsScreen()];
  final titles=['المحادثة','مكتبة النماذج','اتصالات API','مركز الأخطاء'];
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Row(children:[
      Container(width:34,height:34,decoration:BoxDecoration(color:_red,borderRadius:BorderRadius.circular(10)),child:const Icon(Icons.bolt,color:Colors.white)),
      const SizedBox(width:10),const Text('DARK GPT',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1)),
    ]),actions:[Padding(padding:const EdgeInsets.only(right:14),child:Center(child:Text(titles[index],style:const TextStyle(color:_muted,fontSize:12))))]),
    body:pages[index],
    bottomNavigationBar:NavigationBar(
      selectedIndex:index,onDestinationSelected:(v)=>setState(()=>index=v),
      backgroundColor:const Color(0xFF17171D),indicatorColor:_red.withValues(alpha:.18),
      destinations:const [
        NavigationDestination(icon:Icon(Icons.chat_bubble_outline),selectedIcon:Icon(Icons.chat),label:'الدردشة'),
        NavigationDestination(icon:Icon(Icons.memory),label:'النماذج'),
        NavigationDestination(icon:Icon(Icons.cloud_outlined),label:'API'),
        NavigationDestination(icon:Icon(Icons.bug_report_outlined),label:'الأخطاء'),
      ],
    ),
  );
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override State<ChatScreen> createState()=>_ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final input=TextEditingController();
  final scroll=ScrollController();
  final local=LocalEngine();
  List<ChatLine> lines=[];
  List<String> attached=[];
  bool busy=false;
  String? activeModel;
  String mode='local';
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    try {
      final h=await Store.chat(); final id=await Store.activeId();
      final ms=await Store.models();
      if(!mounted)return;
      setState(()=>{lines=h,activeModel=ms.where((m)=>m.id==id).isEmpty?null:ms.firstWhere((m)=>m.id==id).name});
    }catch(e,st){await _error('Chat init','تعذر تحميل المحادثة',e,st);}
  }
  Future<void> _error(String area,String title,Object e,StackTrace st) async {
    await Store.log(Diagnostic(area,title,e.toString(),st.toString()));
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$title: $e')));
  }
  Future<void> _attach() async {
    try {
      final r=await FilePicker.platform.pickFiles(allowMultiple:true,withData:true);
      if(r==null)return;
      final snippets=<String>[];
      for(final f in r.files) {
        final ext=(f.extension??'').toLowerCase();
        if(f.bytes==null) continue;
        if(['txt','md','json','csv','dart','yaml','yml','xml','html','css','js','py','java','kt','sql'].contains(ext)) {
          final text=utf8.decode(f.bytes!,allowMalformed:true);
          snippets.add('\\n[FILE: ${f.name}]\\n${text.length>18000?text.substring(0,18000):text}\\n[/FILE]');
          attached.add(f.name);
        } else {
          attached.add('${f.name} (تم إرفاقه، لكن استخراج نص هذا النوع غير مدعوم حالياً)');
        }
      }
      if(snippets.isNotEmpty) input.text='${input.text}\\n\\n${snippets.join('\\n')}';
      if(mounted)setState((){});
    }catch(e,st){await _error('Attachments','تعذر قراءة المرفق',e,st);}
  }
  Future<void> _send() async {
    final prompt=input.text.trim();
    if(prompt.isEmpty||busy)return;
    final user=ChatLine('user',prompt,DateTime.now());
    setState(()=>{lines.add(user),busy=true});
    input.clear(); attached.clear();
    try {
      final api=await ApiConfig.load();
      String answer;
      if(mode=='api') {
        if(api==null) throw Exception('أضف اتصال API أولاً من تبويب API.');
        answer=await ApiChat().send(api,lines.where((e)=>e!=user).toList(),prompt);
      } else {
        final id=await Store.activeId();
        final models=await Store.models();
        final selected=models.where((m)=>m.id==id).toList();
        if(selected.isEmpty) throw Exception('اختر نموذج GGUF من مكتبة النماذج أولاً.');
        if(local.loadedPath!=selected.first.path) await local.load(selected.first.path);
        answer=await local.send(lines.where((e)=>e!=user).toList(),prompt);
      }
      lines.add(ChatLine('assistant',answer,DateTime.now()));
      await Store.saveChat(lines);
    }catch(e,st){await _error('Chat generation','فشل توليد الرد',e,st);lines.add(ChatLine('assistant','حدث خطأ أثناء التنفيذ. افتح مركز الأخطاء لنسخ التقرير.\\n\\n${e.toString()}',DateTime.now()));}
    finally{if(mounted)setState(()=>busy=false);_scrollDown();}
  }
  void _scrollDown()=>WidgetsBinding.instance.addPostFrameCallback((_){if(scroll.hasClients)scroll.animateTo(scroll.position.maxScrollExtent,duration:const Duration(milliseconds:250),curve:Curves.easeOut);});
  Future<void> _makeTextFile() async {
    final name=TextEditingController(text:'dark_gpt_note.txt');
    final body=TextEditingController(text:lines.isEmpty?'':lines.last.text);
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('إنشاء ملف نصي'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:name,decoration:const InputDecoration(labelText:'اسم الملف')),
      const SizedBox(height:8),TextField(controller:body,maxLines:6,decoration:const InputDecoration(labelText:'المحتوى')),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('إنشاء'))]));
    if(ok!=true)return;
    try {
      final f=await FileTools.createText(name.text,body.text);
      if(!mounted)return;
      await showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('تم إنشاء الملف'),content:Text(f.path),actions:[
        TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إغلاق')),
        FilledButton(onPressed:()async{await Share.shareXFiles([XFile(f.path)]);if(c.mounted)Navigator.pop(c);},child:const Text('مشاركة / تنزيل')),
      ]));
    }catch(e,st){await _error('File creation','تعذر إنشاء الملف',e,st);}
  }
  @override void dispose(){input.dispose();scroll.dispose();local.unload();super.dispose();}
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.fromLTRB(14,8,14,4),child:Row(children:[
      Expanded(child:Text(activeModel??'لم يتم اختيار نموذج محلي',style:const TextStyle(color:_muted,fontSize:12),overflow:TextOverflow.ellipsis)),
      DropdownButton<String>(value:mode,underline:const SizedBox(),items:const [
        DropdownMenuItem(value:'local',child:Text('محلي GGUF')),
        DropdownMenuItem(value:'api',child:Text('API')),
      ],onChanged:(v)=>setState(()=>mode=v??'local')),
      IconButton(tooltip:'إنشاء ملف',onPressed:_makeTextFile,icon:const Icon(Icons.note_add_outlined)),
    ])),
    Expanded(child:lines.isEmpty?const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(Icons.auto_awesome,color:_red,size:42),SizedBox(height:12),
      Text('مرحباً بك في Dark GPT',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      SizedBox(height:6),Text('اختر نموذجاً أو اربط API وابدأ المحادثة.',style:TextStyle(color:_muted)),
    ])):ListView.builder(controller:scroll,padding:const EdgeInsets.all(14),itemCount:lines.length+(busy?1:0),itemBuilder:(c,i){
      if(i==lines.length)return const Padding(padding:EdgeInsets.all(12),child:LinearProgressIndicator(color:_red));
      final m=lines[i];final user=m.role=='user';
      return Align(alignment:user?Alignment.centerRight:Alignment.centerLeft,child:Container(
        constraints:BoxConstraints(maxWidth:MediaQuery.of(context).size.width*.88),
        margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.all(13),
        decoration:BoxDecoration(color:user?const Color(0xFF352126):const Color(0xFF202027),borderRadius:BorderRadius.circular(16)),
        child:SelectableText(m.text,style:const TextStyle(height:1.45)),
      ));
    })),
    SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(12,6,12,10),child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
      IconButton(onPressed:busy?null:_attach,icon:const Icon(Icons.attach_file)),
      Expanded(child:TextField(controller:input,minLines:1,maxLines:5,decoration:const InputDecoration(hintText:'اكتب رسالتك إلى Dark GPT...',contentPadding:EdgeInsets.all(14)))),
      const SizedBox(width:7),
      IconButton.filled(onPressed:busy?null:_send,style:IconButton.styleFrom(backgroundColor:_red),icon:Icon(busy?Icons.hourglass_top:Icons.arrow_upward)),
    ]))),
  ]);
}

class ModelScreen extends StatefulWidget {
  const ModelScreen({super.key});
  @override State<ModelScreen> createState()=>_ModelScreenState();
}
class _ModelScreenState extends State<ModelScreen> {
  List<ModelEntry> models=[];String? active;bool busy=false;double progress=0;String status='';
  final url=TextEditingController();final name=TextEditingController();
  @override void initState(){super.initState();refresh();}
  Future<void> refresh()async{final m=await Store.models();final a=await Store.activeId();if(mounted)setState(()=>{models=m,active=a});}
  Future<void> _log(String title,Object e,StackTrace st)async{await Store.log(Diagnostic('Model library',title,e.toString(),st.toString()));}
  Future<void> importModel()async{
    try{
      final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['gguf'],withData:false);
      if(r==null||r.files.single.path==null)return;
      final f=File(r.files.single.path!);final dest=await Store.modelsDir();final target=File('${dest.path}/${r.files.single.name}');
      await f.copy(target.path);await ModelManager().register(target.path,r.files.single.name,await target.length());await refresh();
    }catch(e,st){await _log('فشل استيراد النموذج',e,st);}
  }
  Future<void> downloadModel()async{
    final u=url.text.trim();if(u.isEmpty)return;
    final filename=name.text.trim().isEmpty?Uri.parse(u).pathSegments.last:name.text.trim();
    setState(()=>{busy=true,progress=0,status='بدء التنزيل...'});
    try{
      final path=await ModelManager().download(u,filename,(received,total){if(mounted)setState(()=>{progress=total>0?received/total:0,status=total>0?'${(received/total*100).toStringAsFixed(1)}%':'${(received/1024/1024).toStringAsFixed(1)} MB'});});
      await ModelManager().register(path,filename,await File(path).length());await refresh();
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('اكتمل تنزيل النموذج وإضافته إلى المكتبة.')));
    }catch(e,st){await _log('فشل تنزيل النموذج',e,st);if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل التنزيل: $e')));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _downloadDialog()async{
    url.clear();name.clear();
    await showDialog(context:context,builder:(c)=>AlertDialog(title:const Text('تنزيل نموذج GGUF'),content:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:url,decoration:const InputDecoration(labelText:'رابط التنزيل المباشر',hintText:'https://.../model.gguf')),
      const SizedBox(height:8),TextField(controller:name,decoration:const InputDecoration(labelText:'اسم الملف (اختياري)')),
      const SizedBox(height:8),const Text('استخدم رابط ملف GGUF مباشر. قد تكون الملفات عدة جيجابايت.',style:TextStyle(color:_muted,fontSize:12)),
    ]),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('إلغاء')),FilledButton(onPressed:(){Navigator.pop(c);downloadModel();},child:const Text('تنزيل'))]));
  }
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(14),children:[
    Row(children:[Expanded(child:Text('النماذج المحمّلة (${models.length})',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),IconButton(onPressed:importModel,icon:const Icon(Icons.file_open)),FilledButton.icon(onPressed:busy?null:_downloadDialog,icon:const Icon(Icons.download),label:const Text('تنزيل'))]),
    if(busy)...[const SizedBox(height:12),LinearProgressIndicator(value:progress==0?null:progress,color:_red),const SizedBox(height:5),Text(status,style:const TextStyle(color:_muted))],
    if(models.isEmpty&&!busy)const Padding(padding:EdgeInsets.all(28),child:Text('لا توجد نماذج بعد. استورد ملف GGUF أو نزّله من رابط مباشر.',textAlign:TextAlign.center,style:TextStyle(color:_muted))),
    ...models.map((m)=>Card(child:ListTile(
      leading:const Icon(Icons.memory,color:_red,size:30),
      title:Text(m.name,maxLines:1,overflow:TextOverflow.ellipsis),
      subtitle:Text('${_size(m.bytes)} • GGUF${active==m.id?' • نشط':''}'),
      trailing:PopupMenuButton<String>(onSelected:(v)async{
        try{if(v=='active'){await Store.setActive(m.id);}else if(v=='delete'){await ModelManager().delete(m);}await refresh();}
        catch(e,st){await _log('فشل تعديل النموذج',e,st);}
      },itemBuilder:(_)=>const [
        PopupMenuItem(value:'active',child:Text('اختيار كنموذج نشط')),
        PopupMenuItem(value:'delete',child:Text('حذف النموذج من الجهاز')),
      ]),
    ))),
    const Padding(padding:EdgeInsets.all(8),child:Text('ملاحظة: تشغيل نموذج كبير يحتاج ذاكرة RAM كافية. صيغة التشغيل المحلي المدعومة هنا هي GGUF.',style:TextStyle(color:_muted,fontSize:12))),
  ]);
}

String _size(int b)=>b>=1073741824?'${(b/1073741824).toStringAsFixed(2)} GB':'${(b/1048576).toStringAsFixed(1)} MB';

class ApiScreen extends StatefulWidget {
  const ApiScreen({super.key});
  @override State<ApiScreen> createState()=>_ApiScreenState();
}
class _ApiScreenState extends State<ApiScreen>{
  final n=TextEditingController(),b=TextEditingController(text:'https://api.openai.com/v1'),m=TextEditingController(),k=TextEditingController();
  bool obscure=true,hasConfig=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{final c=await ApiConfig.load();if(c!=null){n.text=c.name;b.text=c.baseUrl;m.text=c.model;k.text=c.key;if(mounted)setState(()=>hasConfig=true);}}
  Future<void> save()async{
    if(b.text.trim().isEmpty||m.text.trim().isEmpty||k.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('أكمل عنوان API واسم النموذج والمفتاح.')));return;}
    try{await ApiConfig.save(ApiConfig(name:n.text.trim().isEmpty?'My API':n.text.trim(),baseUrl:b.text.trim(),model:m.text.trim(),key:k.text.trim()));if(mounted)setState(()=>hasConfig=true);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم حفظ اتصال API بأمان.')));}
    catch(e,st){await Store.log(Diagnostic('API','فشل حفظ الإعدادات',e.toString(),st.toString()));}
  }
  Future<void> clear()async{await ApiConfig.clear();n.clear();m.clear();k.clear();if(mounted)setState(()=>hasConfig=false);}
  @override void dispose(){n.dispose();b.dispose();m.dispose();k.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('ربط مزود ذكاء اصطناعي',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const SizedBox(height:6),const Text('يدعم المزودين الذين يقدمون واجهة متوافقة مع OpenAI Chat Completions.',style:TextStyle(color:_muted)),
    const SizedBox(height:18),
    TextField(controller:n,decoration:const InputDecoration(labelText:'اسم الاتصال')),
    const SizedBox(height:10),TextField(controller:b,decoration:const InputDecoration(labelText:'Base URL',hintText:'https://api.example.com/v1')),
    const SizedBox(height:10),TextField(controller:m,decoration:const InputDecoration(labelText:'اسم النموذج')),
    const SizedBox(height:10),TextField(controller:k,obscureText:obscure,decoration:InputDecoration(labelText:'API Key',suffixIcon:IconButton(onPressed:()=>setState(()=>obscure=!obscure),icon:Icon(obscure?Icons.visibility:Icons.visibility_off)))),
    const SizedBox(height:16),FilledButton.icon(onPressed:save,icon:const Icon(Icons.save),label:const Text('حفظ الاتصال')),
    if(hasConfig)TextButton.icon(onPressed:clear,icon:const Icon(Icons.delete_outline),label:const Text('حذف الاتصال المحفوظ')),
    const SizedBox(height:14),const Text('مفاتيح API تحفظ باستخدام التخزين الآمن في الجهاز. لا تشارك المفتاح ولا ترفعه إلى GitHub.',style:TextStyle(color:Colors.orangeAccent,fontSize:12)),
  ]);
}

class DiagnosticsScreen extends StatefulWidget{
  const DiagnosticsScreen({super.key});
  @override State<DiagnosticsScreen> createState()=>_DiagnosticsScreenState();
}
class _DiagnosticsScreenState extends State<DiagnosticsScreen>{
  List<Map<String,dynamic>> errors=[];
  @override void initState(){super.initState();load();}
  Future<void> load()async{final e=await Store.errors();if(mounted)setState(()=>errors=e);}
  Future<void> copy()async{
    final report=jsonEncode({'app':'Dark GPT','version':'1.0.0','platform':Platform.operatingSystem,'createdAt':DateTime.now().toIso8601String(),'errors':errors});
    await Clipboard.setData(ClipboardData(text=report));
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('تم نسخ تقرير الأخطاء. أرسله للمساعدة في التشخيص.')));
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      Expanded(child:Text('سجل الأخطاء (${errors.length})',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
      IconButton(onPressed:copy,tooltip:'نسخ التقرير',icon:const Icon(Icons.copy_all)),
      IconButton(onPressed:()async{await Store.clearErrors();await load();},tooltip:'مسح السجل',icon:const Icon(Icons.delete_outline)),
    ])),
    Expanded(child:errors.isEmpty?const Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
      Icon(Icons.check_circle_outline,color:Colors.green,size:44),SizedBox(height:8),Text('لا توجد أخطاء مسجلة'),
    ])):ListView.builder(itemCount:errors.length,itemBuilder:(c,i){
      final e=errors[i];
      return Card(child:ExpansionTile(
        leading:const Icon(Icons.error_outline,color:Colors.orange),
        title:Text(e['title']??'Error'),
        subtitle:Text('${e['area']} • ${e['time']}'),
        childrenPadding:const EdgeInsets.all(14),
        children:[Align(alignment:Alignment.centerLeft,child:SelectableText('${e['message']}\\n\\n${e['stack']??''}'))],
      ));
    })),
  ]);
}
