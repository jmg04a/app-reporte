import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart'; 
import '../reportes/report_detail_screen.dart'; 

/// A dedicated feed displaying only the reports authored by the active user.
///
/// Inherits the visual presentation ([TarjetaReporteOptimizada]) and 
/// pagination logic from [HomeScreen], but enforces a strict database 
/// filter against the current user's UUID.
class MisReportesScreen extends StatefulWidget {
  const MisReportesScreen({super.key});

  @override
  State<MisReportesScreen> createState() => _MisReportesScreenState();
}

class _MisReportesScreenState extends State<MisReportesScreen> {
  List<Map<String, dynamic>> _misReportes = [];
  bool _isLoading = true;
  bool _bloqueoRecarga = false;

    /// Pagination configuration parameters.
  int _rangoInicio = 0;
  final int _cantidadPorPagina = 15; 
  bool _hayMasDatos = true;
  bool _cargandoMas = false;

  final ScrollController _scrollController = ScrollController();

    /// Explicit Focus node to guarantee global hotkey interception on pushed routes.
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _cargarMisReportes();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Smoothly animates the list back to the top offset.
  /// 
  /// Bound to hardware keyboard shortcuts (ArrowUp / Home) via [CallbackShortcuts].
  
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
    if (_bloqueoRecarga) return;
    _bloqueoRecarga = true;

    setState(() => _isLoading = true);
    _rangoInicio = 0;
    _hayMasDatos = true;
    
    try {
      final supabase = Supabase.instance.client;
      final miUserId = supabase.auth.currentUser!.id;

      // Notice the specific `.eq('usuario_id', miUserId)` filter ensuring 
      // strict data isolation for the current session.
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
          // Halt pagination if the response size is smaller than the requested limit.
          if (response.length < _cantidadPorPagina) _hayMasDatos = false;
        });
      }
    } catch (e) {
      debugPrint("Error al cargar mis reportes: $e");
      if (mounted) setState(() => _isLoading = false);
    }finally {
      _bloqueoRecarga = false; // Abrimos el candado
    }
  }

  /// Fetches the subsequent payload of user reports (Pagination).
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
    // Hardware evaluation to apply correct OS-level modifier keys.
    final bool isApple = !kIsWeb && (Platform.isMacOS || Platform.isIOS);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyR, control: !isApple, meta: isApple,includeRepeats: false): _cargarMisReportes,
        SingleActivator(LogicalKeyboardKey.arrowUp, control: !isApple, meta: isApple,includeRepeats: false): _scrollToTop,
        const SingleActivator(LogicalKeyboardKey.home,includeRepeats: false): _scrollToTop,
      },
      child: Focus(
        focusNode: _focusNode,
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
          body: RefreshIndicator(
            onRefresh: _cargarMisReportes,
            color: const Color(0xFF800000),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
                : _misReportes.isEmpty
                // Render empty state as ListView to preserve pull-to-refresh physics.
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 150),
                          Icon(Icons.inbox, size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("Aún no has creado ningún reporte.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: _misReportes.length + 1, 
                        itemBuilder: (context, index) {
                          
                          // Render pagination trigger at the end of the list.
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
                              // Await the modal pop to automatically refresh the feed 
                              // in case the user edited or deleted the report inside.
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
      ),
    );
  }
}