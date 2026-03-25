import 'dart:convert'; 
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; 
import '../reportes/report_detail_screen.dart'; 
import '../reportes/filter_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState(); 
}

class HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _reportes = [];
  bool _isLoading = true;

  Map<String, dynamic> _filtrosActivos = {};

  final ScrollController _scrollController = ScrollController();
  int _rangoInicio = 0;
  final int _cantidadPorPagina = 15; 
  bool _hayMasDatos = true;
  bool _cargandoMas = false;

  @override
  void initState() {
    super.initState();
    cargarReportes(); 
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        _cargarMasReportes(); 
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // =========================================================
  // EL CEREBRO DE BÚSQUEDA (CONSTRUCTOR DE CONSULTAS SUPABASE)
  // =========================================================
  PostgrestFilterBuilder<List<Map<String, dynamic>>> _construirConsultaSupabase() {
    final supabase = Supabase.instance.client;
    
    // 1. Iniciamos la consulta base asegurando las relaciones (!inner) para poder filtrar
    var query = supabase.from('reportes').select('''
      id,
      titulo,
      estado,
      evidencia_url,
      reaccion_count,
      categoria_id,
      cat_categorias (id, nombre, icono, color),
      perfiles!inner (nombre, estudiantes(numero_control)),
      reporte_ubicaciones!inner (lugar_id, cat_lugares(id, nombre))
    ''');

    // 2. Filtro de Título (Búsqueda Parcial)
    final titulo = _filtrosActivos['titulo']?.toString().trim() ?? '';
    if (titulo.isNotEmpty) {
      query = query.ilike('titulo', '%$titulo%');
    }

    // 3. Filtro de Categoría
    final categoriaId = _filtrosActivos['categoriaId'];
    if (categoriaId != null) {
      query = query.eq('categoria_id', categoriaId);
    }

    // 4. Filtro de Estado
    final estadoFiltro = _filtrosActivos['estado'] ?? 'todos';
    if (estadoFiltro != 'todos') {
      query = query.eq('estado', estadoFiltro);
    }

    // 5. Filtro de Ubicación
    final lugarId = _filtrosActivos['lugarId'];
    if (lugarId != null) {
      query = query.eq('reporte_ubicaciones.lugar_id', lugarId);
    }

    // 6. Filtro de Usuario (Por Nombre)
    final usuario = _filtrosActivos['usuario']?.toString().trim() ?? '';
    if (usuario.isNotEmpty) {
      query = query.ilike('perfiles.nombre', '%$usuario%');
    }

    return query;
  }

  // =========================================================

  Future<void> cargarReportes() async {
    _rangoInicio = 0;
    _hayMasDatos = true;

    // Solo usamos la caché local si NO hay filtros activos (para no mezclar datos)
    if (_filtrosActivos.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final datosGuardados = prefs.getString('reportes_cache');

      if (datosGuardados != null && _reportes.isEmpty) {
        if (mounted) {
          setState(() {
            _reportes = List<Map<String, dynamic>>.from(jsonDecode(datosGuardados));
            _isLoading = false; 
          });
        }
      } else {
        setState(() => _isLoading = true);
      }
    } else {
      setState(() => _isLoading = true);
    }

    try {
      // Obtenemos la consulta pre-armada con filtros
      var queryBase = _construirConsultaSupabase();
      
      PostgrestTransformBuilder<List<Map<String, dynamic>>> queryOrdenada;
      
      // Aplicamos el ORDENAMIENTO desde el servidor
      final orden = _filtrosActivos['ordenReacciones'] ?? 'recientes';
      if (orden == 'desc') {
        queryOrdenada = queryBase.order('reaccion_count', ascending: false).order('id', ascending: false);
      } else if (orden == 'asc') {
        queryOrdenada = queryBase.order('reaccion_count', ascending: true).order('id', ascending: false);
      } else {
        queryOrdenada = queryBase.order('id', ascending: false); // Por defecto (Recientes)
      }

      // Descargamos los primeros 15
      final response = await queryOrdenada.range(_rangoInicio, _rangoInicio + _cantidadPorPagina - 1);

      if (mounted) {
        setState(() {
          _reportes = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          
          if (response.length < _cantidadPorPagina) _hayMasDatos = false;
        });
        
        // Solo guardamos en caché si es la vista general sin filtros
        if (_filtrosActivos.isEmpty) {
          final prefs = await SharedPreferences.getInstance();
          prefs.setString('reportes_cache', jsonEncode(response));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error cargando datos: $e');
    }
  }

  Future<void> _cargarMasReportes() async {
    if (_cargandoMas || !_hayMasDatos) return;

    setState(() => _cargandoMas = true);
    _rangoInicio += _cantidadPorPagina;

    try {
      var queryBase = _construirConsultaSupabase();
      
      PostgrestTransformBuilder<List<Map<String, dynamic>>> queryOrdenada;
      
      final orden = _filtrosActivos['ordenReacciones'] ?? 'recientes';
      if (orden == 'desc') {
        queryOrdenada = queryBase.order('reaccion_count', ascending: false).order('id', ascending: false);
      } else if (orden == 'asc') {
        queryOrdenada = queryBase.order('reaccion_count', ascending: true).order('id', ascending: false);
      } else {
        queryOrdenada = queryBase.order('id', ascending: false);
      }

      final response = await queryOrdenada.range(_rangoInicio, _rangoInicio + _cantidadPorPagina - 1);

      if (mounted) {
        setState(() {
          if (response.isEmpty) {
            _hayMasDatos = false; 
          } else {
            _reportes.addAll(List<Map<String, dynamic>>.from(response));
            if (response.length < _cantidadPorPagina) _hayMasDatos = false;
          }
          _cargandoMas = false; 
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  Future<void> abrirPantallaFiltros() async {
    final filtrosElegidos = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => FilterScreen(filtrosActuales: _filtrosActivos),
      ),
    );

    if (filtrosElegidos != null) {
      _filtrosActivos = filtrosElegidos;
      // Cuando el usuario elige filtros, simplemente recargamos desde cero
      // ¡El servidor hará todo el trabajo pesado!
      cargarReportes();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool tieneFiltrosActivos = _filtrosActivos.isNotEmpty && (
      _filtrosActivos['titulo']?.toString().isNotEmpty == true ||
      _filtrosActivos['usuario']?.toString().isNotEmpty == true ||
      _filtrosActivos['categoriaId'] != null ||
      _filtrosActivos['lugarId'] != null ||
      (_filtrosActivos['estado'] != null && _filtrosActivos['estado'] != 'todos') ||
      (_filtrosActivos['ordenReacciones'] != null && _filtrosActivos['ordenReacciones'] != 'recientes')
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Reportes", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF800000), 
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: cargarReportes,
        color: const Color(0xFF800000),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator()) 
            : _reportes.isEmpty
                ? ListView( 
                    children: [
                      const SizedBox(height: 150),
                      const Icon(Icons.search_off, size: 80, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        tieneFiltrosActivos ? "No se encontraron reportes con estos filtros." : "No hay ningún reporte aún.", 
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 16)
                      ),
                      if (tieneFiltrosActivos)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: TextButton.icon(
                            onPressed: () {
                              setState(() => _filtrosActivos = {});
                              cargarReportes(); // Limpiamos y recargamos
                            },
                            icon: const Icon(Icons.clear_all, color: Color(0xFF800000)),
                            label: const Text("Limpiar Filtros", style: TextStyle(color: Color(0xFF800000))),
                          ),
                        )
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    controller: _scrollController,
                    itemCount: _reportes.length + (_cargandoMas ? 1 : 0),
                    itemExtent: 110.0, 
                    addAutomaticKeepAlives: false,
                    itemBuilder: (context, index) {
                      
                      if (index == _reportes.length) {
                        return const Center(
                          child: CircularProgressIndicator(color: Color(0xFF800000))
                        );
                      }

                      return TarjetaReporteOptimizada(
                        reporte: _reportes[index],
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ReportDetailScreen(reporteId: _reportes[index]['id'])),
                          );
                          cargarReportes(); 
                        },
                      );
                    },
                  ),
      ),
    );
  }
}

