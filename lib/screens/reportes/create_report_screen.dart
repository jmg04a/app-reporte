import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateReportScreen extends StatefulWidget {
  const CreateReportScreen({super.key});

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _tituloController = TextEditingController();
  final _descripcionController = TextEditingController();

  bool _isLoading = false;

  // Variables para los Dropdowns
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _edificios = [];
  List<Map<String, dynamic>> _aulas = []; 

  int? _selectedCategoriaId;
  int? _selectedEdificioId;
  int? _selectedAulaId;

  @override
  void initState() {
    super.initState();
    _cargarDatosIniciales();
  }

  Future<void> _cargarDatosIniciales() async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Cargar Categorías (con ícono y color)
      final categoriasData = await supabase.from('cat_categorias').select('id, nombre, icono, color').order('nombre');
      
      // 2. Cargar Edificios principales (sin parent_id)
      final edificiosData = await supabase
          .from('cat_lugares')
          .select('id, nombre')
          .isFilter('parent_id', null) 
          .order('nombre');

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

      final aulasData = await Supabase.instance.client
          .from('cat_lugares')
          .select('id, nombre')
          .eq('parent_id', edificioId)
          .order('nombre');

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
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : Colors.green,
      ),
    );
  }

  // --- FUNCIONES PARA ÍCONOS Y COLORES ---
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
  // ----------------------------------------

  // --- LÓGICA DE ENVÍO DE REPORTE (DOS TABLAS) ---
  Future<void> _enviarReporte() async {
    if (_tituloController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa un título.", esError: true);
      return;
    }
    if (_descripcionController.text.trim().isEmpty) {
      _mostrarMensaje("Por favor ingresa una descripción.", esError: true);
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

      // PASO 1: Insertar en la tabla 'reportes' y obtener el ID
      final reporteInsertado = await supabase.from('reportes').insert({
        'titulo': _tituloController.text.trim(),
        'descripcion': _descripcionController.text.trim(),
        'categoria_id': _selectedCategoriaId,
        'usuario_id': userId,
        'estado': 'pendiente', 
      }).select('id').single(); 

      final reporteId = reporteInsertado['id'];

      // PASO 2: Insertar la ubicación en la tabla 'reporte_ubicaciones'
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
            const Text(
              "¿Qué está fallando?",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _tituloController,
              decoration: const InputDecoration(
                labelText: "Título breve",
                hintText: "Ej. Proyector no enciende",
                prefixIcon: Icon(Icons.short_text),
                border: OutlineInputBorder(),
              ),
              maxLength: 50,
            ),
            const SizedBox(height: 15),

            // CATEGORÍA (Con íconos y colores)
            DropdownButtonFormField<int>(
              initialValue: _selectedCategoriaId,
              decoration: const InputDecoration(
                labelText: "Categoría",
                prefixIcon: Icon(Icons.category_outlined),
                border: OutlineInputBorder(),
              ),
              items: _categorias.map((cat) {
                return DropdownMenuItem<int>(
                  value: cat['id'],
                  child: Row(
                    children: [
                      Icon(
                        _getIconFromName(cat['icono']),
                        color: _getColorFromHex(cat['color']),
                      ),
                      const SizedBox(width: 10),
                      Text(cat['nombre']),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedCategoriaId = val),
              hint: const Text("Selecciona el tipo de problema"),
            ),
            const SizedBox(height: 20),

            const Divider(),
            const SizedBox(height: 10),
            const Text(
              "Ubicación del problema",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // EDIFICIO
            DropdownButtonFormField<int>(
              initialValue: _selectedEdificioId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: "Edificio / Zona",
                prefixIcon: Icon(Icons.domain),
                border: OutlineInputBorder(),
              ),
              items: _edificios.map((edificio) {
                return DropdownMenuItem<int>(
                  value: edificio['id'],
                  child: Text(edificio['nombre'], overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedEdificioId = val);
                if (val != null) {
                  _cargarAulas(val); 
                }
              },
              hint: const Text("Selecciona el edificio"),
            ),
            const SizedBox(height: 15),

            // AULA (Opcional, cambia al elegir Edificio)
            if (_selectedEdificioId != null)
              DropdownButtonFormField<int>(
                key: ValueKey(_selectedEdificioId), 
                initialValue: _selectedAulaId,      
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "Aula / Laboratorio (Opcional)",
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _aulas.map((aula) {
                  return DropdownMenuItem<int>(
                    value: aula['id'],
                    child: Text(aula['nombre'], overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _selectedAulaId = val),
                hint: _aulas.isEmpty 
                    ? const Text("Este lugar no tiene aulas específicas")
                    : const Text("Selecciona el aula exacta"),
              ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 15),

            // DESCRIPCIÓN
            TextField(
              controller: _descripcionController,
              decoration: const InputDecoration(
                labelText: "Descripción detallada",
                hintText: "Explica con más detalle cuál es el problema...",
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
              keyboardType: TextInputType.multiline,
            ),
            const SizedBox(height: 30),

            // BOTÓN ENVIAR
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}