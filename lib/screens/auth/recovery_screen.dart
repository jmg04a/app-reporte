import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Gestiona la máquina de estados para la recuperación de contraseña.
///
/// Implementa un flujo de autenticación seguro dividido en 3 fases:
/// 1. Envío de código OTP (Contraseña de un solo uso) por correo electrónico.
/// 2. Verificación del token ingresado por el usuario.
/// 3. Actualización segura de las credenciales en la base de datos.
class RecoveryScreen extends StatefulWidget {
  /// Pre-llena la entrada de correo si se navega desde un intento previo en otra pantalla.
  final String? initialEmail;

  const RecoveryScreen({super.key, this.initialEmail});

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _emailController = TextEditingController();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  static const String _dominio = "@correo.itlalaguna.edu.mx";
  
  /// Rastrea la fase activa actual del flujo de recuperación.
  /// 
  /// Estados válidos: 1 (Ingreso de Correo), 2 (Ingreso de Token), 3 (Ingreso de Nueva Contraseña).
  int _pasoActual = 1; 
  
  bool _isLoading = false;
  
  /// Controla el estado de visibilidad de los campos de la contraseña.
  bool _obscurePassword = true; 

  @override
  void initState() {
    super.initState();
    // Optimización UX: Autocompleta el correo si se heredó de la pantalla anterior.
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose(); 
    super.dispose();
  }

  /// Muestra una alerta visual temporal (SnackBar) para retroalimentación.
  ///
  /// Parámetros:
  /// * [msg]: El texto informativo a mostrar.
  /// * [esError]: Cambia el color de fondo a rojo si es verdadero, verde si es falso.
  void _mostrarMensaje(String msg, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  /// Sanitiza la entrada del usuario y anexa el dominio institucional por defecto si se omite.
  String _obtenerEmailCompleto() {
    final input = _emailController.text.trim();
    return input.contains('@') ? input : input + _dominio;
  }

  /// Fase 1: Solicita a Supabase Auth un token OTP para ser enviado por correo.
  Future<void> _enviarCodigo() async {
    if (_emailController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa tu usuario.", esError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final emailFinal = _obtenerEmailCompleto();
      await Supabase.instance.client.auth.resetPasswordForEmail(emailFinal);
      
      _mostrarMensaje("Código enviado. Revisa tu correo institucional.");
      // Transición a la Fase 2 tras el envío exitoso del token.
      setState(() => _pasoActual = 2);
    } on AuthException catch (e) {
      _mostrarMensaje(e.message, esError: true);
    } catch (e) {
      _mostrarMensaje("Error: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Fase 2: Valida el token OTP proporcionado por el usuario contra Supabase Auth.
  Future<void> _verificarCodigo() async {
    if (_tokenController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa el código.", esError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final emailFinal = _obtenerEmailCompleto();
      
      await Supabase.instance.client.auth.verifyOTP(
        token: _tokenController.text.trim(),
        type: OtpType.recovery,
        email: emailFinal,
      );

      _mostrarMensaje("Código correcto. Ingresa tu nueva contraseña.");
      // Transición a la Fase 3 tras la validación exitosa del token.
      setState(() => _pasoActual = 3);
    } on AuthException catch (_) {
      _mostrarMensaje("Código inválido o expirado", esError: true);
    } catch (e) {
      _mostrarMensaje("Error: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Fase 3: Guarda la nueva contraseña en el perfil del usuario autenticado.
  Future<void> _actualizarPassword() async {
    // Validaciones locales previas para evitar peticiones de red innecesarias.
    if (_passwordController.text.length < 6) {
      _mostrarMensaje("La contraseña debe tener al menos 6 caracteres.", esError: true);
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _mostrarMensaje("Las contraseñas no coinciden.", esError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );

      if (mounted) {
        _mostrarMensaje("¡Contraseña actualizada con éxito!");
        // Completa el flujo exitosamente y devuelve el correo a la pantalla de login.
        Navigator.pop(context, _emailController.text.trim()); 
      }
    } on AuthException catch (e) {
      _mostrarMensaje(e.message, esError: true);
    } catch (e) {
      _mostrarMensaje("Error: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Recuperar Cuenta"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        // Sobrescribe el comportamiento del botón de retroceso para pasar el estado hacia atrás
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _emailController.text.trim()),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Indicador de progreso visual (Stepper)
            Row(
              children: [
                _buildStep(1, "Correo"),
                const Expanded(child: Divider(color: Colors.grey, thickness: 1)),
                _buildStep(2, "Código"),
                const Expanded(child: Divider(color: Colors.grey, thickness: 1)),
                _buildStep(3, "Password"),
              ],
            ),
            const SizedBox(height: 40),

            // ==========================================
            // UI FASE 1: INGRESO DE CORREO
            // ==========================================
            if (_pasoActual == 1) ...[
              const Icon(Icons.mark_email_read_outlined, size: 60, color: Color(0xFF800000)),
              const SizedBox(height: 20),
              const Text(
                "Enviaremos un código de recuperación a tu correo institucional.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: "Correo institucional",
                  helperText: "Se agregará automáticamente @correo.itlalaguna.edu.mx",
                  helperStyle: TextStyle(color: Colors.black54),
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _enviarCodigo,
                icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_isLoading ? "ENVIANDO..." : "ENVIAR CÓDIGO", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF800000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],

            // ==========================================
            // UI FASE 2: INGRESO DE TOKEN
            // ==========================================
            if (_pasoActual == 2) ...[
              const Icon(Icons.password, size: 60, color: Color(0xFF800000)),
              const SizedBox(height: 20),
              const Text(
                "Revisa tu bandeja de entrada e ingresa el código de 8 dígitos que te enviamos.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _tokenController,
                decoration: const InputDecoration(
                  labelText: "Código de Verificación",
                  hintText: "Ej. 12345678",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.dialpad),
                ),
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, letterSpacing: 8, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _verificarCodigo,
                icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.verified_user_outlined),
                label: Text(_isLoading ? "VERIFICANDO..." : "VERIFICAR CÓDIGO", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF800000),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],

            // ==========================================
            // UI FASE 3: INGRESO DE NUEVA CONTRASEÑA
            // ==========================================
            if (_pasoActual == 3) ...[
              const Icon(Icons.lock_reset, size: 60, color: Colors.green),
              const SizedBox(height: 20),
              const Text(
                "¡Identidad verificada! Por favor, crea tu nueva contraseña para acceder.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 30),
              
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: "Nueva Contraseña",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword, 
              ),
              const SizedBox(height: 15),

              TextField(
                controller: _confirmPasswordController,
                decoration: InputDecoration(
                  labelText: "Confirmar Nueva Contraseña",
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_reset),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword, 
              ),

              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _actualizarPassword,
                icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save),
                label: Text(_isLoading ? "GUARDANDO..." : "ACTUALIZAR CONTRASEÑA", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, 
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Construuye un nodo visual individual para el indicador de pasos horizontal.
  Widget _buildStep(int paso, String label) {
    bool activo = _pasoActual >= paso;
    return Column(
      children: [
        CircleAvatar(
          radius: 18, 
          backgroundColor: activo ? const Color(0xFF800000) : Colors.grey[300],
          child: Text(
            "$paso", 
            style: TextStyle(
              color: activo ? Colors.white : Colors.grey[600],
              fontWeight: FontWeight.bold,
              fontSize: 16
            )
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label, 
          style: TextStyle(
            fontSize: 13, 
            color: activo ? Colors.black87 : Colors.grey,
            fontWeight: activo ? FontWeight.bold : FontWeight.normal
          )
        ),
      ],
    );
  }
}