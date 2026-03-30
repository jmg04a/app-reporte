import 'dart:io'; 
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:window_manager/window_manager.dart'; 

import 'screens/splash/splash_screen.dart'; 
import 'screens/reportes/filter_screen.dart'; 
import 'screens/reportes/create_report_screen.dart'; 

/// Global configuration states.
/// [navigatorKey] provides global access to the NavigatorState for imperative routing outside the widget tree.
/// [globalTabIndex] manages the state of the BottomNavigationBar across the application.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<int> globalTabIndex = ValueNotifier<int>(0);

/// Pushes a new route globally while preventing duplicate stacking.
///
/// Evaluates the current navigation stack and pops intermediate routes
/// to maintain a shallow stack depth and prevent memory bloat.
void _abrirPantallaGlobal(String nombreRuta, Widget pantalla) {
  bool isAlreadyOnTop = false;
  
  // Inspect the top-most route without mutating the navigation stack.
  navigatorKey.currentState?.popUntil((route) {
    isAlreadyOnTop = route.settings.name == nombreRuta;
    return true; 
  });

  // Abort if the target route is already actively displayed.
  if (isAlreadyOnTop) return;

  // Clear intermediate secondary routes to return to the root MainNavigationScreen.
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
  
  // Push the target route with its respective RouteSettings for future state checks.
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      settings: RouteSettings(name: nombreRuta),
      builder: (_) => pantalla
    )
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PaintingBinding.instance.imageCache.maximumSize = 20; // Max of 20 load pictures to ram 
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 15; // 15 MB as maximum 

  // Desktop platform window initialization.
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(900, 860),         
      minimumSize: Size(600, 700),   
      center: true,                  
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: "Reportes ITL",         
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Environment variables initialization.
  await dotenv.load(fileName: "assets/.env");

  // Supabase BaaS initialization.
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

// Singleton instance of the Supabase client.
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Platform check to assign correct hardware modifier keys (Meta for macOS, Control otherwise).
    final bool isMac = !kIsWeb && Platform.isMacOS;

    return CallbackShortcuts(
      bindings: {
        // Unmount current route.
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (navigatorKey.currentState?.canPop() == true) {
            navigatorKey.currentState?.pop();
          }
        },

        // Trigger global search view.
        SingleActivator(LogicalKeyboardKey.keyF, control: !isMac, meta: isMac): () {
          _abrirPantallaGlobal('/buscar', const FilterScreen());
        },
        SingleActivator(LogicalKeyboardKey.keyK, control: !isMac, meta: isMac): () {
          _abrirPantallaGlobal('/buscar', const FilterScreen());
        },

        // Trigger report creation view.
        SingleActivator(LogicalKeyboardKey.keyN, control: !isMac, meta: isMac): () {
          _abrirPantallaGlobal('/crear_reporte', const CreateReportScreen());
        },

        // Navigate to root stack (Home).
        SingleActivator(LogicalKeyboardKey.keyH, control: !isMac, meta: isMac): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst); 
          globalTabIndex.value = 0; 
        },
        SingleActivator(LogicalKeyboardKey.digit1, control: !isMac, meta: isMac): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 0; 
        },

        // Navigate to root stack (Profile).
        SingleActivator(LogicalKeyboardKey.keyP, control: !isMac, meta: isMac): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 3; 
        },
        SingleActivator(LogicalKeyboardKey.comma, control: !isMac, meta: isMac): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 3; 
        },
      },
      child: Focus(
        autofocus: true, 
        child: MaterialApp(
          navigatorKey: navigatorKey, 
          title: 'Reportes ITL',
          debugShowCheckedModeBanner: false, 
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF800000), 
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: const SplashScreen(), 
        ),
      ),
    );
  }
}