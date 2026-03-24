import 'dart:io';
import 'dart:convert'; // Para convertir el borrador a texto
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Para guardar el borrador

class CreateReportScreen extends StatefulWidget {
  const CreateReportScreen({super.key});

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _tituloController = TextEditingController();
  final _descripcionController = TextEditingController();

  bool _isSubmitting = false; // Rueda de carga del botón enviar
  bool _isLoadingData = true; // Rueda de carga al abrir la pantalla

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _todosLosLugares = []; 

  int? _selectedCategoriaId;
  int? _selectedLugarId; 

  XFile? _imagenSeleccionada;
  final ImagePicker _picker = ImagePicker();

  // Esta llave nos servirá para reiniciar el buscador de lugares cuando limpiemos el borrador
  Key _autocompleteKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  @override
  void dispose() {
    _tituloController.removeListener(_guardarBorrador);
    _descripcionController.removeListener(_guardarBorrador);
    _tituloController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final supabase = Supabase.instance.client;
      
      // 1. Descargamos Categorías
      final categoriasData = await supabase
          .from('cat_categorias')
          .select('id, nombre, icono, color')
          .order('nombre');

      // 2. Descargamos Lugares
      final lugaresData = await supabase
          .from('cat_lugares')
          .select('id, nombre, tipo, parent_id')
          .order('nombre');

      List<Map<String, dynamic>> lugaresFormateados = [];
      for (var lugar in lugaresData) {
        String nombreMostrar = lugar['nombre'];
        if (lugar['tipo'] == 'aula' && lugar['parent_id'] != null) {
          final padre = lugaresData.firstWhere(
            (element) => element['id'] == lugar['parent_id'], 
            orElse: () => {'nombre': ''}
          );
          if (padre['nombre'] != '') {
            nombreMostrar = '$nombreMostrar (${padre['nombre']})';
          }
        }
        lugaresFormateados.add({
          'id': lugar['id'],
          'nombreBuscable': nombreMostrar,
        });
      }

      if (mounted) {
        setState(() {
          _categorias = List<Map<String, dynamic>>.from(categoriasData);
          _todosLosLugares = lugaresFormateados;
        });
      }

      // 3. ¡NUEVO! Cargamos el borrador si existe, DESPUÉS de cargar los catálogos
      await _cargarBorrador();

    } catch (e) {
      _mostrarMensaje("Error cargando catálogos: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  // --- LÓGICA DE BORRADOR (AUTOGUARDADO) ---

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

    // Le decimos a los campos de texto que guarden automáticamente cada vez que el usuario escriba una letra
    _tituloController.addListener(_guardarBorrador);
    _descripcionController.addListener(_guardarBorrador);
  }

  Future<void> _guardarBorrador() async {
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
    // Confirmación antes de borrar
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Descartar reporte"),
        content: const Text("¿Estás seguro de que deseas borrar todo lo que has escrito?"),
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('reporte_borrador'); // Borramos de la memoria

      setState(() {
        // Limpiamos la pantalla
        _tituloController.clear();
        _descripcionController.clear();
        _selectedCategoriaId = null;
        _selectedLugarId = null;
        _imagenSeleccionada = null;
        _autocompleteKey = UniqueKey(); // Reiniciamos el buscador de texto forzosamente
      });
    }
  }

  // ----------------------------------------

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
      setState(() => _imagenSeleccionada = image);
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

