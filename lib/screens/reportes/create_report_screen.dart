import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

class CreateReportScreen extends StatefulWidget {
  const CreateReportScreen({super.key});

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _tituloController = TextEditingController();
  final _descripcionController = TextEditingController();

  bool _isLoading = false;

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _todosLosLugares = []; // Nueva lista para el buscador inteligente

  int? _selectedCategoriaId;
  int? _selectedLugarId; // Sustituye a edificioId y aulaId

  XFile? _imagenSeleccionada;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final supabase = Supabase.instance.client;
      
      // 1. Descargamos Categorías
      final categoriasData = await supabase
          .from('cat_categorias')
          .select('id, nombre, icono, color')
          .order('nombre');

      // 2. Descargamos TODOS los lugares para el buscador
      final lugaresData = await supabase
          .from('cat_lugares')
          .select('id, nombre, tipo, parent_id')
          .order('nombre');

      // 3. Formateamos los lugares en la memoria del celular para que el buscador sea instantáneo
      List<Map<String, dynamic>> lugaresFormateados = [];
      for (var lugar in lugaresData) {
        String nombreMostrar = lugar['nombre'];
        
        // Si es un aula, buscamos el nombre de su edificio para darle contexto al usuario (Ej. "Aula 1 (Edificio Sistemas)")
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
    } catch (e) {
      _mostrarMensaje("Error cargando catálogos: $e", esError: true);
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
    // 1. Validaciones
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

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;

      // --- RADAR DE DUPLICADOS ---
      final duplicados = await supabase
          .from('reportes')
          .select('id, titulo, estado, reporte_ubicaciones!inner(lugar_id)')
          .eq('categoria_id', _selectedCategoriaId!)
          .neq('estado', 'finalizado') // Omitimos los ya resueltos
          .eq('reporte_ubicaciones.lugar_id', _selectedLugarId!);

      if (duplicados.isNotEmpty && mounted) {
        setState(() => _isLoading = false);
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
        setState(() => _isLoading = true);
      }
      // --- FIN RADAR ---

      // 2. Subir imagen (si hay)
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

      // 3. Guardar el reporte principal
      final reporteInsertado = await supabase.from('reportes').insert({
        'titulo': _tituloController.text.trim(),
        'descripcion': _descripcionController.text.trim(),
        'categoria_id': _selectedCategoriaId,
        'usuario_id': userId,
        'estado': 'pendiente',
        'evidencia_url': evidenciaUrlFinal,
      }).select('id').single();

      final reporteId = reporteInsertado['id'];

      // 4. Guardar la ubicación
      await supabase.from('reporte_ubicaciones').insert({
        'reporte_id': reporteId,
        'lugar_id': _selectedLugarId,
      });

      if (!mounted) return;
      _mostrarMensaje("¡Reporte enviado con éxito!");
      Navigator.pop(context);

    } catch (e) {
      _mostrarMensaje("Error al enviar reporte: $e", esError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Nuevo Reporte"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
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
              onChanged: (val) => setState(() => _selectedCategoriaId = val),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            
            const Text("Ubicación del problema", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            // --- AQUÍ ESTÁ EL BUSCADOR INTELIGENTE TIPO YOUTUBE ---
            Autocomplete<Map<String, dynamic>>(
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
                FocusScope.of(context).unfocus(); // Oculta el teclado al elegir
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
                    // Si el usuario borra el texto, quitamos el ID seleccionado
                    if (val.isEmpty) {
                      setState(() => _selectedLugarId = null);
                    }
                  },
                );
              },
            ),
            // --------------------------------------------------------

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

            if (_isLoading)
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