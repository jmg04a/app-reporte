import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Importante para cerrar la aplicación
import 'package:supabase_flutter/supabase_flutter.dart';
import '../reportes/create_report_screen.dart';
import '../reportes/report_detail_screen.dart'; 
import '../reportes/filter_screen.dart';
import 'profile_screen.dart'; // Asegúrate de importar la pantalla que acabamos de crear
import 'package:flutter/foundation.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _todosLosReportes = [];
  List<Map<String, dynamic>> _reportesFiltrados = [];
  bool _isLoading = true;

  Map<String, dynamic> _filtrosActivos = {};
  
  // --- VARIABLES PARA EL USUARIO ---
  String _nombreUsuario = 'Cargando...';
  String _rolUsuario = '';
  String? _avatarUrl; // Agregamos la variable de la foto

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario(); 
    _cargarReportes(); 
  }

  Future<void> _cargarDatosUsuario() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;
      
      if (userId != null) {
        // Ahora también le pedimos el 'avatar_url' a la base de datos
        final userData = await supabase
            .from('perfiles')
            .select('nombre, rol, avatar_url')
            .eq('id', userId)
            .maybeSingle();
        
        if (userData != null && mounted) {
          setState(() {
            _nombreUsuario = userData['nombre'] ?? 'Usuario Desconocido';
            _rolUsuario = userData['rol'] ?? 'usuario';
            _avatarUrl = userData['avatar_url'];
          });
        }
      }
    } catch (e) {
      debugPrint("Error al cargar datos del usuario: $e");
    }
  }

  // --- NUEVA FUNCIÓN: SALIR DE LA APLICACIÓN ---
Future<void> _salirDeLaApp() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Salir de la App"),
        content: const Text("¿Estás seguro de que deseas cerrar la aplicación?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF800000), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sí, salir"),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      SystemNavigator.pop(); // Cierra la app en Android
    }
  }

  Future<void> _cargarReportes() async {
    setState(() => _isLoading = true);
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        setState(() => _isLoading = false);
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

  Future<void> _abrirPantallaFiltros() async {
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
        // --- AQUÍ CONVERTIMOS LA BARRA DE TÍTULO EN UN BOTÓN INTERACTIVO ---
        title: GestureDetector(
          onTap: () {
            // Al tocar el perfil, abrimos la nueva pantalla
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(
                  nombre: _nombreUsuario,
                  rol: _rolUsuario,
                  avatarUrl: _avatarUrl,
                ),
              ),
            );
          },
          child: Row(
            children: [
              // Avatar pequeño
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white24,
                backgroundImage: _avatarUrl != null ? NetworkImage(_avatarUrl!) : null,
                child: _avatarUrl == null ? const Icon(Icons.person, color: Colors.white, size: 20) : null,
              ),
              const SizedBox(width: 10),
              // Nombre y Rol
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Panel de Reportes", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                      "$_nombreUsuario ${_rolUsuario == 'admin' ? '(Admin)' : ''}",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
                      overflow: TextOverflow.ellipsis, // Si el nombre es muy largo, lo corta con "..."
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        backgroundColor: const Color(0xFF800000), 
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            // Cambiamos Icons.filter_alt por Icons.search
            icon: Icon(Icons.search, color: tieneFiltrosActivos ? Colors.yellow : Colors.white), 
            onPressed: _abrirPantallaFiltros,
            tooltip: "Busqueda y filtros", // Opcional: también puedes actualizar el texto emergente
          ),
          // --- ESTE BOTÓN AHORA CIERRA LA APLICACIÓN ---
          // --- CONDICIÓN DEFINITIVA: SOLO MOSTRAR EN ANDROID / WINDOWS ---
          // ESTO CREA EL BOTÓN ÚNICA Y EXCLUSIVAMENTE EN ANDROID NATIVO
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              onPressed: _salirDeLaApp,
              tooltip: "Salir de la Aplicación",
            )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarReportes,
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
                        tieneFiltrosActivos ? "No se encontraron reportes con estos filtros." : "No has hecho ningún reporte aún.", 
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
                                if (reacciones > 0)
                                  Row(
                                    children: [
                                      const Icon(Icons.favorite, color: Colors.red, size: 14),
                                      const SizedBox(width: 4),
                                      Text(reacciones.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                                    ],
                                  )
                              ],
                            ),
                          ),
                          trailing: imageUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    imageUrl,
                                    width: 50,
                                    height: 50,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                )
                              : const SizedBox(width: 50, height: 50, child: Icon(Icons.image_not_supported, color: Colors.grey)),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ReportDetailScreen(reporteId: reporte['id'])),
                            );
                            _cargarReportes(); 
                          },
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateReportScreen()),
          );
          _cargarReportes();
        },
        icon: const Icon(Icons.add),
        label: const Text("Nuevo Reporte"),
      ),
    );
  }
}