import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart'; 
import '../home/main_navigation_screen.dart'; 

/// Pantalla inicial de carga y resolución de sesión.
///
/// Muestra la identidad visual de la aplicación (branding) mientras verifica 
/// la existencia de un token de autenticación activo en Supabase para 
/// determinar el flujo de enrutamiento inicial del usuario.
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

  /// Evalúa el estado actual de la autenticación del usuario.
  ///
  /// Introduce un retraso artificial para evitar parpadeos en la interfaz 
  /// (UI flickering) en dispositivos rápidos, asegurando que la pantalla de 
  /// carga sea visible. Navega hacia [MainNavigationScreen] si existe una sesión 
  /// válida; de lo contrario, redirige a [LoginScreen].
  Future<void> _verificarSesion() async {
    // Retraso artificial por motivos de experiencia de usuario (UX) y branding.
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Recupera la sesión activa desde el cliente local GoTrue de Supabase.
    final session = Supabase.instance.client.auth.currentSession;

    if (session != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } else {
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