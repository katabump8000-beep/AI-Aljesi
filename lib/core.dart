import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_local_llm/flutter_local_llm.dart';

const appName = 'Dark GPT';
const redColorValue = 0xFFD52D3A;
const _uuid = Uuid();

class ModelEntry {
  final String id, name, path, format;
  final int bytes;
  final DateTime addedAt;
  const ModelEntry({required this.id, required this.name, required this.path, required this.format, required this.bytes, required this.addedAt});
  Map<String, dynamic> toJson() => {'id':id,'name':name,'path':path,'format':format,'bytes':bytes,'addedAt':addedAt.toIso8601String()};
  factory ModelEntry.fromJson(Map<String,dynamic> j) => ModelEntry(
    id:j['id'], name:j['name'], path:j['path'], format:j['format'] ?? 'GGUF',
    bytes:j['bytes'] ?? 0, addedAt:DateTime.tryParse(j['addedAt'] ?? '') ?? DateTime.now(),
  );
}

class ChatLine {
  final String role, text;
  final DateTime time;
  const ChatLine(this.role, this.text, this.time);
  Map<String,dynamic> toJson()=>{'role':role,'text':text,'time':time.toIso8601String()};
  factory ChatLine.fromJson(Map<String,dynamic> j)=>ChatLine(j['role'],j['text'],DateTime.tryParse(j['time']??'')??DateTime.now());
}

class Diagnostic {
  final String id, area, title, message, stack;
  final DateTime time;
  Diagnostic(this.area,this.title,this.message,[this.stack=''])
    : id=_uuid.v4(), time=DateTime.now();
  Map<String,dynamic> toJson()=>{'id':id,'area':area,'title':title,'message':message,'stack':stack,'time':time.toIso8601String()};
}

class Store {
  static const _modelsKey='dgpt.models', _activeKey='dgpt.active', _errorsKey='dgpt.errors', _chatKey='dgpt.chat';
  static const secure=FlutterSecureStorage();

  static Future<List<ModelEntry>> models() async {
    final p=await SharedPreferences.getInstance();
    return (p.getStringList(_modelsKey)??[]).map((s)=>ModelEntry.fromJson(jsonDecode(s))).toList();
  }
  static Future<void> saveModels(List<ModelEntry> m) async {
    final p=await SharedPreferences.getInstance();
    await p.setStringList(_modelsKey,m.map((e)=>jsonEncode(e.toJson())).toList());
  }
  static Future<String?> activeId() async => (await SharedPreferences.getInstance()).getString(_activeKey);
  static Future<void> setActive(String? id) async {
    final p=await SharedPreferences.getInstance();
    if(id==null) { await p.remove(_activeKey); } else { await p.setString(_activeKey,id); }
  }
  static Future<void> log(Diagnostic d) async {
    final p=await SharedPreferences.getInstance();
    final list=p.getStringList(_errorsKey)??[];
    list.insert(0,jsonEncode(d.toJson()));
    await p.setStringList(_errorsKey,list.take(150).toList());
  }
  static Future<List<Map<String,dynamic>>> errors() async {
    final p=await SharedPreferences.getInstance();
    return (p.getStringList(_errorsKey)??[]).map((s)=>jsonDecode(s) as Map<String,dynamic>).toList();
  }
  static Future<void> clearErrors() async => (await SharedPreferences.getInstance()).remove(_errorsKey);
  static Future<void> saveChat(List<ChatLine> lines) async {
    final p=await SharedPreferences.getInstance();
    await p.setStringList(_chatKey,lines.map((e)=>jsonEncode(e.toJson())).toList());
  }
  static Future<List<ChatLine>> chat() async {
    final p=await SharedPreferences.getInstance();
    return (p.getStringList(_chatKey)??[]).map((s)=>ChatLine.fromJson(jsonDecode(s))).toList();
  }
  static Future<Directory> modelsDir() async {
    final d=await getApplicationDocumentsDirectory();
    final dir=Directory('${d.path}/dark_gpt_models');
    if(!await dir.exists()) await dir.create(recursive:true);
    return dir;
  }
  static Future<Directory> outputDir() async {
    final d=await getApplicationDocumentsDirectory();
    final dir=Directory('${d.path}/dark_gpt_files');
    if(!await dir.exists()) await dir.create(recursive:true);
    return dir;
  }
}

class ModelManager {
  final Dio dio=Dio(BaseOptions(connectTimeout: const Duration(seconds:25), receiveTimeout: const Duration(minutes:30)));
  Future<String> download(String url,String filename,void Function(int,int) progress) async {
    if(!url.startsWith('https://') && !url.startsWith('http://')) throw Exception('رابط التنزيل غير صالح.');
    final dir=await Store.modelsDir();
    final safe=filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
    final path='${dir.path}/$safe';
    await dio.download(url,path,onReceiveProgress:progress,deleteOnError:true,options:Options(followRedirects:true));
    final f=File(path);
    if(!await f.exists() || await f.length()==0) throw Exception('اكتمل الطلب لكن الملف فارغ أو لم يُحفظ.');
    return path;
  }
  Future<String> importFile() async {
    throw UnimplementedError('استخدم منتقي الملفات في الشاشة لاستيراد GGUF.');
  }
  Future<void> register(String path,String name,int bytes) async {
    final models=await Store.models();
    final exists=models.any((m)=>m.path==path);
    if(exists) return;
    models.add(ModelEntry(id:_uuid.v4(),name:name,path:path,format:'GGUF',bytes:bytes,addedAt:DateTime.now()));
    await Store.saveModels(models);
  }
  Future<void> delete(ModelEntry m) async {
    final f=File(m.path);
    if(await f.exists()) await f.delete();
    final models=await Store.models();
    models.removeWhere((e)=>e.id==m.id);
    await Store.saveModels(models);
    if(await Store.activeId()==m.id) await Store.setActive(null);
  }
}

