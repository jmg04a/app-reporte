import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportDetailScreen extends StatefulWidget {
  final int reporteId;

  const ReportDetailScreen({super.key, required this.reporteId});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  Map<String, dynamic>? _reporteCompleto;
  String _ubicacionExacta = "Cargando...";
  bool _isLoading = true;
  
  // --- VARIABLES DE PERMISOS ---
  bool _isAdmin = false;
  String _estadoActual = 'pendiente';

  // Lista de estados permitidos en el sistema
  final List<String> _estadosDisponibles = ['pendiente', 'en proceso', 'resuelto'];

  @override
  void initState() {
    super.initState();
    _cargarDetalles();
  }

  Future<void> _cargarDetalles() async {
    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser!.id;

      // 1. Verificamos si el usuario actual es administrador buscando su rol en 'perfiles'
      try {
        final currentUserData = await supabase
            .from('perfiles')
            .select('rol')
            .eq('id', currentUserId)
            .maybeSingle();
            
        if (currentUserData != null && currentUserData['rol'] == 'admin') {
          _isAdmin = true;
        }
      } catch (e) {
        debugPrint("Error verificando rol: $e");
      }

      // 2. Descargamos el reporte cruzando datos con cat_categorias, perfiles y estudiantes
      final reporteData = await supabase.from('reportes').select('''
        *,
        cat_categorias (nombre, icono, color),
        perfiles (
          nombre,
          estudiantes (numero_control)
        )
      ''').eq('id', widget.reporteId).single();

      // 3. Descargamos el nombre del lugar
      final ubicacionData = await supabase.from('reporte_ubicaciones').select('''
        cat_lugares (nombre)
      ''').eq('reporte_id', widget.reporteId).maybeSingle();

      if (mounted) {
        setState(() {
          _reporteCompleto = reporteData;
          _estadoActual = reporteData['estado'] ?? 'pendiente';
          _ubicacionExacta = ubicacionData?['cat_lugares']?['nombre'] ?? 'Ubicación no especificada';
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

  // --- FUNCIÓN DEL ADMINISTRADOR PARA CAMBIAR ESTADO ---
  Future<void> _actualizarEstado(String nuevoEstado) async {
    if (nuevoEstado == _estadoActual) return; // Si es el mismo, no hacemos nada

    // Mostramos un indicador de carga rápido en pantalla
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Actualizando estado...'), duration: Duration(seconds: 1)),
    );

    try {
      await Supabase.instance.client
          .from('reportes')
          .update({'estado': nuevoEstado})
          .eq('id', widget.reporteId);

      setState(() {
        _estadoActual = nuevoEstado;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Estado actualizado correctamente!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar estado: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- HELPERS VISUALES ---
  Color _getColorFromHex(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return Colors.grey;
    return Color(int.parse('FF${hexColor.replaceAll('#', '')}', radix: 16));
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
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF800000))));
    }

    if (_reporteCompleto == null) {
      return const Scaffold(body: Center(child: Text("No se encontró el reporte")));
    }

    final reporte = _reporteCompleto!;
    final categoria = reporte['cat_categorias'];
    final imageUrl = reporte['evidencia_url'];
    
    // --- EXTRACCIÓN SEGURA DE DATOS DEL CREADOR ---
    final perfilCreador = reporte['perfiles']; 
    final nombreCreador = perfilCreador?['nombre'] ?? 'Usuario Desconocido';
    
    // Dependiendo de cómo lo devuelva Supabase (lista o mapa), sacamos el número de control
    String? numeroControl;
    final dataEstudiante = perfilCreador?['estudiantes'];
    if (dataEstudiante != null) {
      if (dataEstudiante is List && dataEstudiante.isNotEmpty) {
        numeroControl = dataEstudiante[0]['numero_control'];
      } else if (dataEstudiante is Map) {
        numeroControl = dataEstudiante['numero_control'];
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Detalle del Reporte"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. IMAGEN DEL REPORTE (Ajustada para verse completa)
            if (imageUrl != null)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 400), 
                color: Colors.black87,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain, 
                  errorBuilder: (context, error, stackTrace) => 
                      const SizedBox(height: 200, child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                ),
              )
            else
              Container(
                height: 150,
                color: Colors.grey[200],
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                    Text("Sin evidencia fotográfica", style: TextStyle(color: Colors.grey))
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // 2. CONTROLES DE ADMINISTRADOR O VISTA NORMAL DE ESTADO
                  if (_isAdmin) ...[
                    const Text("Gestión de Administrador", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _getColorEstado(_estadoActual).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _getColorEstado(_estadoActual)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _estadoActual,
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down, color: _getColorEstado(_estadoActual)),
                          items: _estadosDisponibles.map((estado) {
                            return DropdownMenuItem(
                              value: estado,
                              child: Text(estado.toUpperCase(), style: TextStyle(color: _getColorEstado(estado), fontWeight: FontWeight.bold)),
                            );
                          }).toList(),
                          onChanged: (nuevoEstado) {
                            if (nuevoEstado != null) _actualizarEstado(nuevoEstado);
                          },
                        ),
                      ),
                    ),
                  ] else ...[
                     // Si no es admin, solo ve el "chip" bonito sin poder tocarlo
                    Chip(
                      label: Text(_estadoActual.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      backgroundColor: _getColorEstado(_estadoActual),
                    ),
                  ],
                  
                  const SizedBox(height: 15),

                  // 3. DATOS PRINCIPALES
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(reporte['titulo'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                      Chip(
                        avatar: Icon(Icons.category, color: _getColorFromHex(categoria['color']), size: 18),
                        label: Text(categoria['nombre']),
                        backgroundColor: _getColorFromHex(categoria['color']).withValues(alpha: 0.1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 4. TARJETA DE QUIÉN LO REPORTÓ
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!)
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFF800000).withValues(alpha: 0.1),
                          child: const Icon(Icons.person, color: Color(0xFF800000)),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Reportado por", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              Text(nombreCreador, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              if (numeroControl != null)
                                Text("No. Control: $numeroControl", style: const TextStyle(fontSize: 14, color: Colors.blueGrey)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. UBICACIÓN Y DESCRIPCIÓN
                  const Text("Ubicación", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF800000)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_ubicacionExacta, style: const TextStyle(fontSize: 16))),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),

                  const Text("Descripción del problema", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    reporte['descripcion'] ?? 'Sin descripción adicional.',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}