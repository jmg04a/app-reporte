import 'dart:io'; 
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:window_manager/window_manager.dart'; 

// --- IMPORTA TUS PANTALLAS (Ajusta las rutas si es necesario) ---
import 'screens/splash/splash_screen.dart'; 
import 'screens/reportes/filter_screen.dart'; 
import 'screens/reportes/create_report_screen.dart'; 

// =======================================================
// CONTROLES REMOTOS GLOBALES
// =======================================================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<int> globalTabIndex = ValueNotifier<int>(0); // 0 = Home, 3 = Perfil

// =======================================================
// ¡NUEVO! FUNCIÓN EXPERTA PARA NAVEGACIÓN GLOBAL SEGURA
// =======================================================
void _abrirPantallaGlobal(String nombreRuta, Widget pantalla) {
  bool yaEstaEnTop = false;
  
  // 1. Revisamos qué pantalla está hasta arriba en este instante
  navigatorKey.currentState?.popUntil((route) {
    yaEstaEnTop = route.settings.name == nombreRuta;
    return true; // Retornar true hace que no cierre nada, solo es para espiar
  });

  // 2. Si ya estamos exactamente en esa pantalla, la dejamos en paz
  if (yaEstaEnTop) return;

  // 3. Si estábamos en OTRA pantalla secundaria, limpiamos la pila 
  // cerrando todo hasta llegar a la base (MainNavigationScreen)
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
  
  // 4. Ahora sí, abrimos la pantalla solicitada sobre una base limpia
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      settings: RouteSettings(name: nombreRuta),
      builder: (_) => pantalla
    )
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuración de ventana (Windows/Mac/Linux)
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

  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Detección de sistema operativo para atajos (Cmd vs Ctrl)
    final bool isMac = !kIsWeb && Platform.isMacOS;

    return CallbackShortcuts(
      bindings: {
        // 1. ESCAPE: Retroceder
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (navigatorKey.currentState?.canPop() == true) {
            navigatorKey.currentState?.pop();
          }
        },

        // 2. BUSCAR: Ctrl + F o Cmd + F
        SingleActivator(LogicalKeyboardKey.keyF, control: !isMac, meta: isMac): () {
          _abrirPantallaGlobal('/buscar', const FilterScreen());
        },

        // 3.  BUSCAR Alternativo: Ctrl + K o Cmd + K 
        SingleActivator(LogicalKeyboardKey.keyK, control: !isMac, meta: isMac): () {
          _abrirPantallaGlobal('/buscar', const FilterScreen());
        },

        // 4. CREAR NUEVO: Ctrl + N o Cmd + N
        SingleActivator(LogicalKeyboardKey.keyN, control: !isMac, meta: isMac): () {
          _abrirPantallaGlobal('/crear_reporte', const CreateReportScreen());
        },
        // 5. INICIO (HOME): Ctrl + H o Cmd + H
        SingleActivator(LogicalKeyboardKey.keyH, control: !isMac, meta: isMac): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst); 
          globalTabIndex.value = 0; // Cambiamos la pestaña
        },
        
        // 5. INICIO Alternativo: Ctrl + 1 o Cmd + 1
        SingleActivator(LogicalKeyboardKey.digit1, control: !isMac, meta: isMac): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 0; 
        },

        // 6. PERFIL: Ctrl + P o Cmd + P
        SingleActivator(LogicalKeyboardKey.keyP, control: !isMac, meta: isMac): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 3; // Cambiamos la pestaña
        },
        
        // 6. PERFIL Alternativo: Ctrl + , o Cmd + ,
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