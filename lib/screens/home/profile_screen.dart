import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../auth/login_screen.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'mis_reportes_screen.dart';
import 'dart:io'; 
import 'package:flutter/foundation.dart'; 
import 'package:image/image.dart' as img;

/// Interfaz para la visualización y edición del perfil del usuario.
///
/// Gestiona la información de la cuenta (Nombre, Correo, Carrera, Avatar).
/// Permite editar datos personales sincronizándolos tanto en la base de datos 
/// (Supabase) como en la caché local (`SharedPreferences`), además de servir 
/// como punto de entrada hacia la gestión de sesión y el historial personal de reportes.
class ProfileScreen extends StatefulWidget {
  final String nombre;
  final String rol; 
  final String? avatarUrl;
  
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
  State<ProfileScreen> createState() => ProfileScreenState();
}

/// Estado interno para [ProfileScreen].
///
/// Implementa [WidgetsBindingObserver] para manejar el ciclo de vida del sistema
/// y recuperar el foco del teclado globalmente, permitiendo navegar la app 
/// con atajos de teclado sin perder el control en entornos de escritorio.
class ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  String? _currentAvatarUrl;
  String _nombreActual = ''; 
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();
  
  String _correoUsuario = '';

  bool _isLoading = true; 
  bool _bloqueoRecarga = false;

  bool _esEstudiante = false;
  String? _numeroControl;
  int? _carreraIdActual;
  String _nombreCarreraActual = 'Cargando carrera...';
  List<Map<String, dynamic>> _carreras = [];

  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  /// Solicita explícitamente el foco del sistema.
  ///
  /// Es invocada externamente por `MainNavigationScreen` cuando el usuario 
  /// cambia a esta pestaña, garantizando que el widget esté listo para 
  /// interceptar atajos de teclado de forma inmediata.
  void pedirFoco() {
    if (mounted && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _nombreActual = widget.nombre;
    _currentAvatarUrl = widget.avatarUrl;
    
    final usuarioActual = Supabase.instance.client.auth.currentUser;
    _correoUsuario = usuarioActual?.email ?? 'Correo no disponible';

    _inicializarPantalla();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); 
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Recupera el teclado tras volver del modo inactivo (background).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_focusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    }
  }

  /// Desplaza la vista a la posición inicial.
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, 
        duration: const Duration(milliseconds: 600), 
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Secuencia el arranque de datos, priorizando velocidad visual.
  Future<void> _inicializarPantalla() async {
    await _cargarPerfilDesdeCache();
    await cargarPerfilFresco();
  }

  /// Renderiza la UI instantáneamente usando la última versión guardada del perfil.
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
        
        if (perfilCache['carrera_id'] != null) {
          _esEstudiante = true;
          _carreraIdActual = perfilCache['carrera_id'];
          _nombreCarreraActual = perfilCache['carrera_nombre'] ?? 'Sin carrera';
          _numeroControl = perfilCache['numero_control'];
        }

        _isLoading = false; 
      });
    }
  }

  /// Sincroniza en segundo plano los datos del servidor con el caché local.
  Future<void> cargarPerfilFresco() async {
    if (_bloqueoRecarga) return; 
    _bloqueoRecarga = true;

    if (_nombreActual == 'Cargando...' || _nombreActual.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      
      final carrerasData = await supabase.from('cat_carreras').select('id, nombre').order('nombre');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('carreras_cache', jsonEncode(carrerasData));
      
      if (mounted) {
        setState(() => _carreras = List<Map<String, dynamic>>.from(carrerasData));
      }

      final data = await supabase
          .from('perfiles')
          .select('nombre, avatar_url, estudiantes(numero_control, carrera_id)')
          .eq('id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _nombreActual = data['nombre'] ?? _nombreActual;
          if (data['avatar_url'] != null) _currentAvatarUrl = data['avatar_url']; 

          if (data['estudiantes'] != null) {
            var estData = data['estudiantes'];
            if (estData is List && estData.isNotEmpty) estData = estData[0];
            
            if (estData is Map) {
              _esEstudiante = true;
              _numeroControl = estData['numero_control'];
              _carreraIdActual = estData['carrera_id'];
              
              final carreraObj = _carreras.firstWhere(
                (c) => c['id'] == _carreraIdActual, 
                orElse: () => {'nombre': 'Carrera no asignada o borrada'}
              );
              _nombreCarreraActual = carreraObj['nombre'];
            }
          }

          _isLoading = false;
        });

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
      if (mounted) setState(() => _isLoading = false);
    } finally {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _bloqueoRecarga = false;
    }
  }

  /// Muestra un modal de selección para modificar la carrera del estudiante.
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

  /// Muestra un modal con entrada de texto para renombrar el perfil del usuario.
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
        
        final prefs = await SharedPreferences.getInstance();
        final perfilStr = prefs.getString('usuario_perfil');
        if (perfilStr != null) {
          Map<String, dynamic> perfilCache = jsonDecode(perfilStr);
          perfilCache['nombre'] = nuevoNombre;
          await prefs.setString('usuario_perfil', jsonEncode(perfilCache));
        } else {
          await prefs.setString('usuario_perfil', jsonEncode({'nombre': nuevoNombre}));
        }

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

  /// Selecciona una imagen, la comprime y la sube al Storage (Bucket) del servidor.
  ///
  /// Implementa procesamiento nativo de imágenes (`image` package) en entornos 
  /// de escritorio (Windows/Mac/Linux) para forzar un ancho máximo de 540px 
  /// antes de subir la carga útil a Supabase, optimizando el ancho de banda.
  Future<void> _cambiarFoto() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image == null) return; 

      setState(() => _isUploading = true);

      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      
      final nombreArchivo = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final rutaArchivo = '$userId/$nombreArchivo';

      Uint8List imageBytes = await image.readAsBytes();

      if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        img.Image? imagenOriginal = img.decodeImage(imageBytes);
        
        if (imagenOriginal != null) {
          img.Image imagenAchicada = img.copyResize(imagenOriginal, width: 540);
          imageBytes = Uint8List.fromList(img.encodeJpg(imagenAchicada, quality: 70));
        }
      }

      await supabase.storage.from('avatars').uploadBinary(
            rutaArchivo,
            imageBytes,
            fileOptions: const FileOptions(
              cacheControl: '0', 
              upsert: true, 
              contentType: 'image/jpeg'
            ),
          );

      final imageUrl = supabase.storage.from('avatars').getPublicUrl(rutaArchivo);

      await supabase.from('perfiles').update({'avatar_url': imageUrl}).eq('id', userId);

      await CachedNetworkImage.evictFromCache(imageUrl);

      if (!mounted) return;

      setState(() {
        _currentAvatarUrl = imageUrl;
        _isUploading = false;
      });

      final prefs = await SharedPreferences.getInstance();
      final perfilStr = prefs.getString('usuario_perfil');
      if (perfilStr != null) {
        Map<String, dynamic> perfilCache = jsonDecode(perfilStr);
        perfilCache['avatar_url'] = imageUrl;
        await prefs.setString('usuario_perfil', jsonEncode(perfilCache));
      } else {
        await prefs.setString('usuario_perfil', jsonEncode({'avatar_url': imageUrl}));
      }

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

  /// Destruye la sesión activa del usuario.
  ///
  /// Elimina los tokens de autenticación remotos y purga las llaves internas 
  /// en `SharedPreferences` para garantizar la privacidad de los datos locales 
  /// antes de devolver al usuario a la pantalla de inicio de sesión.
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
    final bool isApple = !kIsWeb && (Platform.isMacOS || Platform.isIOS);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyR, control: !isApple, meta: isApple, includeRepeats: false): cargarPerfilFresco,
        SingleActivator(LogicalKeyboardKey.arrowUp, control: !isApple, meta: isApple, includeRepeats: false): _scrollToTop,
        const SingleActivator(LogicalKeyboardKey.home, includeRepeats: false): _scrollToTop,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: _scrollToTop,
              child: const Text("Mi Perfil"),
            ),
            backgroundColor: const Color(0xFF800000),
            foregroundColor: Colors.white,
          ),
          body: RefreshIndicator(
            onRefresh: cargarPerfilFresco,
            color: const Color(0xFF800000),
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
              : SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
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
          ),
        ),
      ),
    );
  }
}