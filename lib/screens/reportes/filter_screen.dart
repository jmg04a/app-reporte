import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'resultados_busqueda_screen.dart'; 

/// Search and filtering interface for the report catalog.
///
/// Acts as a query parameter builder. Aggregates multiple state variables
/// (text, foreign keys, enums) into a unified filter payload, which is then 
/// passed to the [ResultadosBusquedaScreen] for execution.
class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  // --- Text-based Filters ---
  final _usuarioController = TextEditingController();
  final _tituloController = TextEditingController();

  // --- Relational Dictionaries ---
  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _lugares = [];
  List<Map<String, dynamic>> _carreras = []; 
  
  bool _isLoadingData = true;

  // --- Active Filter States ---
  int? _selectedCategoriaId;
  int? _selectedLugarId;
  int? _selectedCarreraId; 
  
  String _selectedEstado = 'todos';
  String _selectedOrdenReacciones = 'recientes';

  // --- Autocomplete State ---
  String _lugarTextoActual = '';
  Key _autocompleteKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
  }

  /// Bootstraps the form by concurrently fetching all required foreign key dictionaries.
  ///
  /// Implements an Optimistic UI approach by rendering cached dictionaries instantly 
  /// before fetching the fresh catalog from Supabase.
  Future<void> _cargarCatalogos() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 1. Hydrate from local cache
    final catsCache = prefs.getString('categorias_cache');
    final lugsCache = prefs.getString('lugares_cache');
    final carrsCache = prefs.getString('carreras_cache');

    if (catsCache != null && lugsCache != null && carrsCache != null) {
      final catsLocal = jsonDecode(catsCache);
      final lugsLocal = jsonDecode(lugsCache);
      final carrsLocal = jsonDecode(carrsCache);
      _procesarYMostrarCatalogos(catsLocal, lugsLocal, carrsLocal);
    }

    try {
      final supabase = Supabase.instance.client;
      
      // 2. Fetch all dictionaries concurrently to prevent network waterfalls
      final respuestas = await Future.wait([
        supabase.from('cat_categorias').select('id, nombre').order('nombre'),
        supabase.from('cat_lugares').select('id, nombre, tipo, parent_id').order('nombre'),
        supabase.from('cat_carreras').select('id, nombre').order('nombre') 
      ]);

      final catsNube = respuestas[0];
      final lugsNube = respuestas[1];
      final carrsNube = respuestas[2];

      // 3. Persist fresh data back to local storage
      prefs.setString('categorias_cache', jsonEncode(catsNube));
      prefs.setString('lugares_cache', jsonEncode(lugsNube));
      prefs.setString('carreras_cache', jsonEncode(carrsNube));

      _procesarYMostrarCatalogos(catsNube, lugsNube, carrsNube);
    } catch (e) {
      // Fallback: If network fails and cache is empty, stop the loading spinner
      if (mounted && _categorias.isEmpty) setState(() => _isLoadingData = false);
    }
  }

  /// Flattens the hierarchical location data into a 1D searchable array.
  /// 
  /// Resolves the 'parent_id' relationship to append the parent building name
  /// to specific rooms (e.g., "Aula 3" becomes "Aula 3 (Sistemas)") for better UX.
  void _procesarYMostrarCatalogos(List<dynamic> catsRaw, List<dynamic> lugsRaw, List<dynamic> carrsRaw) {
    List<Map<String, dynamic>> lugaresFormateados = [];
    
    for (var lugar in lugsRaw) {
      String nombre = lugar['nombre'];
      String padreNombre = '';

      if (lugar['parent_id'] != null) {
        final padre = lugsRaw.firstWhere(
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
        _categorias = List<Map<String, dynamic>>.from(catsRaw);
        _lugares = lugaresFormateados;
        _carreras = List<Map<String, dynamic>>.from(carrsRaw); 
        _isLoadingData = false; 
      });
    }
  }

  /// Compiles the active state into a unified payload and triggers navigation.
  void _aplicar() {
    // Validation: Ensure the typed location actually maps to a valid foreign key ID
    if (_selectedLugarId == null && _lugarTextoActual.trim().isNotEmpty) {
      final matchExacto = _lugares.where((l) =>
          l['nombreBuscable'].toString().toLowerCase() == _lugarTextoActual.trim().toLowerCase()).toList();
      
      if (matchExacto.isNotEmpty) {
        _selectedLugarId = matchExacto.first['id']; 
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("El lugar escrito no es válido. Selecciona uno de la lista o borra el texto."), backgroundColor: Colors.red),
        );
        return;
      }
    }

    // Construction of the query payload
    final filtros = {
      'usuario': _usuarioController.text.trim(),
      'titulo': _tituloController.text.trim(),
      'categoriaId': _selectedCategoriaId,
      'lugarId': _selectedLugarId,
      'carreraId': _selectedCarreraId, 
      'estado': _selectedEstado,
      'ordenReacciones': _selectedOrdenReacciones,
    };
    
    // Imperative routing to the results view, replacing the current route
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ResultadosBusquedaScreen(filtros: filtros),
      ),
    );
  }

  /// Prompts for confirmation before executing a full state wipe.
  Future<void> _confirmarLimpiar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_sweep, color: Colors.red),
            SizedBox(width: 10),
            Text("Limpiar filtros"),
          ],
        ),
        content: const Text("¿Estás seguro de que deseas borrar todos los campos de búsqueda?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sí, limpiar"),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      _limpiar();
    }
  }

  /// Resets all form controllers and active state variables to their default values.
  void _limpiar() {
    setState(() {
      _usuarioController.clear();
      _tituloController.clear();
      _selectedCategoriaId = null;
      _selectedLugarId = null;
      _selectedCarreraId = null; 
      _selectedEstado = 'todos';
      _selectedOrdenReacciones = 'recientes';
      _lugarTextoActual = '';
      
      // Forcing a new UniqueKey ensures the Autocomplete widget fully rebuilds and clears its internal state.
      _autocompleteKey = UniqueKey(); 
    });
  }

  @override
  Widget build(BuildContext context) {
    // --- Defensive Checks ---
    // Ensure selected IDs actually exist in the fetched dictionaries to prevent crash on Dropdown rendering.
    bool categoriaExiste = _selectedCategoriaId == null || _categorias.any((c) => c['id'] == _selectedCategoriaId);
    int? safeCategoriaId = categoriaExiste ? _selectedCategoriaId : null;

    bool carreraExiste = _selectedCarreraId == null || _carreras.any((c) => c['id'] == _selectedCarreraId);
    int? safeCarreraId = carreraExiste ? _selectedCarreraId : null;

    const estadosValidos = ['todos', 'pendiente', 'en proceso', 'finalizado'];
    String safeEstado = estadosValidos.contains(_selectedEstado) ? _selectedEstado : 'todos';

    const ordenValidos = ['recientes', 'desc', 'asc'];
    String safeOrden = ordenValidos.contains(_selectedOrdenReacciones) ? _selectedOrdenReacciones : 'recientes';

    String textLugarInicial = '';
    if (_selectedLugarId != null && _lugares.isNotEmpty) {
      final lugarEncontrado = _lugares.firstWhere(
        (l) => l['id'] == _selectedLugarId, 
        orElse: () => {'nombreBuscable': ''}
      );
      textLugarInicial = lugarEncontrado['nombreBuscable'];
    }
    
    _lugarTextoActual = textLugarInicial;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Filtros de Búsqueda"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
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
                    isExpanded: true,
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
                    key: _autocompleteKey,
                    initialValue: TextEditingValue(text: textLugarInicial),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<Map<String, dynamic>>.empty();
                      }
                      final query = textEditingValue.text.toLowerCase();
                      return _lugares.where((lugar) =>
                          lugar['nombreBuscable'].toString().toLowerCase().contains(query));
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
                          labelText: "Ubicación (Opcional)",
                          hintText: "Ej. 19, Sistemas, Aula 3",
                          prefixIcon: const Icon(Icons.location_on),
                          border: const OutlineInputBorder(),
                          // Clear button inside the Autocomplete text field
                          suffixIcon: _selectedLugarId != null || _lugarTextoActual.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, color: Colors.grey),
                                  onPressed: () {
                                    controller.clear();
                                    setState(() {
                                      _selectedLugarId = null;
                                      _lugarTextoActual = '';
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (val) {
                          _lugarTextoActual = val;
                          if (_selectedLugarId != null) {
                            setState(() => _selectedLugarId = null);
                          }
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      final anchosCaja = MediaQuery.of(context).size.width - 40; 
                      
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

                  const SizedBox(height: 15),

                  DropdownButtonFormField<int>(
                    isExpanded: true, 
                    initialValue: safeCarreraId, 
                    decoration: const InputDecoration(labelText: "Carrera del estudiante (Opcional)", prefixIcon: Icon(Icons.school), border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text("Cualquier carrera")),
                      ..._carreras.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text(c['nombre']))),
                    ],
                    onChanged: (val) => setState(() => _selectedCarreraId = val),
                  ),

                  const SizedBox(height: 15),

                  DropdownButtonFormField<String>(
                    isExpanded: true, 
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
                          icon: const Icon(Icons.search), 
                          label: const Text("BUSCAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          onPressed: _aplicar,
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
                        onPressed: _confirmarLimpiar,
                        child: const Icon(Icons.delete_outline), 
                      ),
                    ],
                  )
                ],
              ),
            ),
    );
  }
}