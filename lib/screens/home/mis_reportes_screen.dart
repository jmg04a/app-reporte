import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart'; 
import '../reportes/report_detail_screen.dart'; 

class MisReportesScreen extends StatefulWidget {
  const MisReportesScreen({super.key});

  @override
  State<MisReportesScreen> createState() => _MisReportesScreenState();
}

class _MisReportesScreenState extends State<MisReportesScreen> {
  List<Map<String, dynamic>> _misReportes = [];
  bool _isLoading = true;

  // 1. EL CONTROLADOR DE LA LISTA
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargarMisReportes();
  }

  // ¡IMPORTANTE! Liberar memoria
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // FUNCIÓN PARA ANIMAR HACIA ARRIBA
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, 
        duration: const Duration(milliseconds: 600), 
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _cargarMisReportes() async {
    setState(() => _isLoading = true);
    
    try {
      final supabase = Supabase.instance.client;
      final miUserId = supabase.auth.currentUser!.id;

      final response = await supabase.from('reportes').select('''
        id, titulo, estado, evidencia_url, reaccion_count, categoria_id,
        cat_categorias (id, nombre, icono, color),
        perfiles!inner (nombre, estudiantes(numero_control)),
        reporte_ubicaciones!inner (lugar_id, cat_lugares(id, nombre))
      ''')
      .eq('usuario_id', miUserId) 
      .eq('visible', true) 
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
    final bool isMac = !kIsWeb && Platform.isMacOS;

    // ENVOLVEMOS LA PANTALLA EN ATAJOS LOCALES
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.arrowUp, control: !isMac, meta: isMac): _scrollToTop,
        const SingleActivator(LogicalKeyboardKey.home): _scrollToTop,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            // TÍTULO TÁCTIL PARA REGRESAR ARRIBA
            title: GestureDetector(
              onTap: _scrollToTop,
              child: const Text("Mis Reportes"),
            ),
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
                      controller: _scrollController, // <--- CONECTAMOS EL CONTROLADOR
                      padding: const EdgeInsets.all(12),
                      itemCount: _misReportes.length,
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
        ),
      ),
    );
  }
}