class ApiConfig {
  final String name,baseUrl,model,key;
  const ApiConfig({required this.name,required this.baseUrl,required this.model,required this.key});
  static Future<ApiConfig?> load() async {
    final p=await SharedPreferences.getInstance();
    final base=p.getString('api.base');
    final model=p.getString('api.model');
    final key=await Store.secure.read(key:'api.key');
    if(base==null||model==null||key==null||key.isEmpty) return null;
    return ApiConfig(name:p.getString('api.name')??'API',baseUrl:base,model:model,key:key);
  }
  static Future<void> save(ApiConfig c) async {
    final p=await SharedPreferences.getInstance();
    await p.setString('api.name',c.name);
    await p.setString('api.base',c.baseUrl);
    await p.setString('api.model',c.model);
    await Store.secure.write(key:'api.key',value:c.key);
  }
  static Future<void> clear() async {
    final p=await SharedPreferences.getInstance();
    await p.remove('api.name'); await p.remove('api.base'); await p.remove('api.model');
    await Store.secure.delete(key:'api.key');
  }
}

class ApiChat {
  final Dio dio=Dio(BaseOptions(connectTimeout: const Duration(seconds:30),receiveTimeout: const Duration(minutes:3)));
  Future<String> send(ApiConfig c,List<ChatLine> history,String prompt) async {
    final url='${c.baseUrl.replaceAll(RegExp(r'/+$'),'')}/chat/completions';
    final messages=[
      {'role':'system','content':'You are Dark GPT, a helpful assistant. Answer in the user language. When asked to create files, provide complete file contents in fenced code blocks and clearly name each file. Never claim to have created or uploaded files unless the app actually did so.'},
      ...history.map((m)=>{'role':m.role,'content':m.text}),
      {'role':'user','content':prompt},
    ];
    final response=await dio.post(url,
      data:{'model':c.model,'messages':messages,'temperature':0.7},
      options:Options(headers:{'Authorization':'Bearer ${c.key}','Content-Type':'application/json'}),
    );
    final data=response.data;
    final choices=data is Map ? data['choices'] : null;
    if(choices is! List || choices.isEmpty) throw Exception('استجابة API لا تحتوي على choices. تحقق من عنوان الخادم واسم النموذج.');
    final msg=choices.first['message'];
    final value=msg is Map ? msg['content'] : null;
    if(value is String) return value;
    throw Exception('لم يرجع المزود نصاً مفهوماً. قد يكون هذا النموذج متعدد الوسائط أو تنسيقه غير متوافق.');
  }
}

class LocalEngine {
  LocalLlmEngine? engine;
  LlmSession? session;
  String? loadedPath;
  Future<void> load(String path) async {
    await unload();
    engine=await LocalLlmEngine.loadModel(
      modelPath:path,
      params: const ModelParams(contextSize:2048,gpuLayers:0),
    );
    session=engine!.createSession(defaultTemplate: const ChatMlTemplate());
    loadedPath=path;
  }
  Future<String> send(List<ChatLine> history,String prompt) async {
    final s=session;
    if(s==null) throw Exception('لم يتم تحميل نموذج محلي بعد.');
    final msgs=<dynamic>[
      ChatMessage.system('You are Dark GPT, a helpful assistant. Answer in the same language as the user.'),
      ...history.map((m)=>m.role=='assistant'?ChatMessage.assistant(m.text):ChatMessage.user(m.text)),
      ChatMessage.user(prompt),
    ];
    final out=StringBuffer();
    await for(final token in s.chat(msgs.cast<ChatMessage>(),params:const SamplingParams(temperature:0.7,topP:0.9,maxTokens:768))) {
      out.write(token);
    }
    return out.toString();
  }
  Future<void> unload() async {
    session?.dispose(); session=null;
    engine?.dispose(); engine=null;
    loadedPath=null;
  }
}

class FileTools {
  static Future<File> createText(String filename,String content) async {
    final dir=await Store.outputDir();
    final safe=filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'),'_');
    final file=File('${dir.path}/$safe');
    await file.writeAsString(content,flush:true);
    return file;
  }
  static Future<File> createZip(Map<String,String> files,String filename) async {
    final archive=Archive();
    for(final e in files.entries) {
      archive.addFile(ArchiveFile(e.key,utf8.encode(e.value).length,utf8.encode(e.value)));
    }
    final bytes=ZipEncoder().encode(archive);
    if(bytes==null) throw Exception('تعذر إنشاء ملف ZIP.');
    final dir=await Store.outputDir();
    final file=File('${dir.path}/$filename');
    await file.writeAsBytes(bytes,flush:true);
    return file;
  }
}
