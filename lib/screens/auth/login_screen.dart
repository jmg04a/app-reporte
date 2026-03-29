import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/main_navigation_screen.dart';
import '../auth/register_screen.dart';
import '../auth/recovery_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Entry point for user authentication.
/// 
/// Handles credential validation via Supabase Auth and implements 
/// a domain-completion UX strategy for the institutional email.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuarioController = TextEditingController(); 
  final _passwordController = TextEditingController();
  
  /// Institutional domain suffix appended automatically if the user omits it.
  static const String _dominio = "@correo.itlalaguna.edu.mx";

  bool _isLoading = false;

  /// Displays transient UI feedback for authentication errors.
  /// 
  /// Guarded with [mounted] check to prevent exceptions if the widget 
  /// is disposed before the SnackBar can be rendered.
  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  /// Orchestrates the sign-in flow.
  /// 
  /// 1. Sanitizes user input and handles domain completion.
  /// 2. Authenticates via Supabase Auth.
  /// 3. Prefetches user metadata into SharedPreferences for offline availability.
  /// 4. Routes to the main application shell upon success.
  Future<void> _iniciarSesion() async {
    setState(() => _isLoading = true);
    try {
      final inputUsuario = _usuarioController.text.trim();

      // UX Optimization: Automatically append the institutional domain if the 
      // user only inputs their username/control number.
      final emailCompleto = inputUsuario.contains('@') 
      ? inputUsuario 
      : inputUsuario + _dominio; 

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailCompleto,
        password: _passwordController.text,
      );

      // Prefetch user profile data before routing to prevent layout shifts 
      // or "loading" states on the subsequent screens.
      await _guardarPerfilEnCache(response.user!.id);

      if (!mounted) return;
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => const MainNavigationScreen())
      );
      
    } on AuthException catch (e) {
      // Map Supabase generic errors to user-friendly Spanish messages.
      if (e.message.contains("Email not confirmed")) {
        _mostrarError("¡Aún no confirmas tu correo! Revisa tu bandeja.");
      } else if (e.message.contains("Invalid login credentials")) {
        _mostrarError("Usuario o contraseña incorrectos.");
      } else {
        _mostrarError(e.message); 
      }
    } catch (e) {
      _mostrarError("Error inesperado: $e"); 
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Downloads essential user metadata from the 'perfiles' table and persists 
  /// it locally using SharedPreferences.
  Future<void> _guardarPerfilEnCache(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Perform a join with 'estudiantes' to fetch the control number if applicable.
      final perfil = await supabase
          .from('perfiles')
          .select('nombre, avatar_url, estudiantes(numero_control)')
          .eq('id', userId)
          .single();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('usuario_perfil', jsonEncode(perfil));
    } catch (e) {
      // Silent fail: If cache fails, the ProfileScreen is built to fetch fresh data anyway.
      debugPrint("Error guardando caché del perfil: $e");
    }
  }

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.school, size: 80, color: Color(0xFF800000)),
              const SizedBox(height: 20),
              const Text(
                "Reportes ITL",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              TextField(
                controller: _usuarioController,
                decoration: const InputDecoration(
                  labelText: "Correo Institucional",
                  hintText: "ej. alu.20310092", 
                  helperText: "Se agregará automáticamente @correo.itlalaguna.edu.mx",
                  helperStyle: TextStyle(color: Colors.black54),
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text, 
              ),
              
              const SizedBox(height: 20),

              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: "Contraseña",
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              
              const SizedBox(height: 10),

              // Password recovery flow entry point.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    final correoEscrito = _usuarioController.text.trim();
                    
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RecoveryScreen(initialEmail: correoEscrito),
                      ),
                    );
                  },
                  child: const Text(
                    "¿Olvidaste tu contraseña?",
                    style: TextStyle(color: Color(0xFF800000), fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              if (_isLoading)
                const CircularProgressIndicator(color: Color(0xFF800000))
              else
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: _iniciarSesion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF800000),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("INICIAR SESIÓN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 15),
                    
                    OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterScreen()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF800000),
                        side: const BorderSide(color: Color(0xFF800000)),
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("Registrarse (Crear Cuenta)", style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}