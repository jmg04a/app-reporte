import 'dart:convert'; // Para la memoria caché
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Para guardar datos localmente
import 'package:cached_network_image/cached_network_image.dart'; // Para la caché de imágenes
import '../reportes/report_detail_screen.dart'; 
import '../reportes/filter_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState(); 
}

class HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _todosLosReportes = [];
  List<Map<String, dynamic>> _reportesFiltrados = [];
  bool _isLoading = true;

  Map<String, dynamic> _filtrosActivos = {};

  @override
  void initState() {
    super.initState();
    cargarReportes(); 
  }

  // --- FUNCIÓN CON CACHÉ INTELIGENTE ---
  Future<void> cargarReportes() async {
    // 1. INTENTAR LEER LA CACHÉ LOCAL PRIMERO
    final prefs = await SharedPreferences.getInstance();
    final datosGuardados = prefs.getString('reportes_cache');

    if (datosGuardados != null && _todosLosReportes.isEmpty) {
      if (mounted) {
        setState(() {
          List<dynamic> jsonList = jsonDecode(datosGuardados);
          _todosLosReportes = List<Map<String, dynamic>>.from(jsonList);
          _aplicarFiltros();
          _isLoading = false; 
        });
      }
    } else {
      setState(() => _isLoading = true);
    }

    // 2. BUSCAR DATOS FRESCOS EN SUPABASE
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('reportes')
          .select('''
            id,
            titulo,
            estado,
            evidencia_url,
            reaccion_count,
            cat_categorias (id, nombre, icono, color),
            perfiles (nombre, estudiantes(numero_control)),
            reporte_ubicaciones (cat_lugares(id, nombre))
          ''')
          .order('id', ascending: false); 

      if (mounted) {
        setState(() {
          _todosLosReportes = List<Map<String, dynamic>>.from(response);
          _aplicarFiltros(); 
          _isLoading = false;
        });
        
        // Guardar la nueva respuesta en el celular
        prefs.setString('reportes_cache', jsonEncode(response));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Opcional: Mostrar un mensaje pequeño si está offline, pero ya cargó caché
        debugPrint('Viendo datos sin conexión: $e');
      }
    }
  }

  void _aplicarFiltros() {
    setState(() {
      _reportesFiltrados = _todosLosReportes.where((reporte) {
        final tituloFiltro = _filtrosActivos['titulo']?.toString().toLowerCase() ?? '';
        if (tituloFiltro.isNotEmpty) {
          final tituloReporte = reporte['titulo']?.toString().toLowerCase() ?? '';
          if (!tituloReporte.contains(tituloFiltro)) return false;
        }

        final usuarioFiltro = _filtrosActivos['usuario']?.toString().toLowerCase() ?? '';
        if (usuarioFiltro.isNotEmpty) {
          final perfil = reporte['perfiles'];
          final nombre = perfil?['nombre']?.toString().toLowerCase() ?? '';
          
          String numControl = '';
          final est = perfil?['estudiantes'];
          if (est is List && est.isNotEmpty) {
            numControl = est[0]['numero_control']?.toString().toLowerCase() ?? '';
          } else if (est is Map) {
            numControl = est['numero_control']?.toString().toLowerCase() ?? '';
          }

          if (!nombre.contains(usuarioFiltro) && !numControl.contains(usuarioFiltro)) return false;
        }

        final categoriaId = _filtrosActivos['categoriaId'];
        if (categoriaId != null) {
          if (reporte['cat_categorias']?['id'] != categoriaId) return false;
        }

        final lugarId = _filtrosActivos['lugarId'];
        if (lugarId != null) {
          final ubicaciones = reporte['reporte_ubicaciones'];
          int? idLugarReporte;
          if (ubicaciones is List && ubicaciones.isNotEmpty) {
            idLugarReporte = ubicaciones[0]['cat_lugares']?['id'];
          } else if (ubicaciones is Map) {
            idLugarReporte = ubicaciones['cat_lugares']?['id'];
          }
          if (idLugarReporte != lugarId) return false;
        }

        final estadoFiltro = _filtrosActivos['estado'] ?? 'todos';
        if (estadoFiltro != 'todos') {
          if (reporte['estado'] != estadoFiltro) return false;
        }

        return true;
      }).toList();

      final orden = _filtrosActivos['ordenReacciones'] ?? 'recientes';
      if (orden == 'desc') {
        _reportesFiltrados.sort((a, b) => (b['reaccion_count'] ?? 0).compareTo(a['reaccion_count'] ?? 0));
      } else if (orden == 'asc') {
        _reportesFiltrados.sort((a, b) => (a['reaccion_count'] ?? 0).compareTo(b['reaccion_count'] ?? 0));
      } else {
        _reportesFiltrados.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));
      }
    });
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
      _aplicarFiltros();
    }
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

  Color _getColorEstado(String estado) {
    switch (estado.toLowerCase()) {
      case 'pendiente': return Colors.orange;
      case 'en proceso': return Colors.blue;
      case 'finalizado': return Colors.green;
      default: return Colors.grey;
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
            : _reportesFiltrados.isEmpty
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
                              _aplicarFiltros();
                            },
                            icon: const Icon(Icons.clear_all, color: Color(0xFF800000)),
                            label: const Text("Limpiar Filtros", style: TextStyle(color: Color(0xFF800000))),
                          ),
                        )
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _reportesFiltrados.length,
                    itemBuilder: (context, index) {
                      final reporte = _reportesFiltrados[index];
                      final categoria = reporte['cat_categorias'] as Map<String, dynamic>?;
                      final nombreCategoria = categoria?['nombre'] ?? 'Sin categoría';
                      final iconoCategoria = categoria?['icono'];
                      final colorCategoria = categoria?['color'];
                      final estado = reporte['estado'] ?? 'desconocido';
                      final imageUrl = reporte['evidencia_url'];
                      final reacciones = reporte['reaccion_count'] ?? 0; 

                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: CircleAvatar(
                            backgroundColor: _getColorFromHex(colorCategoria).withValues(alpha: 0.2),
                            child: Icon(_getIconFromName(iconoCategoria), color: _getColorFromHex(colorCategoria)),
                          ),
                          title: Text(
                            reporte['titulo'] ?? 'Sin título',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getColorEstado(estado).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: _getColorEstado(estado)),
                                  ),
                                  child: Text(
                                    estado.toUpperCase(),
                                    style: TextStyle(color: _getColorEstado(estado), fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Text(nombreCategoria, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          ),
                          
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min, 
                            children: [
                              if (reacciones > 0) 
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisSize: MainAxisSize.min,
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
                              
                              // --- IMPLEMENTACIÓN DE CACHED NETWORK IMAGE ---
                              imageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        placeholder: (context, url) => const SizedBox(
                                          width: 50, height: 50, 
                                          child: Center(child: CircularProgressIndicator(strokeWidth: 2))
                                        ),
                                        errorWidget: (context, url, error) => const Icon(Icons.broken_image, color: Colors.grey),
                                      ),
                                    )
                                  : const SizedBox(width: 50, height: 50, child: Icon(Icons.image_not_supported, color: Colors.grey)),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ReportDetailScreen(reporteId: reporte['id'])),
                            );
                            cargarReportes(); 
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}