import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../auth/login_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'mis_reportes_screen.dart';

/// User profile management interface.
///
/// Implements an Optimistic UI pattern: it immediately renders cached data 
/// via [SharedPreferences] to ensure 0-second loading times, while 
/// asynchronously fetching fresh metadata from the Supabase backend.
class ProfileScreen extends StatefulWidget {
  final String nombre;
  final String rol; 
  final String? avatarUrl;
  
  /// Callbacks to notify the parent shell ([MainNavigationScreen]) of state mutations.
  final Function(String)? onNombreCambiado; 
  final Function(String)? onAvatarCambiado;

  const ProfileScreen({
    super.key, 
    required this.nombre, 
    required this.rol, 
    this.avatarUrl,
    this.onNombreCambiado,
    this.onAvatarCambiado,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _currentAvatarUrl;
  String _nombreActual = ''; 
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();
  
  String _correoUsuario = '';

  /// Student-specific metadata states.
  /// If [_esEstudiante] is true, the UI unlocks academic major management.
  bool _esEstudiante = false;
  String? _numeroControl;
  int? _carreraIdActual;
  String _nombreCarreraActual = 'Cargando carrera...';
  List<Map<String, dynamic>> _carreras = [];

  @override
  void initState() {
    super.initState();
    // 1. Inherit initial state from parent shell.
    _nombreActual = widget.nombre;
    _currentAvatarUrl = widget.avatarUrl;
    
    final usuarioActual = Supabase.instance.client.auth.currentUser;
    _correoUsuario = usuarioActual?.email ?? 'Correo no disponible';

    // 2. Trigger asynchronous data resolution.
    _cargarPerfilDesdeCache();
    _cargarPerfilFresco();
  }

  /// Instantly loads offline-available data from device storage.
  Future<void> _cargarPerfilDesdeCache() async {
    final prefs = await SharedPreferences.getInstance();
    
    final carrsCache = prefs.getString('carreras_cache');
    if (carrsCache != null) {
      _carreras = List<Map<String, dynamic>>.from(jsonDecode(carrsCache));
    }

    final perfilStr = prefs.getString('usuario_perfil');
    if (perfilStr != null && mounted) {
      final perfilCache = jsonDecode(perfilStr);
      setState(() {
        if (perfilCache['nombre'] != null) _nombreActual = perfilCache['nombre'];
        if (perfilCache['avatar_url'] != null) _currentAvatarUrl = perfilCache['avatar_url'];
        
        // Hydrate student context if present in the cached payload.
        if (perfilCache['carrera_id'] != null) {
          _esEstudiante = true;
          _carreraIdActual = perfilCache['carrera_id'];
          _nombreCarreraActual = perfilCache['carrera_nombre'] ?? 'Sin carrera';
          _numeroControl = perfilCache['numero_control'];
        }
      });
    }
  }

  /// Fetches the authoritative user state from the Postgres database.
  Future<void> _cargarPerfilFresco() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      
      // Update local dictionary of academic majors.
      final carrerasData = await supabase.from('cat_carreras').select('id, nombre').order('nombre');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('carreras_cache', jsonEncode(carrerasData));
      
      if (mounted) {
        setState(() => _carreras = List<Map<String, dynamic>>.from(carrerasData));
      }

      // Perform an inner join between 'perfiles' and 'estudiantes' to 
      // fetch extended role-based metadata in a single network request.
      final data = await supabase
          .from('perfiles')
          .select('nombre, avatar_url, estudiantes(numero_control, carrera_id)')
          .eq('id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _nombreActual = data['nombre'] ?? _nombreActual;
          if (data['avatar_url'] != null) _currentAvatarUrl = data['avatar_url']; 

          // Evaluate the relational payload to determine student privileges.
          if (data['estudiantes'] != null) {
            var estData = data['estudiantes'];
            if (estData is List && estData.isNotEmpty) estData = estData[0];
            
            if (estData is Map) {
              _esEstudiante = true;
              _numeroControl = estData['numero_control'];
              _carreraIdActual = estData['carrera_id'];
              
              // Map the foreign key to its human-readable label.
              final carreraObj = _carreras.firstWhere(
                (c) => c['id'] == _carreraIdActual, 
                orElse: () => {'nombre': 'Carrera no asignada o borrada'}
              );
              _nombreCarreraActual = carreraObj['nombre'];
            }
          }
        });

        // Persist the fresh authoritative payload to local cache.
        final perfilStr = prefs.getString('usuario_perfil');
        Map<String, dynamic> perfilCache = perfilStr != null ? jsonDecode(perfilStr) : {};
        
        perfilCache['nombre'] = _nombreActual;
        perfilCache['avatar_url'] = _currentAvatarUrl;
        if (_esEstudiante) {
          perfilCache['numero_control'] = _numeroControl;
          perfilCache['carrera_id'] = _carreraIdActual;
          perfilCache['carrera_nombre'] = _nombreCarreraActual;
        }
        await prefs.setString('usuario_perfil', jsonEncode(perfilCache));
      }
    } catch (e) {
      debugPrint("Error recargando perfil: $e");
    }
  }

  /// Mutates the academic major (foreign key) for student accounts.
  Future<void> _cambiarCarrera() async {
    if (_carreras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cargando catálogo de carreras, espera un segundo...")));
      return;
    }

    final nuevaCarreraId = await showDialog<int>(
      context: context,
      builder: (context) {
        int? tempSeleccionada = _carreraIdActual;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Cambiar Carrera"),
              content: DropdownButtonFormField<int>(
                initialValue: tempSeleccionada,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixIcon: Icon(Icons.school)),
                items: _carreras.map((c) => DropdownMenuItem<int>(
                  value: c['id'],
                  child: Text(c['nombre'], overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (val) => setStateDialog(() => tempSeleccionada = val),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF800000), foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(context, tempSeleccionada),
                  child: const Text("Guardar"),
                ),
              ],
            );
          }
        );
      },
    );

    if (nuevaCarreraId != null && nuevaCarreraId != _carreraIdActual) {
      try {
        final supabase = Supabase.instance.client;
        
        // Mutate the related record in the 'estudiantes' table.
        await supabase
            .from('estudiantes')
            .update({'carrera_id': nuevaCarreraId})
            .eq('numero_control', _numeroControl!);

        final carreraObj = _carreras.firstWhere((c) => c['id'] == nuevaCarreraId);
        final nuevaCarreraNombre = carreraObj['nombre'];

        if (!mounted) return;

        setState(() {
          _carreraIdActual = nuevaCarreraId;
          _nombreCarreraActual = nuevaCarreraNombre;
        });

        // Sync local cache with the new mutation.
        final prefs = await SharedPreferences.getInstance();
        final perfilStr = prefs.getString('usuario_perfil');
        if (perfilStr != null) {
          Map<String, dynamic> perfilCache = jsonDecode(perfilStr);
          perfilCache['carrera_id'] = nuevaCarreraId;
          perfilCache['carrera_nombre'] = nuevaCarreraNombre;
          await prefs.setString('usuario_perfil', jsonEncode(perfilCache));
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Carrera actualizada!'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al actualizar carrera: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  /// Mutates the user's full name.
  Future<void> _cambiarNombre() async {
    final controller = TextEditingController(text: _nombreActual);
    
    final nuevoNombre = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Editar Nombre"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: "Escribe tu nombre completo",
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF800000), 
              foregroundColor: Colors.white
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text("Guardar"),
          ),
        ],
      ),
    );

    if (nuevoNombre != null && nuevoNombre.isNotEmpty && nuevoNombre != _nombreActual) {
      try {
        final supabase = Supabase.instance.client;
        final userId = supabase.auth.currentUser!.id;
        
        await supabase.from('perfiles').update({'nombre': nuevoNombre}).eq('id', userId);
        
        if (!mounted) return;

        setState(() => _nombreActual = nuevoNombre);
        
        // Sync cache.
        final prefs = await SharedPreferences.getInstance();
        final perfilStr = prefs.getString('usuario_perfil');
        if (perfilStr != null) {
          Map<String, dynamic> perfilCache = jsonDecode(perfilStr);
          perfilCache['nombre'] = nuevoNombre;
          await prefs.setString('usuario_perfil', jsonEncode(perfilCache));
        } else {
          await prefs.setString('usuario_perfil', jsonEncode({'nombre': nuevoNombre}));
        }

        // Notify parent shell to update global UI.
        if (widget.onNombreCambiado != null) {
          widget.onNombreCambiado!(nuevoNombre);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('¡Nombre actualizado con éxito!'), backgroundColor: Colors.green)
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al actualizar nombre: $e'), backgroundColor: Colors.red)
          );
        }
      }
    }
  }

  /// Uploads a new avatar to Supabase Storage and updates the profile record.
  Future<void> _cambiarFoto() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return; 

      setState(() => _isUploading = true);

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      final extension = image.name.split('.').last;
      
      final nombreArchivo = 'avatar_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final rutaArchivo = '$userId/$nombreArchivo';

      final imageBytes = await image.readAsBytes();

      // Upsert: Replaces the previous file to save storage space.
      await supabase.storage.from('avatars').uploadBinary(
            rutaArchivo,
            imageBytes,
            fileOptions: FileOptions(cacheControl: '0', upsert: true, contentType: 'image/$extension'),
          );

      final imageUrl = supabase.storage.from('avatars').getPublicUrl(rutaArchivo);

      await supabase.from('perfiles').update({'avatar_url': imageUrl}).eq('id', userId);

      // Invalidate specific image cache to force UI refresh.
      await CachedNetworkImage.evictFromCache(imageUrl);

      if (!mounted) return;

      setState(() {
        _currentAvatarUrl = imageUrl;
        _isUploading = false;
      });

      // Sync cache.
      final prefs = await SharedPreferences.getInstance();
      final perfilStr = prefs.getString('usuario_perfil');
      if (perfilStr != null) {
        Map<String, dynamic> perfilCache = jsonDecode(perfilStr);
        perfilCache['avatar_url'] = imageUrl;
        await prefs.setString('usuario_perfil', jsonEncode(perfilCache));
      } else {
        await prefs.setString('usuario_perfil', jsonEncode({'avatar_url': imageUrl}));
      }

      // Notify parent shell.
      if (widget.onAvatarCambiado != null) {
        widget.onAvatarCambiado!(imageUrl);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Foto de perfil actualizada!'), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      setState(() => _isUploading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir foto: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  /// Terminates the user session and performs a hard reset of local storage.
  Future<void> _cerrarSesion(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cerrar Sesión"),
        content: const Text("¿Estás seguro de que deseas salir de tu cuenta?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sí, cerrar sesión"),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      // Purge sensitive and user-specific data from SharedPreferences.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('usuario_perfil'); 
      await prefs.remove('reportes_cache'); 
      await prefs.remove('reporte_borrador'); 

      try {
        await Supabase.instance.client.auth.signOut();
      } catch (e) {
        debugPrint("Fallo de red al cerrar sesión. Forzando cierre local. Error: $e");
      }

      if (context.mounted) {
        // Unmount the entire application tree and route back to Login.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Perfil"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 70,
                  backgroundColor: const Color(0xFF800000).withValues(alpha: 0.1),
                  backgroundImage: _currentAvatarUrl != null ? CachedNetworkImageProvider(_currentAvatarUrl!) : null,
                  child: _isUploading
                      ? const CircularProgressIndicator(color: Color(0xFF800000))
                      : _currentAvatarUrl == null 
                          ? const Icon(Icons.person, size: 70, color: Color(0xFF800000)) 
                          : null,
                ),
                if (!_isUploading)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF800000), 
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                        onPressed: _cambiarFoto,
                        tooltip: "Cambiar foto",
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 15),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: widget.rol == 'admin' ? Colors.amber.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.rol == 'admin' ? Colors.amber : Colors.blue)
              ),
              child: Text(
                widget.rol.toUpperCase(),
                style: TextStyle(
                  color: widget.rol == 'admin' ? Colors.orange[800] : Colors.blue[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 12
                ),
              ),
            ),
            
            const SizedBox(height: 30),

            TextField(
              controller: TextEditingController(text: _nombreActual),
              readOnly: true, 
              decoration: InputDecoration(
                labelText: "Nombre Completo",
                prefixIcon: const Icon(Icons.badge, color: Colors.grey),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.edit, color: Color(0xFF800000)),
                  onPressed: _cambiarNombre,
                  tooltip: "Editar nombre",
                ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
            
            const SizedBox(height: 20),
            
            TextField(
              controller: TextEditingController(text: _correoUsuario),
              readOnly: true, 
              decoration: InputDecoration(
                labelText: "Correo Institucional",
                prefixIcon: const Icon(Icons.email, color: Colors.grey),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),

            if (_esEstudiante) ...[
              const SizedBox(height: 20),
              TextField(
                controller: TextEditingController(text: _nombreCarreraActual),
                readOnly: true, 
                decoration: InputDecoration(
                  labelText: "Carrera",
                  prefixIcon: const Icon(Icons.school, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.edit, color: Color(0xFF800000)),
                    onPressed: _cambiarCarrera, 
                    tooltip: "Cambiar carrera",
                  ),
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
            ],

            const SizedBox(height: 40), 
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const MisReportesScreen()),
                  );
                },
                icon: const Icon(Icons.list_alt),
                label: const Text("MIS REPORTES", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF800000),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFF800000), width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
            ),

            const SizedBox(height: 15), 
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _cerrarSesion(context),
                icon: const Icon(Icons.logout),
                label: const Text("CERRAR SESIÓN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[50],
                  foregroundColor: Colors.red[700],
                  elevation: 0,
                  side: BorderSide(color: Colors.red[200]!),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}