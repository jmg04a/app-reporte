import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart'; // Importamos el home para reutilizar la tarjeta
import '../reportes/report_detail_screen.dart'; // Ajusta esta ruta según tus carpetas

class MisReportesScreen extends StatefulWidget {
  const MisReportesScreen({super.key});

  @override
  State<MisReportesScreen> createState() => _MisReportesScreenState();
}

class _MisReportesScreenState extends State<MisReportesScreen> {
  List<Map<String, dynamic>> _misReportes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarMisReportes();
  }

  Future<void> _cargarMisReportes() async {
    setState(() => _isLoading = true);
    
    try {
      final supabase = Supabase.instance.client;
      final miUserId = supabase.auth.currentUser!.id;

      // Buscamos SOLO los reportes de este usuario
      final response = await supabase.from('reportes').select('''
        id, titulo, estado, evidencia_url, reaccion_count, categoria_id,
        cat_categorias (id, nombre, icono, color),
        perfiles!inner (nombre, estudiantes(numero_control)),
        reporte_ubicaciones!inner (lugar_id, cat_lugares(id, nombre))
      ''')
      .eq('usuario_id', miUserId) 
      .eq('visible', true) // <--- ¡AGREGA ESTA LÍNEA AQUÍ!
      .order('id', ascending: false); 

      if (mounted) {
        setState(() {
          _misReportes = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error al cargar mis reportes: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mis Reportes"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
          : _misReportes.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("Aún no has creado ningún reporte.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _misReportes.length,
                  // RECICLAMOS tu tarjeta optimizada del HomeScreen
                  itemBuilder: (context, index) {
                    final reporte = _misReportes[index];
                    return TarjetaReporteOptimizada(
                      reporte: reporte,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReportDetailScreen(reporteId: reporte['id'])
                          ),
                        );
                        _cargarMisReportes(); 
                      },
                    );
                  },
                ),
    );
  }
}