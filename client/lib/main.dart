import 'package:client/screens/sign_in.dart';
import 'package:client/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  NotificationService.initNotifications();

  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Messenger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // Global text style with system font (San Francisco on iOS)
        textTheme: Theme.of(context).textTheme.apply(
          fontFamily: 'San Francisco',
        ),
      ),
      home: const SignInScreen(),
    );
  }
}
