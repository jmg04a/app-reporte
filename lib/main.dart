import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/splash/splash_screen.dart'; // <-- 1. IMPORTAMOS EL NUEVO SPLASH SCREEN

Future<void> main() async {
  // 1. Aseguramos que el motor de Flutter esté listo
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  // 2. Conectamos con Supabase
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 3. Arrancamos la App
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

      // <-- 2. AHORA LA APP SIEMPRE ABRE PRIMERO EL SPLASH SCREEN
      home: const SplashScreen(), 
    );
  }
}