import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Asegúrate de que estas rutas coincidan con tus carpetas
import '../auth/login_screen.dart'; 
// 1. CAMBIO AQUÍ: Importamos el nuevo MainNavigationScreen en lugar del HomeScreen
import '../home/main_navigation_screen.dart'; 

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _verificarSesion();
  }

  Future<void> _verificarSesion() async {
    // Le damos medio segundo de pausa para que la animación de carga se alcance a ver
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Le preguntamos a Supabase si alguien dejó la sesión abierta
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      // 2. CAMBIO AQUÍ: Lo mandamos al MainNavigationScreen para que aparezcan los botones de abajo
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } else {
      // Si no hay sesión (o la cerró), lo mandamos a iniciar sesión
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF800000), 
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.school, size: 100, color: Colors.white), 
            SizedBox(height: 30),
            CircularProgressIndicator(color: Colors.white), 
            SizedBox(height: 20),
            Text("Cargando sistema...", style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}