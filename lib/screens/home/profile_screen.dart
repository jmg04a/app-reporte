import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart'; 
import '../auth/login_screen.dart'; 

class ProfileScreen extends StatefulWidget {
  final String nombre;
  final String rol; 
  final String? avatarUrl;
  
  // ¡NUEVO! Los "teléfonos" para avisarle al menú principal de los cambios
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

  @override
  void initState() {
    super.initState();
    _nombreActual = widget.nombre;
    _currentAvatarUrl = widget.avatarUrl;
    
    final usuarioActual = Supabase.instance.client.auth.currentUser;
    _correoUsuario = usuarioActual?.email ?? 'Correo no disponible';

    _cargarPerfilFresco();
  }

  Future<void> _cargarPerfilFresco() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      
      final data = await supabase
          .from('perfiles')
          .select('nombre, avatar_url')
          .eq('id', userId)
          .maybeSingle();

      if (data != null && mounted) {
        setState(() {
          _nombreActual = data['nombre'] ?? _nombreActual;
          if (data['avatar_url'] != null) {
            _currentAvatarUrl = data['avatar_url']; 
          }
        });
      }
    } catch (e) {
      debugPrint("Error recargando perfil: $e");
    }
  }

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
        
        setState(() => _nombreActual = nuevoNombre);
        
        // ¡AVISAMOS AL MENÚ QUE EL NOMBRE CAMBIÓ!
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

      // SOFT RESET SUPABASE
      await supabase.storage.from('avatars').uploadBinary(
            rutaArchivo,
            imageBytes,
            fileOptions: FileOptions(cacheControl: '0', upsert: true, contentType: 'image/$extension'),
          );

      final imageUrl = supabase.storage.from('avatars').getPublicUrl(rutaArchivo);

      await supabase.from('perfiles').update({'avatar_url': imageUrl}).eq('id', userId);

      // SOFT RESET FLUTTER CACHÉ
      await CachedNetworkImage.evictFromCache(imageUrl);

      setState(() {
        _currentAvatarUrl = imageUrl;
        _isUploading = false;
      });

      // ¡AVISAMOS AL MENÚ QUE LA FOTO CAMBIÓ!
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
      await Supabase.instance.client.auth.signOut();
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

            const SizedBox(height: 50),
            
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