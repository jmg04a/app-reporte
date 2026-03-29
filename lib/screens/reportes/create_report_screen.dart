import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Dual-purpose form interface for report creation and modification.
///
/// Implements draft auto-saving via [SharedPreferences] for creation mode, 
/// and state hydration for modification mode when passed a [reporteExistente].
/// Handles image picking, payload construction, and binary uploads to Supabase Storage.
class CreateReportScreen extends StatefulWidget {
  /// The existing report payload. If provided, the UI enters "Edit Mode".
  /// If null, the UI defaults to "Create Mode".
  final Map<String, dynamic>? reporteExistente;

  const CreateReportScreen({super.key, this.reporteExistente});

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _tituloController = TextEditingController();
  final _descripcionController = TextEditingController();

  /// Prevents double-submissions during network requests.
  bool _isSubmitting = false; 
  
  /// Blocks the UI rendering until required catalog dictionaries are loaded.
  bool _isLoadingData = true; 

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _todosLosLugares = []; 

  int? _selectedCategoriaId;
  int? _selectedLugarId; 

  String? _errorLugar;
  String _lugarTextoActual = '';

  XFile? _imagenSeleccionada;
  final ImagePicker _picker = ImagePicker();

  /// UniqueKey to force rebuilding the Autocomplete widget when resetting state.
  Key _autocompleteKey = UniqueKey();

  /// State flags for image modification during Edit Mode.
  String? _imagenViejaUrl;
  bool _eliminoImagenVieja = false;

  /// Computed property to determine current execution mode.
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

  /// Bootstraps the form by loading required catalog dictionaries (Categories and Locations).
  ///
  /// Implements Optimistic UI by loading stale cache first, then asynchronously 
  /// querying Supabase. Finally, hydrates the form based on the current mode (Edit vs Create).
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
      
      // Fetch both dictionaries concurrently to reduce network waterfall delay.
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

  /// Processes raw location data into a flattened, searchable format.
  /// 
  /// Appends the parent building name to classrooms for better Autocomplete UX 
  /// (e.g., "Aula 3 (Sistemas)").
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

  /// Hydrates the form controllers and state variables using the passed report payload.
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

