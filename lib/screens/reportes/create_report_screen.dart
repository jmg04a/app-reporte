import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image/image.dart' as img;

/// Interfaz de formulario de doble propósito para la creación y modificación de reportes.
///
/// Implementa el autoguardado de borradores mediante [SharedPreferences] para el 
/// modo de creación, y la hidratación de estado para el modo de modificación 
/// cuando se recibe un [reporteExistente]. Gestiona la selección de imágenes, 
/// la construcción del paquete de datos (payload) y las subidas binarias a Supabase Storage.
class CreateReportScreen extends StatefulWidget {
  /// Los datos del reporte existente. Si se proporciona, la interfaz entra en "Modo Edición".
  /// Si es nulo, la interfaz adopta por defecto el "Modo Creación".
  final Map<String, dynamic>? reporteExistente;

  const CreateReportScreen({super.key, this.reporteExistente});

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _tituloController = TextEditingController();
  final _descripcionController = TextEditingController();

  /// Previene envíos múltiples o duplicados durante las peticiones de red.
  bool _isSubmitting = false; 
  
  /// Bloquea el renderizado de la interfaz hasta que se carguen los diccionarios de catálogo requeridos.
  bool _isLoadingData = true; 

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _todosLosLugares = []; 

  int? _selectedCategoriaId;
  int? _selectedLugarId; 

  String? _errorLugar;
  String _lugarTextoActual = '';

  XFile? _imagenSeleccionada;
  final ImagePicker _picker = ImagePicker();

  /// Banderas de estado para la modificación de la imagen durante el Modo Edición.
  String? _imagenViejaUrl;
  bool _eliminoImagenVieja = false;

  /// Propiedad calculada (Getter) para determinar el modo de ejecución actual.
  bool get _esEdicion => widget.reporteExistente != null;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  @override
  void dispose() {
    if (!_esEdicion) {
      _tituloController.removeListener(_guardarBorrador);
      _descripcionController.removeListener(_guardarBorrador);
    }
    _tituloController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  /// Inicializa el formulario cargando los diccionarios de catálogos requeridos (Categorías y Lugares).
  Future<void> _cargarDatosIniciales() async {
    final prefs = await SharedPreferences.getInstance();
    final catsCache = prefs.getString('categorias_cache');
    final lugsCache = prefs.getString('lugares_cache');

    if (catsCache != null && lugsCache != null) {
      final catsLocal = jsonDecode(catsCache);
      final lugsLocal = jsonDecode(lugsCache);
      _procesarYMostrarCatalogos(catsLocal, lugsLocal);
    }

    try {
      final supabase = Supabase.instance.client;
      
      final respuestas = await Future.wait([
        supabase.from('cat_categorias').select('id, nombre, icono, color').order('nombre'),
        supabase.from('cat_lugares').select('id, nombre, tipo, parent_id').order('nombre')
      ]);

      final categoriasData = respuestas[0];
      final lugaresData = respuestas[1];

      prefs.setString('categorias_cache', jsonEncode(categoriasData));
      prefs.setString('lugares_cache', jsonEncode(lugaresData));

      _procesarYMostrarCatalogos(categoriasData, lugaresData);

    } catch (e) {
      if (_categorias.isEmpty) {
        _mostrarMensaje("Error cargando catálogos: $e", esError: true);
      }
    } finally {
      if (_esEdicion) {
        _prellenarDatosEdicion();
      } else {
        await _cargarBorrador();
      }
      
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  void _procesarYMostrarCatalogos(List<dynamic> categoriasData, List<dynamic> lugaresData) {
    List<Map<String, dynamic>> lugaresFormateados = [];
    
    for (var lugar in lugaresData) {
      String nombre = lugar['nombre'];
      String padreNombre = '';

      if (lugar['parent_id'] != null) {
        final padre = lugaresData.firstWhere(
          (element) => element['id'] == lugar['parent_id'], 
          orElse: () => {'nombre': ''}
        );
        padreNombre = padre['nombre'];
      }

      String nombreBuscable = padreNombre.isNotEmpty ? '$nombre ($padreNombre)' : nombre;

      lugaresFormateados.add({
        'id': lugar['id'],
        'nombre': nombre,
        'padre_nombre': padreNombre,
        'tipo': lugar['tipo'], 
        'nombreBuscable': nombreBuscable,
      });
    }

    if (mounted) {
      setState(() {
        _categorias = List<Map<String, dynamic>>.from(categoriasData);
        _todosLosLugares = lugaresFormateados;
      });
    }
  }

  void _prellenarDatosEdicion() {
    final rep = widget.reporteExistente!;
    setState(() {
      _tituloController.text = rep['titulo'] ?? '';
      _descripcionController.text = rep['descripcion'] ?? '';
      _selectedCategoriaId = rep['categoria_id'];
      _imagenViejaUrl = rep['evidencia_url'];
    });

    _cargarUbicacionEdicion(rep['id']);
  }

  Future<void> _cargarUbicacionEdicion(int reporteId) async {
    try {
      final data = await Supabase.instance.client
          .from('reporte_ubicaciones')
          .select('lugar_id')
          .eq('reporte_id', reporteId)
          .maybeSingle();
          
      if (data != null && mounted) {
        setState(() {
          _selectedLugarId = data['lugar_id'];
          final lugarEncontrado = _todosLosLugares.firstWhere(
            (l) => l['id'] == _selectedLugarId, 
            orElse: () => {'nombreBuscable': ''}
          );
          _lugarTextoActual = lugarEncontrado['nombreBuscable'];
        });
      }
    } catch (e) {
      debugPrint("Error cargando ubicación para editar: $e");
    }
  }

  Future<void> _cargarBorrador() async {
    final prefs = await SharedPreferences.getInstance();
    final borradorStr = prefs.getString('reporte_borrador');

    if (borradorStr != null) {
      final borrador = jsonDecode(borradorStr);
      setState(() {
        _tituloController.text = borrador['titulo'] ?? '';
        _descripcionController.text = borrador['descripcion'] ?? '';
        _selectedCategoriaId = borrador['categoriaId'];
        _selectedLugarId = borrador['lugarId'];
      });
    }

    _tituloController.addListener(_guardarBorrador);
    _descripcionController.addListener(_guardarBorrador);
  }

  Future<void> _guardarBorrador() async {
    if (_esEdicion) return; 
    final prefs = await SharedPreferences.getInstance();
    final borrador = {
      'titulo': _tituloController.text,
      'descripcion': _descripcionController.text,
      'categoriaId': _selectedCategoriaId,
      'lugarId': _selectedLugarId,
    };
    await prefs.setString('reporte_borrador', jsonEncode(borrador));
  }

  Future<void> _limpiarBorrador() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 10),
            Text("Descartar cambios"),
          ],
        ),
        content: Text(_esEdicion 
          ? "¿Estás seguro de que deseas descartar los cambios? El reporte quedará como estaba."
          : "¿Estás seguro de que deseas borrar todo lo que has escrito?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sí, descartar"),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      if (!mounted) return;

