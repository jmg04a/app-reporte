import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/main_navigation_screen.dart';
import '../auth/register_screen.dart';
import '../auth/recovery_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // 1. CAMBIAMOS EL NOMBRE: Ya no es emailController, es usuarioController
  final _usuarioController = TextEditingController(); 
  final _passwordController = TextEditingController();
  
  // 2. CONSTANTE DEL DOMINIO: Para no escribirla mal nunca
  static const String _dominio = "@correo.itlalaguna.edu.mx";

  bool _isLoading = false;

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  // LOGICA DE LOGIN
Future<void> _iniciarSesion() async {
    setState(() => _isLoading = true);
    try {

      // 1. Obtienes lo que escribió el usuario limpio
      final inputUsuario = _usuarioController.text.trim();

      // 2. Decides inteligentemente
      final emailCompleto = inputUsuario.contains('@') 
      ? inputUsuario 
      : inputUsuario + _dominio; 

      // 3. Intentamos iniciar sesión
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailCompleto,
        password: _passwordController.text,
      );

      // 4. ¡NUEVO! Guardamos el caché ANTES de revisar si la pantalla sigue viva
      // Así aseguramos que el perfil se guarde pase lo que pase.
      await _guardarPerfilEnCache(response.user!.id);

      // 5. AHORA SÍ: Revisamos si el usuario no cerró la app mientras descargábamos
      if (mounted) { 
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const MainNavigationScreen())
        );
      }
      
    } on AuthException catch (e) {
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

  Future<void> _guardarPerfilEnCache(String userId) async {
  try {
    final supabase = Supabase.instance.client;
    
    final perfil = await supabase
        .from('perfiles')
        .select('nombre, avatar_url, estudiantes(numero_control)')
        .eq('id', userId)
        .single();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usuario_perfil', jsonEncode(perfil));
  } catch (e) {
    debugPrint("Error guardando caché del perfil: $e");
  }
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
                "PlaceHolderTitle",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              // CAMPO USUARIO (MEJORADO)
              TextField(
                controller: _usuarioController,
                decoration: InputDecoration(
                  labelText: "Correo Institucional",
                  hintText: "ej. alu.20310092", // Ejemplo corto
                  
                  helperText: "Se agregará automáticamente @correo.itlalaguna.edu.mx",
                  helperStyle: TextStyle(color: Colors.black54),
                  
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text, // Ya no es emailAddress, es texto normal
              ),
              
              const SizedBox(height: 20),

              // CAMPO PASSWORD
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: "Contraseña",
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 30),

              const SizedBox(height: 10),

              // BOTÓN DE "OLVIDÉ MI CONTRASEÑA"
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // Extraemos el texto que el usuario haya escrito
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
                const CircularProgressIndicator()
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
                      child: const Text("INICIAR SESIÓN", style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(height: 15),
                    
                    // Botón de registro secundario
                    OutlinedButton(
                      onPressed: () {
                        // NAVEGACIÓN A LA PANTALLA DE REGISTRO
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => RegisterScreen()),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                          // ... tus estilos
                      ),
                      child: const Text("Registrarse (Crear Cuenta)"),
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