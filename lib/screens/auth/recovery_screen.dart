import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();

  int _pasoActual = 1; // 1: Email, 2: Token, 3: Nueva Password
  bool _isLoading = false;

  void _mostrarMensaje(String msg, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  // PASO 1: Enviar el código al correo
  Future<void> _enviarCodigo() async {
    setState(() => _isLoading = true);
    try {
      final email = "${_emailController.text.trim()}@correo.itlalaguna.edu.mx";
      
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      
      _mostrarMensaje("Código enviado. Revisa tu correo.");
      setState(() => _pasoActual = 2); // Avanzamos al siguiente paso
    } on AuthException catch (e) {
      _mostrarMensaje(e.message, esError: true);
    } catch (e) {
      _mostrarMensaje("Error: $e", esError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // PASO 2: Verificar el código
  Future<void> _verificarCodigo() async {
    setState(() => _isLoading = true);
    try {
      final email = "${_emailController.text.trim()}@correo.itlalaguna.edu.mx";
      
      // Esto inicia sesión temporalmente si el código es correcto
      await Supabase.instance.client.auth.verifyOTP(
        token: _tokenController.text.trim(),
        type: OtpType.recovery,
        email: email,
      );

      _mostrarMensaje("Código correcto. Ingresa tu nueva contraseña.");
      setState(() => _pasoActual = 3); // Avanzamos al paso final
    } on AuthException catch (_) {
      _mostrarMensaje("Código inválido o expirado", esError: true);
    } catch (e) {
      _mostrarMensaje("Error: $e", esError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // PASO 3: Guardar la nueva contraseña
  Future<void> _actualizarPassword() async {
    setState(() => _isLoading = true);
    try {
      // Como verifyOTP ya nos inició sesión, podemos actualizar el usuario directamente
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );

      if (mounted) {
        _mostrarMensaje("¡Contraseña actualizada! Inicia sesión.");
        Navigator.pop(context); // Regresamos al Login
      }
    } on AuthException catch (e) {
      _mostrarMensaje(e.message, esError: true);
    } catch (e) {
      _mostrarMensaje("Error: $e", esError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Recuperar Cuenta")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // BARRA DE PROGRESO VISUAL
            Row(
              children: [
                _buildStep(1, "Correo"),
                const Expanded(child: Divider()),
                _buildStep(2, "Código"),
                const Expanded(child: Divider()),
                _buildStep(3, "Password"),
              ],
            ),
            const SizedBox(height: 40),

            // FORMULARIOS DINÁMICOS SEGÚN EL PASO
            if (_pasoActual == 1) ...[
              const Text("Ingresa tu usuario para recibir un código."),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Usuario / No. Control",
                  suffixText: "@correo.itlalaguna.edu.mx",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _enviarCodigo,
                child: _isLoading ? const CircularProgressIndicator() : const Text("ENVIAR CÓDIGO"),
              ),
            ],

            if (_pasoActual == 2) ...[
              const Text("Revisa tu correo e ingresa el código de 6 dígitos."),
              const SizedBox(height: 20),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: "Código (Token)",
                  hintText: "123456",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _verificarCodigo,
                child: _isLoading ? const CircularProgressIndicator() : const Text("VERIFICAR"),
              ),
            ],

            if (_pasoActual == 3) ...[
              const Text("¡Casi listo! Crea tu nueva contraseña."),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: "Nueva Contraseña",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_reset),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isLoading ? null : _actualizarPassword,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                child: _isLoading ? const CircularProgressIndicator() : const Text("FINALIZAR"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Widget auxiliar para las bolitas de paso
  Widget _buildStep(int paso, String label) {
    bool activo = _pasoActual >= paso;
    return Column(
      children: [
        CircleAvatar(
          radius: 15,
          backgroundColor: activo ? const Color(0xFF800000) : Colors.grey[300],
          child: Text("$paso", style: TextStyle(color: activo ? Colors.white : Colors.grey)),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: activo ? Colors.black : Colors.grey)),
      ],
    );
  }
}