// =====================================================================
// TARJETA EXTRAÍDA E INDEPENDIENTE
// =====================================================================
class TarjetaReporteOptimizada extends StatelessWidget {
  final Map<String, dynamic> reporte;
  final VoidCallback onTap;

  const TarjetaReporteOptimizada({
    super.key,
    required this.reporte,
    required this.onTap,
  });

  static final Map<String, Color> _colorCache = {};

  static Color _getColorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return Colors.grey;
    if (_colorCache.containsKey(hexColor)) return _colorCache[hexColor]!;
    
    final hexCode = hexColor.replaceAll('#', '');
    final color = Color(int.parse('FF$hexCode', radix: 16));
    _colorCache[hexColor] = color;
    return color;
  }

  static IconData _getIconFromName(String? iconName) {
    switch (iconName) {
      case 'build': return Icons.build;
      case 'chair': return Icons.chair_alt;
      case 'computer': return Icons.computer;
      case 'cleaning_services': return Icons.cleaning_services;
      case 'security': return Icons.security;
      default: return Icons.category;
    }
  }

  static Color _getColorEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'pendiente': return Colors.orange;
      case 'en proceso': return Colors.blue;
      case 'finalizado': return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoria = reporte['cat_categorias'] as Map<String, dynamic>?;
    final nombreCategoria = categoria?['nombre'] ?? 'Sin categoría';
    final iconoCategoria = categoria?['icono'];
    final colorCategoria = categoria?['color'];
    final estado = reporte['estado'] ?? 'desconocido';
    final imageUrl = reporte['evidencia_url'];
    final reacciones = reporte['reaccion_count'] ?? 0; 
    
    final colorBase = _getColorFromHex(colorCategoria);
    final colorEst = _getColorEstado(estado);

    return Card(
      elevation: 0, 
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300, width: 1), 
      ),
      child: InkWell( 
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: colorBase.withValues(alpha: 0.2),
                child: Icon(_getIconFromName(iconoCategoria), color: colorBase),
              ),
              const SizedBox(width: 12), 
              
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reporte['titulo'] ?? 'Sin título',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8), 
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorEst.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: colorEst),
                          ),
                          child: Text(
                            estado.toUpperCase(),
                            style: TextStyle(color: colorEst, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8), 
                        Expanded(
                          child: Text(
                            nombreCategoria, 
                            style: const TextStyle(fontSize: 12), 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis
                          )
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 8), 
              if (reacciones > 0) 
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Text(
                          reacciones.toString(),
                          style: const TextStyle(
                            fontSize: 15, 
                            fontWeight: FontWeight.bold, 
                            color: Color(0xFF800000)
                          ),
                        ),
                        const SizedBox(width: 4), 
                        const Icon(Icons.group, size: 16, color: Color(0xFF800000)), 
                      ],
                    ),
                    const Text(
                      "Tengo el mismo\nproblema", 
                      style: TextStyle(fontSize: 9, color: Colors.grey, height: 1.1),
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
              const SizedBox(width: 12), 
              
              imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      memCacheWidth: 150, 
                      // ==========================================
                      // ¡NUEVO! Matamos las animaciones pesadas
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      // ==========================================
                      imageBuilder: (context, imageProvider) => Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: DecorationImage(
                            image: imageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      placeholder: (context, url) => Container(
                        width: 50, height: 50, 
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.image, color: Colors.grey, size: 20),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    )
                  : Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.image_not_supported, color: Colors.grey),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}