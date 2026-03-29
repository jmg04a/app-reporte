import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entry point for new user registration.
///
/// Handles user creation via Supabase Auth and collects extended metadata 
/// (full name, student status, and academic major) to be appended 
/// to the internal `auth.users` raw metadata payload.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  /// Institutional domain suffix appended automatically if the user omits it.
  static const String _dominio = "@correo.itlalaguna.edu.mx";
  
  bool _isLoading = false;

  /// Holds the cached catalog of academic majors fetched from the database.
  List<Map<String, dynamic>> _carreras = []; 
  
  int? _selectedCarreraId;
  
  /// Controls the visibility and enforcement of the academic major dropdown.
  /// If true, [_selectedCarreraId] becomes a required field.
  bool _esAlumno = false; 

  @override
  void initState() {
    super.initState();
    _cargarCarreras();
    
    // Attach listener to evaluate input heuristically in real-time.
    _correoController.addListener(_sugerirTipoUsuario);
  }

  @override
  void dispose() {
    _correoController.removeListener(_sugerirTipoUsuario);
    _nombreController.dispose();
    _correoController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  /// Heuristic algorithm to auto-detect if the user is a student.
  ///
  /// Evaluates the prefix of the institutional email. ITL students typically 
  /// use 'alu.[control_number]' or '[l][control_number]'. 
  /// Automatically toggles the [_esAlumno] state to enhance UX, though 
  /// the user retains manual override control via the Switch widget.
  void _sugerirTipoUsuario() {
    final texto = _correoController.text.trim().toLowerCase();
    
    bool pareceAlumno = texto.startsWith('alu.') || 
                        (texto.startsWith('l') && RegExp(r'^l[0-9]').hasMatch(texto)) ||
                        RegExp(r'^[0-9]').hasMatch(texto);

    // Only auto-toggle to true if the heuristic matches and the state is currently false,
    // avoiding disruptive UX overrides if the user manually disabled it.
    if (pareceAlumno && !_esAlumno) {
      setState(() {
        _esAlumno = true;
      });
    }
  }

  /// Fetches the 'cat_carreras' catalog from Supabase to populate the dropdown.
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

  /// Displays transient UI feedback for validation and network responses.
  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  /// Orchestrates the registration flow and payload construction.
  Future<void> _crearCuenta() async {
    // 1. Pre-flight UI Validation
    if (_nombreController.text.trim().isEmpty) {
      _mostrarMensaje("Ingresa tu nombre completo.", esError: true);
      return;
    }
    
    // Enforce major selection strictly if the student flag is active.
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
      // 2. Data Sanitization
      String inputCorreo = _correoController.text.trim();
      String emailFinal = inputCorreo.contains('@') 
          ? inputCorreo 
          : inputCorreo + _dominio;

      // 3. Auth Request
      // We embed extended metadata ('data' object) which triggers a Postgres 
      // trigger on the backend to automatically populate the 'perfiles' and 
      // 'estudiantes' tables upon successful registration.
      final response = await Supabase.instance.client.auth.signUp(
        email: emailFinal,
        password: _passwordController.text,
        data: {
          'full_name': _nombreController.text.trim(),
          'carrera_id': _esAlumno ? _selectedCarreraId : null, 
        },
      );

      if (!mounted) return;

      // 4. Response Handling
      // If session is null, email confirmation is strictly required by the backend.
      if (response.session == null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("📧 Verifica tu correo"),
            content: Text("Enlace enviado a:\n$emailFinal"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Pop back to LoginScreen
                },
                child: const Text("Ir al Login"),
              ),
            ],
          ),
        );
      } else {
        _mostrarMensaje("¡Cuenta creada con éxito!");
        Navigator.pop(context);
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
              
              // Manual override for the student heuristic
              SwitchListTile(
                title: const Text(
                  "¿Eres Estudiante?", 
                  style: TextStyle(fontWeight: FontWeight.bold)
                ),
                subtitle: const Text("Actívalo para seleccionar tu carrera"),
                value: _esAlumno,
                activeTrackColor: const Color(0xFF800000),
                onChanged: (bool valor) {
                  setState(() {
                    _esAlumno = valor;
                    // Garbage collection: Nullify major if user is not a student
                    // to prevent sending dirty data to Supabase.
                    if (!_esAlumno) _selectedCarreraId = null;
                  });
                },
              ),

              // Academic Major Dropdown (Conditional rendering based on [_esAlumno])
              if (_esAlumno) ...[
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
                decoration: const InputDecoration(
                  labelText: "Contraseña",
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 15),

              TextField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: "Confirmar Contraseña",
                  prefixIcon: Icon(Icons.lock_reset),
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
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