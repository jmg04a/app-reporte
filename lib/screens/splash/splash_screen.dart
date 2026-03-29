import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart'; 
import '../home/main_navigation_screen.dart'; 

/// Initial application entry point for session resolution.
///
/// Displays a branding screen while verifying the presence of an active 
/// Supabase authentication token to determine the initial routing flow.
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

  /// Evaluates the current authentication state.
  ///
  /// Introduces an artificial delay to prevent UI flickering on fast devices, 
  /// ensuring the branding is visible. Routes to [MainNavigationScreen] if 
  /// a valid session exists, otherwise redirects to [LoginScreen].
  Future<void> _verificarSesion() async {
    // Artificial delay for UX/branding purposes.
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // Retrieve active session from the local Supabase GoTrue client.
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