import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Map<String, dynamic>> _sessions = [{"first_query": null, "history": []}];
  int _currentSessionIndex = 0;
  int? _editingQueryIndex;
  String? _fileContent;
  String? _fileName;
  
  // کلید API گراک از متغیرهای محیطی
  String? _groqApiKey;
  // مدل انتخاب شده - پیش‌فرض Llama3-8b-8192
  String _selectedModel = 'Llama3-8b-8192';
  
  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadApiKey();
  }
  
  // بارگذاری کلید API از متغیرهای محیطی
  void _loadApiKey() {
    _groqApiKey = dotenv.env['groq_api_key'] ?? '';
    if (_groqApiKey!.isEmpty) {
      // نمایش پیام خطا اگر کلید API تنظیم نشده باشد
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('کلید API گراک یافت نشد. لطفاً فایل .env را تنظیم کنید.')),
        );
      });
    }
  }
  
  // بارگذاری جلسات ذخیره شده از حافظه محلی
  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String sessionsJson = prefs.getString('chat_sessions') ?? '';
    
    if (sessionsJson.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(sessionsJson);
        setState(() {
          _sessions = decoded.map((session) => Map<String, dynamic>.from(session)).toList();
        });
      } catch (e) {
        print('خطا در بارگذاری جلسات: $e');
        // مقداردهی اولیه با داده‌های پیش‌فرض در صورت شکست بارگذاری
        setState(() {
          _sessions = [{"first_query": null, "history": []}];
        });
      }
    }
  }
  
  // ذخیره جلسات در حافظه محلی
  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String sessionsJson = jsonEncode(_sessions);
    await prefs.setString('chat_sessions', sessionsJson);
  }
  
  // انتخاب فایل (PDF یا TXT)
  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt'],
    );
    
    if (result != null) {
      final path = result.files.single.path!;
      final extension = path.split('.').last.toLowerCase();
      
      setState(() {
        _fileName = result.files.single.name;
      });
      
      if (extension == 'pdf') {
        _readPdfFile(path);
      } else if (extension == 'txt') {
        _readTextFile(path);
      }
    }
  }
  
  // خواندن محتوای فایل PDF با استفاده از Syncfusion
  Future<void> _readPdfFile(String path) async {
    try {
      // خواندن فایل به صورت بایت‌ها
      final File file = File(path);
      final Uint8List bytes = await file.readAsBytes();
      
      // بارگذاری سند PDF
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      // ایجاد استخراج‌کننده متن PDF
      PdfTextExtractor textExtractor = PdfTextExtractor(document);
      
      // استخراج متن از تمام صفحات
      String text = '';
      for (int i = 0; i < document.pages.count; i++) {
        text += textExtractor.extractText(startPageIndex: i) + '\n';
      }
      
      // آزادسازی منابع سند
      document.dispose();
      
      setState(() {
        _fileContent = text;
      });
    } catch (e) {
      print('خطا در خواندن PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در خواندن فایل PDF: $e')),
      );
    }
  }
  
  // خواندن محتوای فایل متنی
  Future<void> _readTextFile(String path) async {
    try {
      final File file = File(path);
      final String contents = await file.readAsString();
      
      setState(() {
        _fileContent = contents;
      });
    } catch (e) {
      print('خطا در خواندن فایل متنی: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در خواندن فایل متنی: $e')),
      );
    }
  }
  
  // ارسال پیام به API گراک و دریافت پاسخ
  Future<String> _getGroqResponse(String userInput) async {
    if (_groqApiKey == null || _groqApiKey!.isEmpty) {
      return 'خطا: کلید API گراک تنظیم نشده است.';
    }
    
    final currentSession = _sessions[_currentSessionIndex];
    
    // آماده‌سازی تاریخچه گفتگو
    List<Map<String, String>> conversationHistory = [];
    
    // افزودن پیام‌های قبلی از تاریخچه
    for (var entry in currentSession['history']) {
      conversationHistory.add({"role": "user", "content": entry["query"]});
      conversationHistory.add({"role": "assistant", "content": entry["response"]});
    }
    
    // افزودن محتوای فایل در صورت وجود
    if (_fileContent != null) {
      conversationHistory.add({"role": "system", "content": "محتوای فایل: $_fileContent"});
    }
    
    // افزودن پیام فعلی کاربر
    conversationHistory.add({"role": "user", "content": userInput});
    
    try {
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_groqApiKey',
        },
        body: jsonEncode({
          'model': _selectedModel,
          'messages': conversationHistory,
        }),
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'];
      } else {
        print('خطا از API گراک: ${response.body}');
        return 'خطا: عدم دریافت پاسخ از گراک (وضعیت ${response.statusCode})';
      }
    } catch (e) {
      print('استثنا در هنگام فراخوانی API گراک: $e');
      return 'خطا: $e';
    }
  }
  
  // ارسال پیام جدید یا ویرایش پیام موجود
  Future<void> _handleSubmit(String userInput, {bool isEdit = false}) async {
    if (userInput.isEmpty) return;
    
    // دریافت پاسخ از API گراک
    final response = await _getGroqResponse(userInput);
    
    setState(() {
      if (isEdit && _editingQueryIndex != null) {
        // ویرایش پیام موجود
        _sessions[_currentSessionIndex]['history'][_editingQueryIndex!] = {
          "query": userInput,
          "response": response
        };
        _editingQueryIndex = null;
      } else {
        // افزودن پیام جدید
        _sessions[_currentSessionIndex]['history'].add({
          "query": userInput,
          "response": response
        });
        
        // تنظیم اولین پرسش اگر این اولین پیام است
        if (_sessions[_currentSessionIndex]['first_query'] == null) {
          _sessions[_currentSessionIndex]['first_query'] = userInput;
        }
      }
    });
    
    _textController.clear();
    await _saveSessions();
    
    // اسکرول به پایین
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  // ایجاد جلسه جدید
  void _createNewSession() {
    setState(() {
      _sessions.add({"first_query": null, "history": []});
      _currentSessionIndex = _sessions.length - 1;
    });
    _saveSessions();
  }
  
  // تغییر به جلسه دیگر
  void _switchSession(int index) {
    setState(() {
      _currentSessionIndex = index;
      _editingQueryIndex = null;
    });
  }
  
  // پاک کردن همه جلسات
  void _clearSessions() {
    setState(() {
      _sessions = [{"first_query": null, "history": []}];
      _currentSessionIndex = 0;
      _editingQueryIndex = null;
    });
    _saveSessions();
  }
  
  // کوتاه کردن متن طولانی
  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = _sessions[_currentSessionIndex];
    final history = currentSession['history'] as List;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDP-Bot by Nawid Fadai',style: TextStyle(fontSize: 10),),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewSession,
            tooltip: 'جلسه جدید',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text('جلسات', style: TextStyle(color: Colors.white, fontSize: 24)),
            ),
            // لیست همه جلسات
            for (int i = 0; i < _sessions.length; i++)
              ListTile(
                title: Text(_truncateText(_sessions[i]['first_query'] ?? 'جلسه ${i + 1}', 40)),
                selected: i == _currentSessionIndex,
                onTap: () {
                  _switchSession(i);
                  Navigator.pop(context);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('پاک کردن همه جلسات'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('تایید'),
                    content: const Text('آیا مطمئن هستید که می‌خواهید همه جلسات را پاک کنید؟'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('لغو'),
                      ),
                      TextButton(
                        onPressed: () {
                          _clearSessions();
                          Navigator.pop(context);
                        },
                        child: const Text('بله'),
                      ),
                    ],
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('آپلود فایل'),
              subtitle: _fileName != null ? Text(_fileName!) : null,
              onTap: () {
                Navigator.pop(context);
                _pickFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('تنظیمات مدل'),
              onTap: () {
                Navigator.pop(context);
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('انتخاب مدل گراک'),
                    content: DropdownButton<String>(
                      value: _selectedModel,
                      items: [
                        'Llama3-8b-8192',
                        'Llama3-70b-8192',
                        'Mixtral-8x7b-32768',
                        'Gemma-7b-It'
                      ].map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedModel = newValue;
                          });
                        }
                        Navigator.pop(context);
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // تاریخچه چت
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: history.length,
                padding: const EdgeInsets.all(8.0),
                itemBuilder: (context, index) {
                  final item = history[index];
                  
                  if (index == _editingQueryIndex) {
                    // نمایش رابط ویرایش اگر این پیام در حال ویرایش است
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: TextEditingController(text: item['query']),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'ویرایش پیام شما',
                            ),
                            maxLines: null,
                            onSubmitted: (value) {
                              _handleSubmit(value, isEdit: true);
                            },
                          ),
                          ButtonBar(
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _editingQueryIndex = null;
                                  });
                                },
                                child: const Text('لغو'),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  final controller = TextEditingController.fromValue(
                                    TextEditingValue(text: item['query']),
                                  );
                                  _handleSubmit(controller.text, isEdit: true);
                                },
                                child: const Text('ذخیره'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  } else {
                    // نمایش رابط پیام عادی
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // پیام کاربر
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, size: 16),
                              onPressed: () {
                                setState(() {
                                  _editingQueryIndex = index;
                                });
                              },
                            ),
                            Flexible(
                              child: Container(
                                margin: const EdgeInsets.all(8.0),
                                padding: const EdgeInsets.all(12.0),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(item['query']),
                              ),
                            ),
                            CircleAvatar(
                              backgroundColor: Colors.blue[300],
                              child: const Icon(Icons.person, color: Colors.white),
                            ),
                          ],
                        ),
                        
                        // پاسخ ربات
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.grey[300],
                              child: const Icon(Icons.smart_toy, color: Colors.black),
                            ),
                            Flexible(
                              child: Container(
                                margin: const EdgeInsets.all(8.0),
                                padding: const EdgeInsets.all(12.0),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(item['response']),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }
                },
              ),
            ),
            
            // بخش ورودی پیام
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'سوال خود را بپرسید...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (text) {
                        if (text.isNotEmpty) {
                          _handleSubmit(text);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      if (_textController.text.isNotEmpty) {
                        _handleSubmit(_textController.text);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
