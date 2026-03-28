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

  // Lógica de Paginación
  int _rangoInicio = 0;
  final int _cantidadPorPagina = 15; 
  bool _hayMasDatos = true;
  bool _cargandoMas = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargarMisReportes();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
    _rangoInicio = 0;
    _hayMasDatos = true;
    
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
      .order('id', ascending: false)
      .range(_rangoInicio, _rangoInicio + _cantidadPorPagina - 1); 

      if (mounted) {
        setState(() {
          _misReportes = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          if (response.length < _cantidadPorPagina) _hayMasDatos = false;
        });
      }
    } catch (e) {
      debugPrint("Error al cargar mis reportes: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarMasReportes() async {
    if (_cargandoMas || !_hayMasDatos) return;

    setState(() => _cargandoMas = true);
    _rangoInicio += _cantidadPorPagina;

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
      .order('id', ascending: false)
      .range(_rangoInicio, _rangoInicio + _cantidadPorPagina - 1);

      if (mounted) {
        setState(() {
          if (response.isEmpty) {
            _hayMasDatos = false; 
          } else {
            _misReportes.addAll(List<Map<String, dynamic>>.from(response));
            if (response.length < _cantidadPorPagina) _hayMasDatos = false;
          }
          _cargandoMas = false; 
        });
      }
    } catch (e) {
      if (mounted) setState(() => _cargandoMas = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMac = !kIsWeb && Platform.isMacOS;

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.arrowUp, control: !isMac, meta: isMac): _scrollToTop,
        const SingleActivator(LogicalKeyboardKey.home): _scrollToTop,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
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
                      controller: _scrollController, 
                      cacheExtent: 2500, // <--- ¡SIN PARPADEOS!
                      padding: const EdgeInsets.all(12),
                      itemCount: _misReportes.length + 1, // +1 para el botón
                      itemBuilder: (context, index) {
                        
                        if (index == _misReportes.length) {
                          if (!_hayMasDatos) return const SizedBox.shrink();
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: _cargandoMas
                              ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
                              : Center(
                                  child: OutlinedButton.icon(
                                    onPressed: _cargarMasReportes,
                                    icon: const Icon(Icons.add, color: Color(0xFF800000)),
                                    label: const Text("Cargar más", style: TextStyle(color: Color(0xFF800000))),
                                    style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF800000))),
                                  ),
                                ),
                          );
                        }

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