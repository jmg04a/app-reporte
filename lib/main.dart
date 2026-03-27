import 'dart:io'; // Para saber si estamos en PC o Celular
import 'package:flutter/foundation.dart'; // Para saber si estamos en Web
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:window_manager/window_manager.dart'; // IMPORT DE VENTANAS
import 'screens/splash/splash_screen.dart'; 

Future<void> main() async {
  // 1. Aseguramos que el motor de Flutter esté listo
  WidgetsFlutterBinding.ensureInitialized();

  // =======================================================
  // 2. CONFIGURACIÓN DE VENTANA (SOLO PARA WINDOWS/MAC/LINUX)
  // =======================================================
  // Verificamos que no estemos en Web y que estemos en una PC de escritorio
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();

    WindowOptions windowOptions = const WindowOptions(
      size: Size(900, 860),         // Tamaño por DEFAULT al abrir
      minimumSize: Size(600, 700),   // Tamaño MÍNIMO permitido
      center: true,                  // Centrado en el monitor
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
  // =======================================================

  // 3. Cargamos las variables de entorno
  await dotenv.load(fileName: ".env");

  // 4. Conectamos con Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 5. Arrancamos la App
  runApp(const MyApp());
}

// Variable global para usar 'supabase' en cualquier lado de la app fácilmente
final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reportes ITL',
      debugShowCheckedModeBanner: false, 
      
      // Tema Global (Estilo del Tec)
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF800000), // Guinda / Rojo oscuro
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),

      // LA APP SIEMPRE ABRE PRIMERO EL SPLASH SCREEN
      home: const SplashScreen(), 
    );
  }
}