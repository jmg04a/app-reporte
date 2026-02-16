import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/home_screen.dart';

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
      final emailCompleto = _usuarioController.text.trim() + _dominio;

      // Intentamos iniciar sesión
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailCompleto,
        password: _passwordController.text,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const HomeScreen())
        );
      }
      
    // AQUI ES DONDE VA TU NUEVO CODIGO (Reemplaza el catch anterior)
    // -------------------------------------------------------
    } on AuthException catch (e) {
      if (e.message.contains("Email not confirmed")) {
        _mostrarError("¡Aún no confirmas tu correo! Revisa tu bandeja.");
      } else if (e.message.contains("Invalid login credentials")) {
        _mostrarError("Usuario o contraseña incorrectos.");
      } else {
        _mostrarError(e.message); // Otro error de Supabase
      }
    // -------------------------------------------------------

    } catch (e) {
      _mostrarError("Error inesperado: $e"); // Error de código o internet
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // LOGICA DE REGISTRO
Future<void> _registrarse() async {
    setState(() => _isLoading = true);
    try {
      final emailCompleto = _usuarioController.text.trim() + _dominio;

      // 1. Enviamos el registro a Supabase
      // Como activaste "Confirm Email", esto enviará el correo automáticamente
      final response = await Supabase.instance.client.auth.signUp(
        email: emailCompleto,
        password: _passwordController.text,
      );

      // 2. Verificamos si Supabase nos pide confirmación
      // Si la sesión es nula, significa que requiere verificación
      if (response.session == null && mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("✉️ Verificación Enviada"),
            content: Text(
              "Hemos enviado un enlace a:\n$emailCompleto\n\n"
              "Por favor, revisa tu correo institucional y haz clic en el enlace para activar tu cuenta."
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Entendido"),
              ),
            ],
          ),
        );
      } else if (mounted) {
        // Si por alguna razón entra directo (ej. desactivaste la confirmación luego)
         Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => const HomeScreen())
        );
      }
    } on AuthException catch (e) {
      _mostrarError(e.message);
    } catch (e) {
      _mostrarError("Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                "Reportes ITL",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              // CAMPO USUARIO (MEJORADO)
              TextField(
                controller: _usuarioController,
                decoration: InputDecoration(
                  labelText: "Usuario / No. Control",
                  hintText: "ej. alu.20310092", // Ejemplo corto
                  
                  // ESTA ES LA PARTE VISUAL CLAVE:
                  suffixText: _dominio, 
                  suffixStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                  
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
                      onPressed: _registrarse,
                      style: OutlinedButton.styleFrom(
                         minimumSize: const Size(double.infinity, 50),
                         side: const BorderSide(color: Color(0xFF800000)),
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text("Registrarse (Crear Cuenta)", style: TextStyle(color: Color(0xFF800000))),
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