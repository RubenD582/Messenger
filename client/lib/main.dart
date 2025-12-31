import 'package:client/screens/auth/sign_in_screen.dart';
import 'package:client/screens/auth/forgot_password_screen.dart'; // Import ForgotPasswordScreen
import 'package:client/screens/auth/reset_password_screen.dart';   // Import ResetPasswordScreen
import 'package:client/services/notification_service.dart';
import 'package:client/database/message_database.dart';
import 'package:client/theme/colors.dart';
import 'package:client/theme/typography.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pull_down_button/pull_down_button.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications
  NotificationService.initNotifications();

  // Initialize Hive for local caching
  final appDocumentDir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(appDocumentDir.path);

  // Initialize encrypted message database
  await MessageDatabase.database;

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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.primary,
        colorScheme: ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.primaryLight,
          surface: AppColors.surface,
          error: AppColors.error,
          onPrimary: AppColors.textPrimary,
          onSecondary: AppColors.textPrimary,
          onSurface: AppColors.textPrimary,
          onError: AppColors.textPrimary,
        ),

        // Typography
        textTheme: TextTheme(
          displayLarge: AppTypography.h1,
          displayMedium: AppTypography.h2,
          displaySmall: AppTypography.h3,
          bodyLarge: AppTypography.bodyLarge,
          bodyMedium: AppTypography.body,
          bodySmall: AppTypography.bodySmall,
          labelLarge: AppTypography.button,
          labelMedium: AppTypography.label,
          labelSmall: AppTypography.caption,
        ),
        fontFamily: GoogleFonts.inter().fontFamily,

        // Card theme
        cardColor: AppColors.surfaceVariant,
        cardTheme: CardThemeData(
          color: AppColors.surfaceVariant,
          elevation: 0,
        ),

        // App bar theme
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          titleTextStyle: AppTypography.h3,
        ),

        // Input decoration theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceVariant,
          focusColor: AppColors.primary,
          hoverColor: AppColors.primary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 2),
          ),
        ),

        // Button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.buttonPrimary,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTypography.button,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            splashFactory: InkRipple.splashFactory,
            textStyle: AppTypography.button,
          ),
        ),

        // Icon theme
        iconTheme: IconThemeData(
          color: AppColors.textPrimary,
        ),

        // Ripple/highlight
        highlightColor: AppColors.ripple,
        splashColor: AppColors.ripple,

        extensions: [
          PullDownButtonTheme(
            routeTheme: PullDownMenuRouteTheme(
              backgroundColor: AppColors.surface,
            ),
            itemTheme: PullDownMenuItemTheme(
              textStyle: AppTypography.body,
            ),
            dividerTheme: PullDownMenuDividerTheme(
              dividerColor: AppColors.textTertiary.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
      initialRoute: '/',
      onGenerateRoute: (settings) {
        if (settings.name == '/reset-password') {
          String? token;
          // Try to get token from arguments first (for internal navigation)
          if (settings.arguments is String) {
            token = settings.arguments as String;
          } else {
            // For deep links (web), try to get from Uri.base
            final uri = Uri.parse(Uri.base.toString());
            token = uri.queryParameters['token'];
          }
          return MaterialPageRoute(builder: (context) => ResetPasswordScreen(token: token));
        }
        // Default route
        return MaterialPageRoute(builder: (context) => const SignInScreen());
      },
    );
  }
}
