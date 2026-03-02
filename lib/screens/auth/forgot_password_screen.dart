import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  
  // El mismo dominio que usamos en Login
  static const String _dominio = "@correo.itlalaguna.edu.mx";

  Future<void> _enviarCorreoRecuperacion() async {
    if (_emailController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa tu correo o número de control", esError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. FORMATEAR CORREO (Igual que en Login)
      String input = _emailController.text.trim();
      String emailFinal = input.contains('@') ? input : input + _dominio;

      // 2. ENVIAR SOLICITUD A SUPABASE
      // Esto enviará un email con un enlace para resetear el password
      await Supabase.instance.client.auth.resetPasswordForEmail(
        emailFinal,
        // Opcional: redirectTo: 'io.supabase.tuapp://login-callback',
        // Si no configuras Deep Links, el usuario reseteará en el navegador.
      );

      if (!mounted) return;
      
      // 3. ÉXITO
      _mostrarDialogoExito(emailFinal);

    } on AuthException catch (e) {
      _mostrarMensaje(e.message, esError: true);
    } catch (e) {
      _mostrarMensaje("Error inesperado: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  void _mostrarDialogoExito(String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("📧 Correo Enviado"),
        content: Text(
          "Hemos enviado las instrucciones a:\n$email\n\n"
          "Revisa tu bandeja de entrada (y Spam). El enlace te permitirá crear una nueva contraseña."
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Cierra diálogo
              Navigator.pop(context); // Regresa al Login
            },
            child: const Text("Entendido, ir al Login"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Recuperar Contraseña"),
        backgroundColor: const Color(0xFF800000), // Rojo ITL
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_reset, size: 80, color: Color(0xFF800000)),
            const SizedBox(height: 20),
            
            const Text(
              "¿Olvidaste tu contraseña?",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            
            const Text(
              "Ingresa tu número de control o correo institucional y te enviaremos un enlace para restablecerla.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),

            // CAMPO DE TEXTO
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: "Correo Institucional",
                hintText: "ej. alu.19130095",
                // ESTA ES LA PARTE VISUAL CLAVE:
                suffixText: _dominio, 
                suffixStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 30),

            // BOTÓN
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _enviarCorreoRecuperacion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF800000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("ENVIAR INSTRUCCIONES", style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}