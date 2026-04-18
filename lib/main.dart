import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:logbook_app_094/features/onboarding/onboarding_view.dart';
import 'package:logbook_app_094/features/logbook/log_view.dart';
import 'package:logbook_app_094/features/logbook/models/log_model.dart';
import 'package:logbook_app_094/services/mongo_service.dart';
import 'package:logbook_app_094/helpers/log_helper.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Verifikasi kamera di perangkat
  try {
    cameras = await availableCameras();
    debugPrint('Jumlah kamera terdeteksi: ${cameras.length}');
  } on CameraException catch (e) {
    debugPrint('Error kamera: ${e.code}\n${e.description}');
  }

  // 1) Load ENV
  await dotenv.load(fileName: ".env");

  // 2) Inisialisasi Hive
  await Hive.initFlutter();
  Hive.registerAdapter(LogModelAdapter());
  await Hive.openBox<LogModel>('offline_logs');

  // 3) Handshake MongoDB
  const source = "main.dart";

  await LogHelper.writeLog(
    "Boot: (Level 3) Mulai proses handshake MongoDB...",
    source: source,
    level: 3,
  );

  try {
    await MongoService().connect();

    await LogHelper.writeLog(
      "Boot: (Level 2) MongoDB CONNECTED ✅",
      source: source,
      level: 2,
    );
  } catch (e) {
    await LogHelper.writeLog(
      "Boot: (Level 1) MongoDB FAILED ❌ -> $e",
      source: source,
      level: 1,
    );
  }

  // 4) Cek status login dari SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

  Map<String, dynamic>? user;

  if (isLoggedIn) {
    user = {
      'uid': prefs.getString('uid') ?? '',
      'username': prefs.getString('username') ?? '',
      'role': prefs.getString('role') ?? '',
      'teamId': prefs.getString('teamId') ?? '',
    };
  }

  runApp(MyApp(user: user));
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic>? user;

  const MyApp({super.key, this.user});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogBook App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7AA7FF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF6F8FF),
          elevation: 0,
          centerTitle: false,
          foregroundColor: Color(0xFF1F2A44),
        ),
      ),
      home: user != null
          ? LogView(currentUser: user!)
          : const OnboardingView(),
    );
  }
}