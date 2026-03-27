import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert'; 
import 'package:shared_preferences/shared_preferences.dart'; 
import 'resultados_busqueda_screen.dart'; 

class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  final _usuarioController = TextEditingController();
  final _tituloController = TextEditingController();

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _lugares = [];
  List<Map<String, dynamic>> _carreras = []; // ¡NUEVO: Lista de carreras!
  
  bool _isLoadingData = true;

  int? _selectedCategoriaId;
  int? _selectedLugarId;
  int? _selectedCarreraId; // ¡NUEVO: Control de la carrera seleccionada!
  
  String _selectedEstado = 'todos';
  String _selectedOrdenReacciones = 'recientes';

  String _lugarTextoActual = '';
  Key _autocompleteKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _cargarCatalogos();
  }

  Future<void> _cargarCatalogos() async {
    final prefs = await SharedPreferences.getInstance();
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
      final respuestas = await Future.wait([
        supabase.from('cat_categorias').select('id, nombre').order('nombre'),
        supabase.from('cat_lugares').select('id, nombre, tipo, parent_id').order('nombre'),
        supabase.from('cat_carreras').select('id, nombre').order('nombre') // Cargamos las carreras
      ]);

      final catsNube = respuestas[0];
      final lugsNube = respuestas[1];
      final carrsNube = respuestas[2];

      prefs.setString('categorias_cache', jsonEncode(catsNube));
      prefs.setString('lugares_cache', jsonEncode(lugsNube));
      prefs.setString('carreras_cache', jsonEncode(carrsNube));

      _procesarYMostrarCatalogos(catsNube, lugsNube, carrsNube);
    } catch (e) {
      if (mounted && _categorias.isEmpty) setState(() => _isLoadingData = false);
    }
  }

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
        _carreras = List<Map<String, dynamic>>.from(carrsRaw); // Guardamos las carreras
        _isLoadingData = false; 
      });
    }
  }

  void _aplicar() {
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

    final filtros = {
      'usuario': _usuarioController.text.trim(),
      'titulo': _tituloController.text.trim(),
      'categoriaId': _selectedCategoriaId,
      'lugarId': _selectedLugarId,
      'carreraId': _selectedCarreraId, // ¡Enviamos el nuevo filtro de carrera!
      'estado': _selectedEstado,
      'ordenReacciones': _selectedOrdenReacciones,
    };
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ResultadosBusquedaScreen(filtros: filtros),
      ),
    );
  }

  // ¡NUEVO: Cuadro de diálogo estándar para confirmar!
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

  void _limpiar() {
    setState(() {
      _usuarioController.clear();
      _tituloController.clear();
      _selectedCategoriaId = null;
      _selectedLugarId = null;
      _selectedCarreraId = null; // Limpiamos la carrera
      _selectedEstado = 'todos';
      _selectedOrdenReacciones = 'recientes';
      _lugarTextoActual = '';
      _autocompleteKey = UniqueKey(); 
    });
  }

  @override
  Widget build(BuildContext context) {
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
        // ¡Se eliminó el botón de limpiar de la barra superior!
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

                  // ¡NUEVO: Dropdown de Carreras!
                  DropdownButtonFormField<int>(
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

                  // ¡NUEVO: Fila con botón de Búsqueda y Bote de Basura!
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
                          icon: const Icon(Icons.search), // Lupa en vez del embudo
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
                        child: const Icon(Icons.delete_outline), // Bote de basura
                      ),
                    ],
                  )
                ],
              ),
            ),
    );
  }
}