  Future<void> _enviarReporte() async {
    if (_tituloController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa un título.", esError: true);
      return;
    }
    if (_selectedCategoriaId == null) {
      _mostrarMensaje("Selecciona una categoría.", esError: true);
      return;
    }
    if (_selectedLugarId == null) {
      _mostrarMensaje("Por favor busca y selecciona una ubicación.", esError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      // --- RADAR DE DUPLICADOS ---
      final duplicados = await supabase
          .from('reportes')
          .select('id, titulo, estado, reporte_ubicaciones!inner(lugar_id)')
          .eq('categoria_id', _selectedCategoriaId!)
          .neq('estado', 'finalizado') 
          .eq('reporte_ubicaciones.lugar_id', _selectedLugarId!);

      if (duplicados.isNotEmpty && mounted) {
        setState(() => _isSubmitting = false);
        final tituloDuplicado = duplicados[0]['titulo'];
        
        final continuar = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 10),
                Text("Posible duplicado"),
              ],
            ),
            content: Text(
                "Parece que alguien ya reportó un problema similar aquí:\n\n"
                "'$tituloDuplicado'\n\n"
                "¿Estás seguro de que quieres crear un reporte nuevo?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF800000), foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Sí, enviar"),
              ),
            ],
          ),
        );

        if (continuar != true) return;
        setState(() => _isSubmitting = true);
      }

      // Subir imagen (si hay)
      String? evidenciaUrlFinal;
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

      // Guardar el reporte principal
      final reporteInsertado = await supabase.from('reportes').insert({
        'titulo': _tituloController.text.trim(),
        'descripcion': _descripcionController.text.trim(),
        'categoria_id': _selectedCategoriaId,
        'usuario_id': userId,
        'estado': 'pendiente',
        'evidencia_url': evidenciaUrlFinal,
      }).select('id').single();

      final reporteId = reporteInsertado['id'];

      // Guardar la ubicación
      await supabase.from('reporte_ubicaciones').insert({
        'reporte_id': reporteId,
        'lugar_id': _selectedLugarId,
      });

      // ¡NUEVO! Como el reporte ya se envió, borramos el borrador guardado en el teléfono
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('reporte_borrador');

      if (!mounted) return;
      _mostrarMensaje("¡Reporte enviado con éxito!");
      Navigator.pop(context);

    } catch (e) {
      _mostrarMensaje("Error al enviar reporte: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Si todavía estamos extrayendo los datos y el borrador de la memoria, mostramos una carga inicial
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Nuevo Reporte"),
          backgroundColor: const Color(0xFF800000),
        ),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF800000))),
      );
    }

    // Preparamos el texto del buscador de lugares para que coincida con el borrador recuperado
    String textLugarInicial = '';
    if (_selectedLugarId != null && _todosLosLugares.isNotEmpty) {
      final lugarEncontrado = _todosLosLugares.firstWhere(
        (l) => l['id'] == _selectedLugarId, 
        orElse: () => {'nombreBuscable': ''}
      );
      textLugarInicial = lugarEncontrado['nombreBuscable'];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Nuevo Reporte"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        actions: [
          // ¡NUEVO! Botón para descartar/limpiar el borrador
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: "Limpiar reporte",
            onPressed: _limpiarBorrador,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("¿Qué está fallando?", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                _guardarBorrador(); // Autoguardado al cambiar opción
              },
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            
            const Text("Ubicación del problema", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            // BUSCADOR INTELIGENTE
            Autocomplete<Map<String, dynamic>>(
              key: _autocompleteKey, // Esto permite reiniciarlo desde el botón limpiar
              initialValue: TextEditingValue(text: textLugarInicial), // Carga el borrador
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<Map<String, dynamic>>.empty();
                }
                return _todosLosLugares.where((lugar) =>
                    lugar['nombreBuscable']
                        .toString()
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
              },
              displayStringForOption: (option) => option['nombreBuscable'],
              onSelected: (option) {
                setState(() => _selectedLugarId = option['id']);
                _guardarBorrador(); // Autoguardado al seleccionar ubicación
                FocusScope.of(context).unfocus(); 
              },
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: "Buscar edificio o aula...",
                    hintText: "Ej. 19, Sistemas, Aula 3",
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    if (val.isEmpty) {
                      setState(() => _selectedLugarId = null);
                      _guardarBorrador();
                    }
                  },
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

            if (_imagenSeleccionada != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _imagenSeleccionada = null),
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  label: const Text("Quitar foto", style: TextStyle(color: Colors.red)),
                ),
              ),
            const SizedBox(height: 30),

            if (_isSubmitting)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton.icon(
                onPressed: _enviarReporte,
                icon: const Icon(Icons.send),
                label: const Text("ENVIAR REPORTE", style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF800000),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
          ],
        ),
      ),
    );
  }
}