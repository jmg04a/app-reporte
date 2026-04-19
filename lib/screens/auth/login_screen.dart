import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../home/main_navigation_screen.dart';
import '../auth/register_screen.dart';
import '../auth/recovery_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Pantalla inicial para la autenticación de usuarios.
/// 
/// Gestiona la validación de credenciales a través de Supabase Auth e 
/// implementa una estrategia de experiencia de usuario (UX) para el 
/// autocompletado del dominio institucional. Sincroniza automáticamente 
/// el campo de correo con las rutas secundarias (recuperación y registro).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usuarioController = TextEditingController(); 
  final _passwordController = TextEditingController();
  
  /// Sufijo del dominio institucional que se añade automáticamente si el usuario lo omite.
  static const String _dominio = "@correo.itlalaguna.edu.mx";

  bool _isLoading = false;

  /// Controla el estado de visibilidad del campo de la contraseña.
  bool _obscurePassword = true; 

  /// Muestra una alerta visual temporal (SnackBar) para retroalimentación de errores.
  /// 
  /// Utiliza un bloque [mounted] para prevenir excepciones en caso de que el 
  /// widget sea destruido antes de que el SnackBar pueda renderizarse en pantalla.
  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
    );
  }

  /// Orquesta el flujo completo de inicio de sesión.
  /// 
  /// 1. Sanitiza la entrada del usuario y maneja el autocompletado del dominio.
  /// 2. Autentica las credenciales mediante Supabase Auth.
  /// 3. Precarga los metadatos del usuario en caché (`SharedPreferences`) para disponibilidad offline.
  /// 4. Navega hacia la estructura principal de la aplicación (`MainNavigationScreen`) en caso de éxito.
  Future<void> _iniciarSesion() async {
    setState(() => _isLoading = true);
    try {
      final inputUsuario = _usuarioController.text.trim();

      // Optimización UX: Agrega el dominio institucional automáticamente si el 
      // usuario solo ingresó su nombre de usuario/número de control.
      final emailCompleto = inputUsuario.contains('@') 
      ? inputUsuario 
      : inputUsuario + _dominio; 

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailCompleto,
        password: _passwordController.text,
      );

      // Precarga los datos del perfil antes de navegar para evitar saltos en el 
      // diseño (layout shifts) o pantallas de carga en las vistas subsecuentes.
      await _guardarPerfilEnCache(response.user!.id);

      if (!mounted) return;
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(builder: (context) => const MainNavigationScreen())
      );
      
    } on AuthException catch (e) {
      // Mapea los errores genéricos de Supabase a mensajes amigables en español.
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

  /// Descarga los metadatos esenciales del usuario desde la tabla 'perfiles' y los 
  /// persiste localmente utilizando `SharedPreferences`.
  Future<void> _guardarPerfilEnCache(String userId) async {
    try {
      final supabase = Supabase.instance.client;
      
      // Realiza un join con 'estudiantes' para obtener el número de control si aplica.
      final perfil = await supabase
          .from('perfiles')
          .select('nombre, avatar_url, estudiantes(numero_control)')
          .eq('id', userId)
          .single();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('usuario_perfil', jsonEncode(perfil));
    } catch (e) {
      // Falla silenciosa: Si la caché falla, la vista ProfileScreen está diseñada 
      // para recuperar datos frescos directamente del servidor de todos modos.
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
                decoration: InputDecoration(
                  labelText: "Contraseña",
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  // Implementación idéntica a RecoveryScreen para la visibilidad de la contraseña.
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
              
              const SizedBox(height: 10),

              // Punto de entrada al flujo de recuperación de contraseña.
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final correoEscrito = _usuarioController.text.trim();
                    
                    // Espera el correo potencialmente actualizado desde RecoveryScreen.
                    final correoRegresado = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RecoveryScreen(initialEmail: correoEscrito),
                      ),
                    );

                    // Sincroniza el estado si el usuario escribió un nuevo correo allá.
                    if (correoRegresado != null && correoRegresado is String) {
                      _usuarioController.text = correoRegresado;
                    }
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
                      onPressed: () async {
                        final correoEscrito = _usuarioController.text.trim();

                        // Espera el correo potencialmente actualizado desde RegisterScreen.
                        final correoRegresado = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => RegisterScreen(initialEmail: correoEscrito),
                          ),
                        );

                        // Sincroniza el estado si el usuario escribió un nuevo correo allá.
                        if (correoRegresado != null && correoRegresado is String) {
                          _usuarioController.text = correoRegresado;
                        }
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