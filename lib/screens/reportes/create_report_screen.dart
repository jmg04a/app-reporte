import 'dart:io'; 
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // <-- NUEVO: Para saber si estamos en Web
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
  List<Map<String, dynamic>> _edificios = [];
  List<Map<String, dynamic>> _aulas = []; 

  int? _selectedCategoriaId;
  int? _selectedEdificioId;
  int? _selectedAulaId;

  // --- NUEVO: Usamos XFile en lugar de File para compatibilidad total ---
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
      final categoriasData = await supabase.from('cat_categorias').select('id, nombre, icono, color').order('nombre');
      final edificiosData = await supabase.from('cat_lugares').select('id, nombre').isFilter('parent_id', null).order('nombre');

      if (mounted) {
        setState(() {
          _categorias = List<Map<String, dynamic>>.from(categoriasData);
          _edificios = List<Map<String, dynamic>>.from(edificiosData);
        });
      }
    } catch (e) {
      _mostrarMensaje("Error cargando catálogos: $e", esError: true);
    }
  }

  Future<void> _cargarAulas(int edificioId) async {
    try {
      setState(() {
        _selectedAulaId = null;
        _aulas = [];
      });
      final aulasData = await Supabase.instance.client.from('cat_lugares').select('id, nombre').eq('parent_id', edificioId).order('nombre');
      if (mounted) {
        setState(() {
          _aulas = List<Map<String, dynamic>>.from(aulasData);
        });
      }
    } catch (e) {
      _mostrarMensaje("Error cargando aulas: $e", esError: true);
    }
  }

  void _mostrarMensaje(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje), backgroundColor: esError ? Colors.red : Colors.green),
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

  Future<void> _seleccionarImagen() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, 
    );

    if (image != null) {
      setState(() {
        _imagenSeleccionada = image; // Guardamos el XFile directamente
      });
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
    if (_selectedEdificioId == null) {
      _mostrarMensaje("Selecciona un edificio.", esError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser!.id;
      final lugarFinalId = _selectedAulaId ?? _selectedEdificioId;

      String? evidenciaUrlFinal;

      // --- NUEVA LÓGICA DE SUBIDA COMPATIBLE CON WEB ---
      if (_imagenSeleccionada != null) {
        // Sacamos la extensión del nombre del archivo (ej. jpg, png)
        final extension = _imagenSeleccionada!.name.split('.').last;
        final nombreArchivo = '${DateTime.now().millisecondsSinceEpoch}.$extension';
        final rutaArchivo = '$userId/$nombreArchivo'; 

        // Convertimos la imagen a Bytes (funciona en Web, Android, iOS, PC)
        final imageBytes = await _imagenSeleccionada!.readAsBytes();

        // Usamos uploadBinary en lugar de upload normal
        await supabase.storage.from('evidencias').uploadBinary(
              rutaArchivo,
              imageBytes,
              fileOptions: FileOptions(
                cacheControl: '3600', 
                upsert: false,
                contentType: 'image/$extension', // Ayuda al navegador a saber que es una imagen
              ),
            );

        evidenciaUrlFinal = supabase.storage.from('evidencias').getPublicUrl(rutaArchivo);
      }

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
        'lugar_id': lugarFinalId,
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

            DropdownButtonFormField<int>(
              initialValue: _selectedEdificioId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: "Edificio / Zona", prefixIcon: Icon(Icons.domain), border: OutlineInputBorder()),
              items: _edificios.map((edificio) {
                return DropdownMenuItem<int>(value: edificio['id'], child: Text(edificio['nombre'], overflow: TextOverflow.ellipsis));
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedEdificioId = val);
                if (val != null) _cargarAulas(val); 
              },
            ),
            const SizedBox(height: 15),

            if (_selectedEdificioId != null)
              DropdownButtonFormField<int>(
                key: ValueKey(_selectedEdificioId), 
                initialValue: _selectedAulaId,      
                isExpanded: true,
                decoration: const InputDecoration(labelText: "Aula / Laboratorio (Opcional)", prefixIcon: Icon(Icons.meeting_room_outlined), border: OutlineInputBorder()),
                items: _aulas.map((aula) {
                  return DropdownMenuItem<int>(value: aula['id'], child: Text(aula['nombre'], overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (val) => setState(() => _selectedAulaId = val),
                hint: _aulas.isEmpty ? const Text("Sin aulas específicas") : const Text("Selecciona el aula exacta"),
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

            // --- SECCIÓN DE EVIDENCIA (PREVIEW DE IMAGEN) ---
            const Text("Evidencia fotográfica (Opcional)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            InkWell(
              onTap: _seleccionarImagen,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity, // Que ocupe todo el ancho de la pantalla
                // Restringimos la altura máxima a 400 para que fotos muy largas no ocupen toda la pantalla
                constraints: const BoxConstraints(maxHeight: 400), 
                decoration: BoxDecoration(
                  color: Colors.grey[200], 
                  border: Border.all(color: Colors.grey[400]!), 
                  borderRadius: BorderRadius.circular(8)
                ),
                child: _imagenSeleccionada != null
                    // SI HAY IMAGEN: Toma su proporción natural sin recortarse
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: kIsWeb 
                          ? Image.network(_imagenSeleccionada!.path, fit: BoxFit.contain)
                          : Image.file(File(_imagenSeleccionada!.path), fit: BoxFit.contain),
                      )
                    // SI NO HAY IMAGEN: Mostramos la cajita fija de 150px
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
            
            // Botón para quitar la foto
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF800000), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
          ],
        ),
      ),
    );
  }
}