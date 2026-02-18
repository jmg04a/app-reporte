import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // CONTROLADORES
  final _nombreController = TextEditingController();
  final _correoController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  static const String _dominio = "@correo.itlalaguna.edu.mx";
  bool _isLoading = false;

  // LÓGICA DE CARRERAS
  List<Map<String, dynamic>> _carreras = []; 
  int? _selectedCarreraId;
  
  // VARIABLE DE ESTADO
  bool _esAlumno = false; 

  @override
  void initState() {
    super.initState();
    _cargarCarreras();
    
    // Escuchamos lo que escribe para "sugerir" si es alumno
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

  // --- EL DETECTIVE (Sugerencia) ---
  void _sugerirTipoUsuario() {
    final texto = _correoController.text.trim().toLowerCase();
    
    // Lógica simple: Si empieza con 'alu.' o 'l' seguido de números, SUGERIMOS que es alumno.
    // Pero el usuario podrá cambiarlo manualmente con el Switch.
    bool pareceAlumno = texto.startsWith('alu.') || 
                        texto.startsWith('l') && RegExp(r'^l[0-9]').hasMatch(texto) ||
                        RegExp(r'^[0-9]').hasMatch(texto);

    // Solo actualizamos si el campo está vacío o si el patrón es muy obvio,
    // para no molestar si el usuario ya lo apagó manualmente.
    if (pareceAlumno && !_esAlumno) {
      setState(() {
        _esAlumno = true;
      });
    }
  }

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

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _crearCuenta() async {
    // 1. VALIDACIONES
    if (_nombreController.text.trim().isEmpty) {
      _mostrarMensaje("Ingresa tu nombre completo.", esError: true);
      return;
    }
    
    // Solo validamos carrera si el switch de Alumno está ENCENDIDO
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

      // 3. ENVIAR A SUPABASE
      final response = await Supabase.instance.client.auth.signUp(
        email: emailFinal,
        password: _passwordController.text,
        data: {
          'full_name': _nombreController.text.trim(),
          // Aquí respetamos lo que diga el Switch (_esAlumno)
          'carrera_id': _esAlumno ? _selectedCarreraId : null, 
        },
      );

      if (!mounted) return;

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
                  Navigator.pop(context);
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

              // NOMBRE
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

              // CORREO
              TextField(
                controller: _correoController,
                decoration: const InputDecoration(
                  labelText: "Correo Institucional",
                  prefixIcon: Icon(Icons.alternate_email),
                  border: OutlineInputBorder(),
                  suffixText: _dominio,
                  suffixStyle: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                keyboardType: TextInputType.text, 
              ),
              
              // --- EL INTERRUPTOR MÁGICO ---
              // Esto le da el control final al usuario
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
                    // Si lo apaga, limpiamos la selección para no enviar basura
                    if (!_esAlumno) _selectedCarreraId = null;
                  });
                },
              ),
              // -----------------------------

              // DROPDOWN (Solo visible si el Switch está ON)
              if (_esAlumno) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: _selectedCarreraId,
                  isExpanded: true, // Para que el texto largo no rompa el diseño
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

              // PASSWORD
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

              // CONFIRMAR PASSWORD
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

              // BOTÓN
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _crearCuenta,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF800000),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text("REGISTRARME", style: TextStyle(fontSize: 18)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}