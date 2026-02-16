import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Importa tus pantallas (aunque te marquen error ahorita porque no las has creado)
// Esto se arreglará en el siguiente paso.
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';

Future<void> main() async {
  // 1. Aseguramos que el motor de Flutter esté listo
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  // 2. Conectamos con Supabase (Pega tus claves aquí)
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
      debugShowCheckedModeBanner: false, // Quita la etiqueta "Debug" de la esquina
      
      // Tema Global (Estilo del Tec)
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF800000), // Guinda / Rojo oscuro
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),

      // Lógica de Redirección (El Portero)
      // ¿Existe una sesión guardada en el celular?
      home: supabase.auth.currentSession == null 
          ? const LoginScreen()  // No -> Mándalo a loguearse
          : const HomeScreen(),  // Sí -> Déjalo pasar al feed
    );
  }
}