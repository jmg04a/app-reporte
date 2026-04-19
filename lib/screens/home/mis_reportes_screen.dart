import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart'; 
import '../reportes/report_detail_screen.dart'; 

/// Pantalla dedicada a mostrar únicamente los reportes creados por el usuario activo.
///
/// Hereda la presentación visual ([TarjetaReporteOptimizada]) y la lógica de 
/// paginación de [HomeScreen], pero impone un filtro estricto en la base de datos 
/// para aislar y mostrar solo los registros que coinciden con el UUID del usuario actual.
class MisReportesScreen extends StatefulWidget {
  const MisReportesScreen({super.key});

  @override
  State<MisReportesScreen> createState() => _MisReportesScreenState();
}

class _MisReportesScreenState extends State<MisReportesScreen> {
  List<Map<String, dynamic>> _misReportes = [];
  bool _isLoading = true;
  bool _bloqueoRecarga = false;

  /// Parámetros de configuración para la paginación de la lista.
  int _rangoInicio = 0;
  final int _cantidadPorPagina = 15; 
  bool _hayMasDatos = true;
  bool _cargandoMas = false;

  final ScrollController _scrollController = ScrollController();

  /// Nodo de enfoque explícito.
  /// 
  /// Garantiza la intercepción de atajos de teclado globales (como actualizar 
  /// o subir) cuando esta ruta es empujada sobre la pila de navegación.
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

  /// Desplaza suavemente la lista de vuelta a la parte superior.
  /// 
  /// Se encuentra vinculada a los atajos de teclado de hardware (Flecha Arriba / Inicio) 
  /// mediante el widget [CallbackShortcuts].
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, 
        duration: const Duration(milliseconds: 600), 
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Descarga el primer bloque de reportes pertenecientes al usuario.
  ///
  /// Realiza una consulta a Supabase aplicando un filtro explícito (`.eq`)
  /// sobre la columna `usuario_id` para garantizar el aislamiento de datos.
  Future<void> _cargarMisReportes() async {
    if (_bloqueoRecarga) return;
    _bloqueoRecarga = true;

    setState(() => _isLoading = true);
    _rangoInicio = 0;
    _hayMasDatos = true;
    
    try {
      final supabase = Supabase.instance.client;
      final miUserId = supabase.auth.currentUser!.id;

      // Filtro estricto `.eq('usuario_id', miUserId)` para asegurar 
      // el aislamiento de datos para la sesión actual.
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
          // Detiene la paginación si el tamaño de la respuesta es menor al límite solicitado.
          if (response.length < _cantidadPorPagina) _hayMasDatos = false;
        });
      }
    } catch (e) {
      debugPrint("Error al cargar mis reportes: $e");
      if (mounted) setState(() => _isLoading = false);
    } finally {
      _bloqueoRecarga = false; // Liberamos el candado de recarga
    }
  }

  /// Descarga el siguiente bloque de reportes del usuario (Paginación).
  ///
  /// Se ejecuta al presionar el botón de "Cargar más" al final de la lista,
  /// anexando los nuevos resultados a la colección existente.
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
    // Evaluación de hardware para aplicar las teclas modificadoras correctas a nivel de SO.
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
                // Renderiza un estado vacío usando ListView para preservar las físicas del "Pull-to-refresh".
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
                          
                          // Renderiza el disparador de paginación al final de la lista.
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
                              // Espera a que se cierre el modal de detalles para refrescar 
                              // automáticamente la vista en caso de que el usuario haya editado o eliminado el reporte.
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