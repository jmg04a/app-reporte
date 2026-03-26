import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ¡Asegúrate de que estas rutas coincidan con tus carpetas!
import '../home/home_screen.dart'; 
import 'report_detail_screen.dart';

class ResultadosBusquedaScreen extends StatefulWidget {
  final Map<String, dynamic> filtros;

  const ResultadosBusquedaScreen({super.key, required this.filtros});

  @override
  State<ResultadosBusquedaScreen> createState() => _ResultadosBusquedaScreenState();
}

class _ResultadosBusquedaScreenState extends State<ResultadosBusquedaScreen> {
  List<Map<String, dynamic>> _reportes = [];
  bool _isLoading = true;

  int _rangoInicio = 0;
  final int _cantidadPorPagina = 15; 
  bool _hayMasDatos = true;
  bool _cargandoMas = false;

  @override
  void initState() {
    super.initState();
    _cargarResultados();
  }

  // Se trajo el "Cerebro" desde el HomeScreen hacia acá
  PostgrestFilterBuilder<List<Map<String, dynamic>>> _construirConsultaSupabase() {
    final supabase = Supabase.instance.client;
    
    var query = supabase.from('reportes').select('''
      id, titulo, estado, evidencia_url, reaccion_count, categoria_id,
      cat_categorias (id, nombre, icono, color),
      perfiles!inner (nombre, estudiantes(numero_control)),
      reporte_ubicaciones!inner (lugar_id, cat_lugares(id, nombre))
    ''');

    final titulo = widget.filtros['titulo']?.toString().trim() ?? '';
    if (titulo.isNotEmpty) query = query.ilike('titulo', '%$titulo%');

    final categoriaId = widget.filtros['categoriaId'];
    if (categoriaId != null) query = query.eq('categoria_id', categoriaId);

    final estadoFiltro = widget.filtros['estado'] ?? 'todos';
    if (estadoFiltro != 'todos') query = query.eq('estado', estadoFiltro);

    final lugarId = widget.filtros['lugarId'];
    if (lugarId != null) query = query.eq('reporte_ubicaciones.lugar_id', lugarId);

    final usuario = widget.filtros['usuario']?.toString().trim() ?? '';
    if (usuario.isNotEmpty) query = query.ilike('perfiles.nombre', '%$usuario%');

    return query;
  }

  Future<void> _cargarResultados() async {
    setState(() => _isLoading = true);
    _rangoInicio = 0;
    _hayMasDatos = true;

    try {
      var queryBase = _construirConsultaSupabase();
      PostgrestTransformBuilder<List<Map<String, dynamic>>> queryOrdenada;
      
      final orden = widget.filtros['ordenReacciones'] ?? 'recientes';
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
          _reportes = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          if (response.length < _cantidadPorPagina) _hayMasDatos = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarMasResultados() async {
    if (_cargandoMas || !_hayMasDatos) return;

    setState(() => _cargandoMas = true);
    _rangoInicio += _cantidadPorPagina;

    try {
      var queryBase = _construirConsultaSupabase();
      PostgrestTransformBuilder<List<Map<String, dynamic>>> queryOrdenada;
      
      final orden = widget.filtros['ordenReacciones'] ?? 'recientes';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Resultados de Búsqueda"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
          : _reportes.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text("No se encontraron reportes con estos filtros.", style: TextStyle(color: Colors.grey, fontSize: 16)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _reportes.length + 1, 
                  itemBuilder: (context, index) {
                    
                    // BOTÓN DE CARGAR MÁS
                    if (index == _reportes.length) {
                      if (!_hayMasDatos) return const SizedBox.shrink();
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: _cargandoMas
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
                          : Center(
                              child: OutlinedButton.icon(
                                onPressed: _cargarMasResultados,
                                icon: const Icon(Icons.add_circle_outline, color: Color(0xFF800000)),
                                label: const Text("Cargar más resultados", style: TextStyle(color: Color(0xFF800000))),
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF800000))),
                              ),
                            ),
                      );
                    }

                    // TARJETAS RECICLADAS
                    return TarjetaReporteOptimizada(
                      reporte: _reportes[index],
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => ReportDetailScreen(reporteId: _reportes[index]['id'])),
                        );
                        _cargarResultados(); 
                      },
                    );
                  },
                ),
    );
  }
}