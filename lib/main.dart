import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:midp_chatbot/chat_page.dart';


void main() async {
  // اطمینان از مقداردهی اولیه فلاتر
  WidgetsFlutterBinding.ensureInitialized();
  
  // بارگذاری متغیرهای محیطی
  await dotenv.load(fileName: "lib/assets/.env");
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ChatPage(),
    );
  }
}