import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert'; // Para convertir a JSON
import 'package:shared_preferences/shared_preferences.dart'; // Para el disco duro local

class FilterScreen extends StatefulWidget {
  final Map<String, dynamic> filtrosActuales;

  const FilterScreen({super.key, required this.filtrosActuales});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final _usuarioController = TextEditingController();
  final _tituloController = TextEditingController();

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _lugares = [];
  bool _isLoadingData = true;

  int? _selectedCategoriaId;
  int? _selectedLugarId;
  String _selectedEstado = 'todos';
  String _selectedOrdenReacciones = 'recientes';

  @override
  void initState() {
    super.initState();
    _cargarFiltrosPrevios();
    _cargarCatalogos();
  }

  void _cargarFiltrosPrevios() {
    _usuarioController.text = widget.filtrosActuales['usuario'] ?? '';
    _tituloController.text = widget.filtrosActuales['titulo'] ?? '';
    _selectedCategoriaId = widget.filtrosActuales['categoriaId'];
    _selectedLugarId = widget.filtrosActuales['lugarId'];
    _selectedEstado = widget.filtrosActuales['estado'] ?? 'todos';
    _selectedOrdenReacciones = widget.filtrosActuales['ordenReacciones'] ?? 'recientes';
  }

  Future<void> _cargarCatalogos() async {
    final prefs = await SharedPreferences.getInstance();
    final catsCache = prefs.getString('categorias_cache');
    final lugsCache = prefs.getString('lugares_cache');

    // 1. CARGA SÚPER RÁPIDA DESDE EL TELÉFONO (Si ya habíamos entrado antes)
    if (catsCache != null && lugsCache != null) {
      final catsLocal = jsonDecode(catsCache);
      final lugsLocal = jsonDecode(lugsCache);
      _procesarYMostrarCatalogos(catsLocal, lugsLocal);
    }

    // 2. ACTUALIZACIÓN SILENCIOSA DE FONDO (O primera vez si no hay caché)
    try {
      final supabase = Supabase.instance.client;
      
      // Usamos Future.wait para descargar ambas cosas al mismo tiempo (el doble de rápido)
      final respuestas = await Future.wait([
        supabase.from('cat_categorias').select('id, nombre').order('nombre'),
        supabase.from('cat_lugares').select('id, nombre, tipo, parent_id').order('nombre')
      ]);

      final catsNube = respuestas[0];
      final lugsNube = respuestas[1];

      // Guardamos en el disco duro para el futuro
      prefs.setString('categorias_cache', jsonEncode(catsNube));
      prefs.setString('lugares_cache', jsonEncode(lugsNube));

      // Actualizamos la pantalla con los datos más frescos
      _procesarYMostrarCatalogos(catsNube, lugsNube);
    } catch (e) {
      // Si el alumno no tiene internet en este momento, no importa.
      // Si ya tenía la caché cargada, la pantalla seguirá funcionando perfecto offline.
      if (mounted && _categorias.isEmpty) setState(() => _isLoadingData = false);
    }
  }

  // Separamos la lógica de formato para no repetir código
  void _procesarYMostrarCatalogos(List<dynamic> catsRaw, List<dynamic> lugsRaw) {
    List<Map<String, dynamic>> lugaresFormateados = [];
    
    for (var lugar in lugsRaw) {
      String nombreMostrar = lugar['nombre'];
      
      if (lugar['tipo'] == 'aula' && lugar['parent_id'] != null) {
        final padre = lugsRaw.firstWhere(
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
        _categorias = List<Map<String, dynamic>>.from(catsRaw);
        _lugares = lugaresFormateados;
        _isLoadingData = false; // Apagamos la rueda de carga si estaba encendida
      });
    }
  }

  void _aplicar() {
    final filtros = {
      'usuario': _usuarioController.text.trim(),
      'titulo': _tituloController.text.trim(),
      'categoriaId': _selectedCategoriaId,
      'lugarId': _selectedLugarId,
      'estado': _selectedEstado,
      'ordenReacciones': _selectedOrdenReacciones,
    };
    Navigator.pop(context, filtros);
  }

  void _limpiar() {
    setState(() {
      _usuarioController.clear();
      _tituloController.clear();
      _selectedCategoriaId = null;
      _selectedLugarId = null;
      _selectedEstado = 'todos';
      _selectedOrdenReacciones = 'recientes';
    });
  }