      if (_esEdicion) {
        Navigator.pop(context); 
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('reporte_borrador');

      if (!mounted) return;

      setState(() {
        _tituloController.clear();
        _descripcionController.clear();
        _selectedCategoriaId = null;
        _selectedLugarId = null;
        _imagenSeleccionada = null;
        _errorLugar = null;
        _lugarTextoActual = '';
      });
    }
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(mensaje),
          backgroundColor: esError ? Colors.red : Colors.green),
    );
  }

  Color _getColorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return Colors.grey;
    final hexCode = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hexCode', radix: 16));
  }

  IconData _getIconFromName(String? iconName) {
    switch (iconName) {
      case 'build': return Icons.build;
      case 'chair': return Icons.chair_alt;
      case 'computer': return Icons.computer;
      case 'cleaning_services': return Icons.cleaning_services;
      case 'security': return Icons.security;
      default: return Icons.category;
    }
  }

  void _mostrarOpcionesDeImagen() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Tomar foto ahora'),
                onTap: () {
                  Navigator.pop(context);
                  _procesarImagen(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Elegir de la galería'),
                onTap: () {
                  Navigator.pop(context);
                  _procesarImagen(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _procesarImagen(ImageSource origen) async {
    final XFile? image = await _picker.pickImage(
      source: origen, 
      imageQuality: 70,
      maxWidth: 1080,
      maxHeight: 1080,
    );
    if (image != null) {
      setState(() {
        _imagenSeleccionada = image;
        _eliminoImagenVieja = true; 
      });
    }
  }

  void _manejarBotonImagen() {
    if (kIsWeb) {
      _procesarImagen(ImageSource.gallery);
    } else if (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) {
      _mostrarOpcionesDeImagen();
    } else {
      _procesarImagen(ImageSource.gallery);
    }
  }

  /// Abre un menú inferior (Bottom Sheet) para la selección interactiva de lugares.
  void _abrirBuscadorDeLugares() {
    String filtroLocal = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, 
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final opcionesFiltradas = _todosLosLugares
                .where((l) => l['nombreBuscable'].toString().toLowerCase().contains(filtroLocal.toLowerCase()))
                .toList();

            return FractionallySizedBox(
              heightFactor: 0.85, 
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  top: 16, left: 16, right: 16
                ),
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: "Buscar edificio o aula...",
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setModalState(() {
                          filtroLocal = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: opcionesFiltradas.length,
                        itemBuilder: (context, index) {
                          final option = opcionesFiltradas[index];
                          final esEdificio = option['padre_nombre'] == '';

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF800000).withValues(alpha: 0.1),
                              child: Icon(esEdificio ? Icons.domain : Icons.meeting_room, color: const Color(0xFF800000)),
                            ),
                            title: Text(option['nombre'], style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(esEdificio ? "Edificio Principal" : "Pertenece a: ${option['padre_nombre']}"),
                            onTap: () {
                              setState(() {
                                _selectedLugarId = option['id'];
                                _lugarTextoActual = option['nombreBuscable'];
                                _errorLugar = null;
                              });
                              _guardarBorrador();
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _enviarReporte() async {
    if (_isSubmitting) return; 

    if (_tituloController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa un título.", esError: true);
      return;
    }
    if (_selectedCategoriaId == null) {
      _mostrarMensaje("Selecciona una categoría.", esError: true);
      return;
    }

    if (_selectedLugarId == null) {
      setState(() => _errorLugar = "Por favor selecciona un edificio o aula válida");
      _mostrarMensaje("Por favor selecciona un edificio o aula válida.", esError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      String? evidenciaUrlFinal = _eliminoImagenVieja ? null : _imagenViejaUrl;

      if (_imagenSeleccionada != null) {
        final nombreArchivo = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final rutaArchivo = '$userId/$nombreArchivo';
        
        Uint8List imageBytes = await _imagenSeleccionada!.readAsBytes();

        if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
          img.Image? imagenOriginal = img.decodeImage(imageBytes);
          
          if (imagenOriginal != null) {
            img.Image imagenAchicada = img.copyResize(imagenOriginal, width: 1080);
            imageBytes = Uint8List.fromList(img.encodeJpg(imagenAchicada, quality: 70));
          }
        }

        await supabase.storage.from('evidencias').uploadBinary(
              rutaArchivo,
              imageBytes,
              fileOptions: const FileOptions(
                cacheControl: '3600', 
                upsert: false, 
                contentType: 'image/jpeg'
              ),
            );
        evidenciaUrlFinal = supabase.storage.from('evidencias').getPublicUrl(rutaArchivo);
      }

      if (_esEdicion) {
        final reporteId = widget.reporteExistente!['id'];

        await supabase.from('reportes').update({
          'titulo': _tituloController.text.trim(),
          'descripcion': _descripcionController.text.trim(),
          'categoria_id': _selectedCategoriaId,
          'evidencia_url': evidenciaUrlFinal,
        }).eq('id', reporteId);

        await supabase.from('reporte_ubicaciones').update({
          'lugar_id': _selectedLugarId,
        }).eq('reporte_id', reporteId);

        _mostrarMensaje("¡Reporte actualizado con éxito!");

      } else {
        final reporteInsertado = await supabase.from('reportes').insert({
          'titulo': _tituloController.text.trim(),
          'descripcion': _descripcionController.text.trim(),
          'categoria_id': _selectedCategoriaId,
          'usuario_id': userId,
          'estado': 'pendiente',
          'evidencia_url': evidenciaUrlFinal,
        }).select('id').single();

        final reporteId = reporteInsertado['id'];

        await supabase.from('reporte_ubicaciones').insert({
          'reporte_id': reporteId,
          'lugar_id': _selectedLugarId,
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('reporte_borrador');

        _mostrarMensaje("¡Reporte enviado con éxito!");
      }

      if (!mounted) return;
      Navigator.pop(context);

    } catch (e) {
      _mostrarMensaje("Error al procesar reporte: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_esEdicion ? "Editar Reporte" : "Nuevo Reporte"),
          backgroundColor: const Color(0xFF800000),
        ),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF800000))),
      );
    }

    if (_selectedLugarId != null && _todosLosLugares.isNotEmpty && _lugarTextoActual.isEmpty) {
      final lugarEncontrado = _todosLosLugares.firstWhere(
        (l) => l['id'] == _selectedLugarId, 
        orElse: () => {'nombreBuscable': ''}
      );
      _lugarTextoActual = lugarEncontrado['nombreBuscable'];
    }

    final bool isApple = !kIsWeb && (Platform.isMacOS || Platform.isIOS);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyS, control: !isApple, meta: isApple, includeRepeats: false): () {
           if (!_isSubmitting) _enviarReporte();
        },
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_esEdicion ? "Editar Reporte" : "Nuevo Reporte"),
          backgroundColor: const Color(0xFF800000),
          foregroundColor: Colors.white,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_esEdicion ? "Corregir detalles" : "¿Qué está fallando?", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              
              TextField(
                controller: _tituloController,
                decoration: const InputDecoration(labelText: "Título breve", hintText: "Ej. Proyector no enciende", prefixIcon: Icon(Icons.short_text), border: OutlineInputBorder()),
                maxLength: 50,
              ),
              const SizedBox(height: 15),
              
              DropdownButtonFormField<int>(
                initialValue: _selectedCategoriaId,
                decoration: const InputDecoration(labelText: "Categoría", prefixIcon: Icon(Icons.category_outlined), border: OutlineInputBorder()),
                items: _categorias.map((cat) {
                  return DropdownMenuItem<int>(
                    value: cat['id'],
                    child: Row(
                      children: [
                        Icon(_getIconFromName(cat['icono']), color: _getColorFromHex(cat['color'])),
                        const SizedBox(width: 10),
                        Text(cat['nombre']),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedCategoriaId = val);
                  _guardarBorrador(); 
                },
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              
              const Text("Ubicación del problema", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              
              // Uso del InkWell + InputDecorator interactivo para el Bottom Sheet en lugar de Autocomplete
              InkWell(
                onTap: _abrirBuscadorDeLugares,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: "Edificio o aula",
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    errorText: _errorLugar,
                  ),
                  child: Text(
                    _lugarTextoActual.isEmpty ? "Toca para buscar..." : _lugarTextoActual,
                    style: TextStyle(
                      color: _lugarTextoActual.isEmpty ? Colors.grey[600] : Colors.black, 
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
  
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 15),
              
              TextField(
                controller: _descripcionController,
                decoration: const InputDecoration(labelText: "Descripción detallada", border: OutlineInputBorder(), alignLabelWithHint: true),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
  
              const Text("Evidencia fotográfica (Opcional)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
  
              InkWell(
                onTap: _manejarBotonImagen,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 400),
                  decoration: BoxDecoration(color: Colors.grey[200], border: Border.all(color: Colors.grey[400]!), borderRadius: BorderRadius.circular(8)),
                  child: _imagenSeleccionada != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: kIsWeb
                              ? Image.network(_imagenSeleccionada!.path, fit: BoxFit.contain)
                              : Image.file(File(_imagenSeleccionada!.path), fit: BoxFit.contain,cacheWidth: 800,),
                        )
                      : (!_eliminoImagenVieja && _imagenViejaUrl != null)
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: _imagenViejaUrl!,
                                fit: BoxFit.contain,
                                memCacheWidth: 800,
                              ),
                            )
                          : const SizedBox(
                              height: 150,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text("Toca para agregar una foto", style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                ),
              ),
  
              if (_imagenSeleccionada != null || (!_eliminoImagenVieja && _imagenViejaUrl != null))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _imagenSeleccionada = null;
                      _eliminoImagenVieja = true;
                    }),
                    icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                    label: const Text("Quitar foto", style: TextStyle(color: Colors.red)),
                  ),
                ),
              const SizedBox(height: 30),
  
              if (_isSubmitting)
                const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF800000),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: Icon(_esEdicion ? Icons.save : Icons.send),
                        label: Text(_esEdicion ? "ACTUALIZAR REPORTE" : "ENVIAR REPORTE", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        onPressed: _enviarReporte,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[50],
                        foregroundColor: Colors.red,
                        elevation: 0,
                        side: BorderSide(color: Colors.red[200]!),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _limpiarBorrador,
                      child: const Icon(Icons.close), 
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