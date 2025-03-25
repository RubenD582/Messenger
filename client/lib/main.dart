import 'package:client/screens/sign_in.dart';
import 'package:client/services/notification_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pull_down_button/pull_down_button.dart';

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
        brightness: Brightness.dark, // Enable global dark mode
        primaryColor: Colors.blue, // Set primary color to blue for buttons, etc.
        hintColor: Colors.blue, // Set accent color to blue (this might be used for some UI elements)
        cardColor: Colors.blue, // Set the default cursor color to blue
        highlightColor: Colors.white.withAlpha(10),
        inputDecorationTheme: InputDecorationTheme(
          focusColor: Colors.blue, // Set color when the field is focused
          hoverColor: Colors.blue, // Set color when hovering over the text field
        ),
        buttonTheme: ButtonThemeData(
          buttonColor: Colors.blue, // Set default button color to blue
          textTheme: ButtonTextTheme.primary, // Make text in the button white when the button is blue
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            splashFactory: InkRipple.splashFactory,
          ),
        ),

        extensions: [
          PullDownButtonTheme(
            routeTheme: PullDownMenuRouteTheme(
              backgroundColor: CupertinoColors.systemFill.darkElevatedColor, // Frosted glass effect
            ),
            itemTheme: PullDownMenuItemTheme(
              textStyle: TextStyle(color: Colors.white), // White text
            ),
            dividerTheme: PullDownMenuDividerTheme(
              dividerColor: Colors.white24, // Subtle translucent divider
            ),
          ),
        ],
      ),
      home: const SignInScreen(),
    );
  }
}
