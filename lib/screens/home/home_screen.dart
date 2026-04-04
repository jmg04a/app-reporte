import 'dart:io';
import 'dart:convert'; 
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart'; 
import 'package:cached_network_image/cached_network_image.dart'; 
import 'package:flutter_cache_manager/flutter_cache_manager.dart'; 
import '../reportes/report_detail_screen.dart'; 

class GestorCacheReportes {
  static const key = 'reportesCacheKey';
  
  static CacheManager instance = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7), 
      maxNrOfCacheObjects: 50, 
      repo: JsonCacheInfoRepository(databaseName: key),
      fileService: HttpFileService(),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  // AGREGAMOS EL OBSERVER AQUÍ
  State<HomeScreen> createState() => HomeScreenState(); 
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _reportes = [];
  bool _isLoading = true;
  bool _bloqueoRecarga = false;
  
  int _rangoInicio = 0;
  final int _cantidadPorPagina = 15; 
  bool _hayMasDatos = true;
  bool _cargandoMas = false;

  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  // Agrega esto en HomeScreenState y ProfileScreenState
  void pedirFoco() {
    if (mounted && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Conectamos el observador
    cargarReportes(); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Desconectamos el observador
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ESTA FUNCIÓN RECUPERA EL TECLADO CUANDO REGRESAS A LA APP
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_focusNode.hasFocus) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    }
  }

  void scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, 
        duration: const Duration(milliseconds: 600), 
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> cargarReportes() async {
    if (_bloqueoRecarga) return; 
    _bloqueoRecarga = true;      

    _rangoInicio = 0;
    _hayMasDatos = true;

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

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.from('reportes').select('''
        id, titulo, estado, evidencia_url, reaccion_count, categoria_id,
        cat_categorias (id, nombre, icono, color),
        perfiles!inner (nombre, estudiantes(numero_control)),
        reporte_ubicaciones!inner (lugar_id, cat_lugares(id, nombre))
      ''').eq('visible', true) 
          .order('id', ascending: false)
          .range(_rangoInicio, _rangoInicio + _cantidadPorPagina - 1);

      if (mounted) {
        setState(() {
          _reportes = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
          if (response.length < _cantidadPorPagina) _hayMasDatos = false;
        });
        prefs.setString('reportes_cache', jsonEncode(response));
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    } finally {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) _bloqueoRecarga = false; 
    }
  }

  Future<void> _cargarMasReportes() async {
    if (_cargandoMas || !_hayMasDatos) return;

    setState(() => _cargandoMas = true);
    _rangoInicio += _cantidadPorPagina;

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.from('reportes').select('''
        id, titulo, estado, evidencia_url, reaccion_count, categoria_id,
        cat_categorias (id, nombre, icono, color),
        perfiles!inner (nombre, estudiantes(numero_control)),
        reporte_ubicaciones!inner (lugar_id, cat_lugares(id, nombre))
      ''').eq('visible', true) 
          .order('id', ascending: false)
          .range(_rangoInicio, _rangoInicio + _cantidadPorPagina - 1);

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
    final bool isApple = !kIsWeb && (Platform.isMacOS || Platform.isIOS);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyR, control: !isApple, meta: isApple, includeRepeats: false): cargarReportes,
        SingleActivator(LogicalKeyboardKey.arrowUp, control: !isApple, meta: isApple, includeRepeats: false): scrollToTop,
        const SingleActivator(LogicalKeyboardKey.home, includeRepeats: false): scrollToTop,
      },
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: GestureDetector(
              onTap: scrollToTop,
              child: const Text("Panel de Reportes", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            backgroundColor: const Color(0xFF800000), 
            foregroundColor: Colors.white,
          ),
          body: RefreshIndicator(
            onRefresh: cargarReportes,
            color: const Color(0xFF800000),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000))) 
                : _reportes.isEmpty
                    ? ListView( 
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 150),
                          Icon(Icons.inbox, size: 80, color: Colors.grey),
                          SizedBox(height: 16),
                          Text("No hay ningún reporte aún.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController, 
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: _reportes.length + 1, 
                        itemBuilder: (context, index) {
                          if (index == _reportes.length) {
                            if (!_hayMasDatos) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: _cargandoMas
                                ? const Center(child: CircularProgressIndicator(color: Color(0xFF800000)))
                                : Center(
                                    child: OutlinedButton.icon(
                                      onPressed: _cargarMasReportes,
                                      icon: const Icon(Icons.add, color: Color(0xFF800000)),
                                      label: const Text("Cargar más reportes", style: TextStyle(color: Color(0xFF800000))),
                                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF800000))),
                                    ),
                                  ),
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
        ),
      ),
    );
  }
}

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
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF800000)),
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
                      cacheManager: GestorCacheReportes.instance, 
                      memCacheWidth: 150, 
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
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