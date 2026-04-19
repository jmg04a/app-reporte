import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pantalla para la creación de nuevas cuentas de usuario.
///
/// Gestiona el registro en Supabase Auth permitiendo a los usuarios crear 
/// una cuenta. Implementa una interfaz reactiva que detecta automáticamente 
/// si el usuario es un estudiante basándose en su prefijo de correo, 
/// solicitando datos adicionales (como la carrera) de ser necesario.
class RegisterScreen extends StatefulWidget {
  final String? initialEmail;

  const RegisterScreen({super.key, this.initialEmail});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  static const String _dominio = "@correo.itlalaguna.edu.mx";
  bool _isLoading = false;
  bool _obscurePassword = true; 
  List<Map<String, dynamic>> _carreras = []; 
  int? _selectedCarreraId;
  
  // Bandera controlada automáticamente por el listener del correo.
  bool _esAlumno = false; 

  @override
  void initState() {
    super.initState();
    _cargarCarreras();
    
    _correoController.addListener(_evaluarTipoUsuario);

    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _correoController.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _correoController.removeListener(_evaluarTipoUsuario);
    _nombreController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Evalúa dinámicamente el prefijo del correo para determinar el tipo de usuario.
  ///
  /// Escucha los cambios en el campo de correo y ajusta la bandera `_esAlumno`
  /// basándose en las reglas estrictas de la base de datos (ej. comienza con 'alu.' 
  /// o 'l' seguido de números). Esto controla la visibilidad del selector de carreras.
  void _evaluarTipoUsuario() {
    final texto = _correoController.text.trim().toLowerCase();
    
    // Validar coincidencia con formato institucional estudiantil.
    bool esCorreoAlumno = texto.startsWith('alu.') || 
                          (texto.startsWith('l') && RegExp(r'^l[0-9]').hasMatch(texto));

    if (esCorreoAlumno != _esAlumno) {
      setState(() {
        _esAlumno = esCorreoAlumno;
        if (!_esAlumno) {
          _selectedCarreraId = null; // Limpiar selección si el usuario borra el prefijo.
        }
      });
    }
  }

  /// Descarga el catálogo de carreras disponibles desde la base de datos.
  ///
  /// Realiza una consulta a la tabla `cat_carreras` en Supabase para poblar
  /// el menú desplegable (Dropdown) requerido durante el registro de estudiantes.
  Future<void> _cargarCarreras() async {
    try {
      final data = await Supabase.instance.client
          .from('cat_carreras')
          .select('id, nombre')
          .order('nombre', ascending: true);

      if (mounted) {
        setState(() {
          _carreras = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('Error cargando carreras: $e');
    }
  }

  /// Muestra una alerta visual temporal (SnackBar) para retroalimentación.
  ///
  /// Parámetros:
  /// * [mensaje]: El texto informativo a mostrar.
  /// * [esError]: Cambia el color de fondo a rojo si es verdadero, verde si es falso.
  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  /// Ejecuta el flujo de validación local y el registro en Supabase Auth.
  ///
  /// 1. Valida campos vacíos, formato de contraseña y selección de carrera (si aplica).
  /// 2. Autocompleta el dominio institucional.
  /// 3. Envía credenciales e inyecta metadatos (`full_name`, `carrera_id`) a Supabase.
  /// 4. Muestra un cuadro de diálogo notificando que se requiere verificación por correo.
  Future<void> _crearCuenta() async {
    if (_nombreController.text.trim().isEmpty) {
      _mostrarMensaje("Ingresa tu nombre completo.", esError: true);
      return;
    }
    
    if (_esAlumno && _selectedCarreraId == null) {
      _mostrarMensaje("Por favor selecciona tu carrera.", esError: true);
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      _mostrarMensaje("Las contraseñas no coinciden.", esError: true);
      return;
    }
    if (_passwordController.text.length < 6) {
      _mostrarMensaje("Mínimo 6 caracteres para la contraseña.", esError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String inputCorreo = _correoController.text.trim();
      String emailFinal = inputCorreo.contains('@') 
          ? inputCorreo 
          : inputCorreo + _dominio;

      final response = await Supabase.instance.client.auth.signUp(
        email: emailFinal,
        password: _passwordController.text,
        data: {
          'full_name': _nombreController.text.trim(),
          'carrera_id': _esAlumno ? _selectedCarreraId : null, 
        },
      );

      if (!mounted) return;

      // Si session es nulo con confirmación habilitada, se requiere verificar el correo.
      if (response.session == null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("📧 Verifica tu correo"),
            content: Text("Enlace enviado a:\n$emailFinal"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, _correoController.text.trim()); 
                },
                child: const Text("Ir al Login"),
              ),
            ],
          ),
        );
      } else {
        _mostrarMensaje("¡Cuenta creada con éxito!");
        Navigator.pop(context, _correoController.text.trim());
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
        title: const Text("Crear Cuenta"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _correoController.text.trim()),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                _esAlumno ? Icons.school : Icons.person_outline, 
                size: 60, 
                color: const Color(0xFF800000)
              ),
              const SizedBox(height: 20),
              
              const Text(
                "Registro de Nuevo Usuario",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),

              TextField(
                controller: _nombreController,
                decoration: const InputDecoration(
                  labelText: "Nombre Completo",
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 15),

              TextField(
                controller: _correoController,
                decoration: const InputDecoration(
                  labelText: "Correo Institucional",
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                  helperText: "Se agregará automáticamente @correo.itlalaguna.edu.mx",
                  helperStyle: TextStyle(color: Colors.black54),
                ),
                keyboardType: TextInputType.text, 
              ),
              
              // Interfaz totalmente reactiva: sin switches manuales.
              if (_esAlumno) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 15.0, bottom: 5.0, left: 5.0, right: 5.0),
                  child: Text(
                    "Identificamos tu número de control. Por favor selecciona tu carrera:",
                    style: TextStyle(color: Color(0xFF800000), fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedCarreraId,
                  isExpanded: true, 
                  decoration: const InputDecoration(
                    labelText: "Carrera",
                    prefixIcon: Icon(Icons.school_outlined),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  ),
                  items: _carreras.map((carrera) {
                    return DropdownMenuItem<int>(
                      value: carrera['id'],
                      child: Text(
                        carrera['nombre'],
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                    );
                  }).toList(),
                  onChanged: (valor) {
                    setState(() {
                      _selectedCarreraId = valor;
                    });
                  },
                  hint: const Text("Selecciona tu carrera"),
                ),
              ],
              
              const SizedBox(height: 15),

              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: "Contraseña",
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
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
                  labelText: "Confirmar Contraseña",
                  prefixIcon: const Icon(Icons.lock_reset),
                  border: const OutlineInputBorder(),
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

              if (_isLoading)
                const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
              else
                ElevatedButton(
                  onPressed: _crearCuenta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF800000),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text("REGISTRARME", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}