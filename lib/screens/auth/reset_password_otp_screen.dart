import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart'; 

class ResetPasswordOtpScreen extends StatefulWidget {
  final String email; 

  const ResetPasswordOtpScreen({super.key, required this.email});

  @override
  State<ResetPasswordOtpScreen> createState() => _ResetPasswordOtpScreenState();
}

class _ResetPasswordOtpScreenState extends State<ResetPasswordOtpScreen> {
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _verificarYCambiarPassword() async {
    // ACTUALIZADO: Validación para 8 dígitos
    if (_otpController.text.trim().length != 8) {
      _mostrarMensaje("El código debe ser de 8 dígitos", esError: true);
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _mostrarMensaje("Las contraseñas no coinciden", esError: true);
      return;
    }
    if (_passwordController.text.length < 6) {
      _mostrarMensaje("La contraseña debe tener al menos 6 caracteres", esError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Canjear el código
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.recovery,
        token: _otpController.text.trim(),
        email: widget.email,
      );

      // 2. Actualizar contraseña
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );

      // 3. Cerrar sesión por seguridad
      await Supabase.instance.client.auth.signOut();
      
      if (!mounted) return; 

      _mostrarMensaje("¡Contraseña actualizada con éxito!");
      
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );

    } on AuthException catch (e) {
      if (e.message.contains("Token has expired or is invalid")) {
        _mostrarMensaje("El código es incorrecto o ya expiró.", esError: true);
      } else {
        _mostrarMensaje("Error: ${e.message}", esError: true);
      }
    } catch (e) {
      _mostrarMensaje("Error inesperado: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Ingresar Código"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_read_outlined, size: 80, color: Color(0xFF800000)),
            const SizedBox(height: 20),
            
            const Text(
              "Revisa tu correo",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            
            Text(
              "Enviamos un código de 8 dígitos a:\n${widget.email}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 30),

            // CAMPO ACTUALIZADO A 8 DÍGITOS
            TextField(
              controller: _otpController,
              decoration: const InputDecoration(
                labelText: "Código de 8 dígitos",
                prefixIcon: Icon(Icons.pin_outlined),
                border: OutlineInputBorder(),
                hintText: "Ej. 12345678",
              ),
              keyboardType: TextInputType.number,
              maxLength: 8, // Aumentado a 8
              textAlign: TextAlign.center,
              // Ajusté el letterSpacing a 6 para que quepan bien los 8 números sin desbordarse
              style: const TextStyle(fontSize: 24, letterSpacing: 6, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: "Nueva Contraseña",
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 15),

            TextField(
              controller: _confirmPasswordController,
              decoration: const InputDecoration(
                labelText: "Confirmar Nueva Contraseña",
                prefixIcon: Icon(Icons.lock_reset),
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 30),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton(
                onPressed: _verificarYCambiarPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF800000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("ACTUALIZAR CONTRASEÑA", style: TextStyle(fontSize: 16)),
              ),
          ],
        ),
      ),
    );
  }
}