  @override
  Widget build(BuildContext context) {
    // --- INICIO DE SEGUROS DE VIDA PARA EVITAR CRASHES ---
    
    // 1. Seguro para Categorías
    // Verificamos si el ID guardado realmente existe en la base de datos actual
    bool categoriaExiste = _selectedCategoriaId == null || 
        _categorias.any((c) => c['id'] == _selectedCategoriaId);
    int? safeCategoriaId = categoriaExiste ? _selectedCategoriaId : null;

    // 2. Seguro para Estados
    const estadosValidos = ['todos', 'pendiente', 'en proceso', 'finalizado'];
    String safeEstado = estadosValidos.contains(_selectedEstado) ? _selectedEstado : 'todos';

    // 3. Seguro para Ordenamiento
    const ordenValidos = ['recientes', 'desc', 'asc'];
    String safeOrden = ordenValidos.contains(_selectedOrdenReacciones) ? _selectedOrdenReacciones : 'recientes';

    // 4. Buscamos el nombre del lugar previo (Este ya lo tenías bien asegurado con el orElse)
    String textLugarInicial = '';
    if (_selectedLugarId != null && _lugares.isNotEmpty) {
      final lugarEncontrado = _lugares.firstWhere(
        (l) => l['id'] == _selectedLugarId, 
        orElse: () => {'nombreBuscable': ''}
      );
      textLugarInicial = lugarEncontrado['nombreBuscable'];
    }
    // --- FIN DE SEGUROS DE VIDA ---

    return Scaffold(
      appBar: AppBar(
        title: const Text("Filtrar Reportes"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _limpiar,
            child: const Text("LIMPIAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Búsqueda por Texto", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tituloController,
                    decoration: const InputDecoration(labelText: "Título del reporte", prefixIcon: Icon(Icons.title), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _usuarioController,
                    decoration: const InputDecoration(labelText: "Usuario (Nombre o No. Control)", prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                  ),
                  
                  const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),

                  const Text("Búsqueda por Atributos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 10),
                  
                  DropdownButtonFormField<int>(
                    // Usamos nuestra variable segura en lugar del _selectedCategoriaId directo
                    initialValue: safeCategoriaId, 
                    decoration: const InputDecoration(labelText: "Categoría", prefixIcon: Icon(Icons.category), border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text("Todas las categorías")),
                      ..._categorias.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['nombre']))),
                    ],
                    onChanged: (val) => setState(() => _selectedCategoriaId = val),
                  ),
                  const SizedBox(height: 15),
                  
                  Autocomplete<Map<String, dynamic>>(
                    initialValue: TextEditingValue(text: textLugarInicial),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      return _lugares.where((lugar) =>
                          lugar['nombreBuscable']
                              .toString()
                              .toLowerCase()
                              .contains(textEditingValue.text.toLowerCase()));
                    },
                    displayStringForOption: (option) => option['nombreBuscable'],
                    onSelected: (option) {
                      setState(() => _selectedLugarId = option['id']);
                      FocusScope.of(context).unfocus();
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: "Ubicación",
                          hintText: "Escribe el edificio o aula...",
                          prefixIcon: const Icon(Icons.location_on),
                          border: const OutlineInputBorder(),
                          suffixIcon: _selectedLugarId != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () {
                                    controller.clear();
                                    setState(() => _selectedLugarId = null);
                                  },
                                )
                              : null,
                        ),
                        onChanged: (val) {
                          if (val.isEmpty) setState(() => _selectedLugarId = null);
                        },
                      );
                    },
                  ),
                  
                  const SizedBox(height: 15),

                  DropdownButtonFormField<String>(
                    // Variable segura
                    initialValue: safeEstado,
                    decoration: const InputDecoration(labelText: "Estado", prefixIcon: Icon(Icons.flag), border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text("Todos los estados")),
                      DropdownMenuItem(value: 'pendiente', child: Text("Pendiente")),
                      DropdownMenuItem(value: 'en proceso', child: Text("En Proceso")),
                      DropdownMenuItem(value: 'finalizado', child: Text("Finalizado")),
                    ],
                    onChanged: (val) => setState(() => _selectedEstado = val!),
                  ),
                  
                  const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider()),

                  const Text("Ordenamiento", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey)),
                  const SizedBox(height: 10),
                  
                  DropdownButtonFormField<String>(
                    // Variable segura
                    initialValue: safeOrden,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: "Ordenar por Reacciones", prefixIcon: Icon(Icons.favorite), border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'recientes', child: Text("Los más recientes primero (Por defecto)", overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'desc', child: Text("Más a menos reacciones", overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: 'asc', child: Text("Menos a más reacciones", overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (val) => setState(() => _selectedOrdenReacciones = val!),
                  ),

                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF800000),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16)
                    ),
                    icon: const Icon(Icons.filter_alt),
                    label: const Text("APLICAR FILTROS", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    onPressed: _aplicar,
                  )
                ],
              ),
            ),
    );
  }
}