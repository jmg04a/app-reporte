import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Rutas correctas de tus carpetas
import '../auth/login_screen.dart';
import '../reportes/create_report_screen.dart';
import '../reportes/report_detail_screen.dart'; // Ajusta la ruta si es necesario

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _reportes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarReportes(); 
  }

  // --- 1. FUNCIÓN RECUPERADA: CERRAR SESIÓN ---
  Future<void> cerrarSesion(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  // --- 2. FUNCIÓN NUEVA: DESCARGAR REPORTES ---
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
            cat_categorias (nombre, icono, color)
          ''')
          .order('id', ascending: false); 

      if (mounted) {
        setState(() {
          _reportes = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar reportes: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // --- HELPERS VISUALES ---
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
      case 'resuelto': return Colors.green;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Reportes"),
        backgroundColor: const Color(0xFF800000), 
        foregroundColor: Colors.white,
        actions: [
          // MANTENEMOS TU BOTÓN DE CERRAR SESIÓN
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => cerrarSesion(context),
            tooltip: "Cerrar Sesión",
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargarReportes,
        color: const Color(0xFF800000),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator()) 
            : _reportes.isEmpty
                ? ListView( 
                    children: const [
                      SizedBox(height: 150),
                      Icon(Icons.inbox, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("No has hecho ningún reporte aún.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _reportes.length,
                    itemBuilder: (context, index) {
                      final reporte = _reportes[index];
                      final categoria = reporte['cat_categorias'] as Map<String, dynamic>?;
                      final nombreCategoria = categoria?['nombre'] ?? 'Sin categoría';
                      final iconoCategoria = categoria?['icono'];
                      final colorCategoria = categoria?['color'];
                      final estado = reporte['estado'] ?? 'desconocido';
                      final imageUrl = reporte['evidencia_url'];

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
                                Expanded(
                                  child: Text(nombreCategoria, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
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
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReportDetailScreen(reporteId: reporte['id']),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
      ),
      // MANTENEMOS EL ACCESO A CREAR REPORTE (A través de un botón flotante más estilizado)
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateReportScreen()),
          );
          _cargarReportes(); // Refresca la lista al volver
        },
        icon: const Icon(Icons.add),
        label: const Text("Nuevo Reporte"),
      ),
    );
  }
}