  /// Resolves the specific location entity for the report being edited.
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
          _autocompleteKey = UniqueKey();
        });
      }
    } catch (e) {
      debugPrint("Error cargando ubicación para editar: $e");
    }
  }

  /// Restores the unsaved draft from device storage (Creation Mode only).
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

  /// Silently serializes current form state to SharedPreferences.
  Future<void> _guardarBorrador() async {
    if (_esEdicion) return; // Prevent overwriting drafts while editing an existing report.
    final prefs = await SharedPreferences.getInstance();
    final borrador = {
      'titulo': _tituloController.text,
      'descripcion': _descripcionController.text,
      'categoriaId': _selectedCategoriaId,
      'lugarId': _selectedLugarId,
    };
    await prefs.setString('reporte_borrador', jsonEncode(borrador));
  }

  /// Prompts user confirmation before wiping form state and local storage.
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
        _autocompleteKey = UniqueKey(); 
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
    final XFile? image = await _picker.pickImage(source: origen, imageQuality: 70);
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

  /// Core submission handler.
  ///
  /// Orchestrates data validation, optional binary image upload to Supabase Storage, 
  /// and branches logic to perform either an SQL INSERT (Creation) or UPDATE (Edition).
  Future<void> _enviarReporte() async {
    // 1. Strict Form Validation
    if (_tituloController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa un título.", esError: true);
      return;
    }
    if (_selectedCategoriaId == null) {
      _mostrarMensaje("Selecciona una categoría.", esError: true);
      return;
    }

    if (_selectedLugarId == null && _lugarTextoActual.trim().isNotEmpty) {
      final matchExacto = _todosLosLugares.where((l) =>
          l['nombreBuscable'].toString().toLowerCase() == _lugarTextoActual.trim().toLowerCase()).toList();
      
      if (matchExacto.isNotEmpty) {
        _selectedLugarId = matchExacto.first['id']; 
        setState(() => _errorLugar = null);
      }
    }

    if (_selectedLugarId == null) {
      setState(() => _errorLugar = "Por favor seleccionar un edificio o aula válida");
      _mostrarMensaje("Por favor seleccionar un edificio o aula válida.", esError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      String? evidenciaUrlFinal = _eliminoImagenVieja ? null : _imagenViejaUrl;

      // 2. Binary Upload (If a new image is attached)
      if (_imagenSeleccionada != null) {
        final extension = _imagenSeleccionada!.name.split('.').last;
        final nombreArchivo = '${DateTime.now().millisecondsSinceEpoch}.$extension';
        final rutaArchivo = '$userId/$nombreArchivo';
        final imageBytes = await _imagenSeleccionada!.readAsBytes();

        await supabase.storage.from('evidencias').uploadBinary(
              rutaArchivo,
              imageBytes,
              fileOptions: FileOptions(cacheControl: '3600', upsert: false, contentType: 'image/$extension'),
            );
        evidenciaUrlFinal = supabase.storage.from('evidencias').getPublicUrl(rutaArchivo);
      }

      // 3. Database Mutation
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

        // Clear local storage draft upon successful database insert.
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

    String textLugarInicial = '';
    if (_selectedLugarId != null && _todosLosLugares.isNotEmpty) {
      final lugarEncontrado = _todosLosLugares.firstWhere(
        (l) => l['id'] == _selectedLugarId, 
        orElse: () => {'nombreBuscable': ''}
      );
      textLugarInicial = lugarEncontrado['nombreBuscable'];
    }
    
    _lugarTextoActual = textLugarInicial;

    return Scaffold(
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
            
            Autocomplete<Map<String, dynamic>>(
              key: _autocompleteKey, 
              initialValue: TextEditingValue(text: _lugarTextoActual), 
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<Map<String, dynamic>>.empty();
                }
                final query = textEditingValue.text.toLowerCase();
                return _todosLosLugares.where((lugar) =>
                    lugar['nombreBuscable'].toString().toLowerCase().contains(query));
              },
              displayStringForOption: (option) => option['nombreBuscable'],
              onSelected: (option) {
                setState(() {
                  _selectedLugarId = option['id'];
                  _errorLugar = null; 
                });
                _guardarBorrador(); 
                FocusScope.of(context).unfocus(); 
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: "Buscar edificio o aula...",
                    hintText: "Ej. 19, Sistemas, Aula 3",
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    errorText: _errorLugar, 
                  ),
                  onChanged: (val) {
                    _lugarTextoActual = val; 
                    
                    if (_selectedLugarId != null) {
                      setState(() => _selectedLugarId = null); 
                    }
                    if (_errorLugar != null) {
                      setState(() => _errorLugar = null); 
                    }
                    _guardarBorrador();
                  },
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final anchosCaja = MediaQuery.of(context).size.width - 48; 
                
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 250, maxWidth: anchosCaja),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          final esEdificio = option['padre_nombre'] == '';

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF800000).withValues(alpha: 0.1),
                              child: Icon(
                                esEdificio ? Icons.domain : Icons.meeting_room,
                                color: const Color(0xFF800000),
                              ),
                            ),
                            title: Text(
                              option['nombre'], 
                              style: const TextStyle(fontWeight: FontWeight.bold)
                            ),
                            subtitle: esEdificio
                                ? const Text("Zona / Edificio Principal", style: TextStyle(color: Colors.grey, fontSize: 12))
                                : Text("Pertenece a: ${option['padre_nombre']}", style: const TextStyle(color: Color(0xFF800000), fontSize: 12)),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
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
                            : Image.file(File(_imagenSeleccionada!.path), fit: BoxFit.contain),
                      )
                    : (!_eliminoImagenVieja && _imagenViejaUrl != null)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: _imagenViejaUrl!,
                              fit: BoxFit.contain,
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
    );
  }
}