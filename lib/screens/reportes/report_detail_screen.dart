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
  
  // --- VARIABLES DE PERMISOS Y ESTADO ---
  bool _isAdmin = false;
  String _estadoActual = 'pendiente';

  // --- NUEVAS VARIABLES PARA REACCIONES ---
  bool _yaReacciono = false;
  int _contadorReacciones = 0;

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

      // 1. Verificamos si el usuario actual es administrador
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
          avatar_url,
          estudiantes (numero_control)
        )
      ''').eq('id', widget.reporteId).single();

      // 3. Descargamos el nombre del lugar
      final ubicacionData = await supabase.from('reporte_ubicaciones').select('''
        cat_lugares (nombre)
      ''').eq('reporte_id', widget.reporteId).maybeSingle();

      // 4. NUEVO: Verificamos si el usuario actual ya reaccionó a este reporte
      final reaccionData = await supabase
          .from('reacciones')
          .select('id')
          .eq('reporte_id', widget.reporteId)
          .eq('usuario_id', currentUserId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _reporteCompleto = reporteData;
          _estadoActual = reporteData['estado'] ?? 'pendiente';
          _ubicacionExacta = ubicacionData?['cat_lugares']?['nombre'] ?? 'Ubicación no especificada';
          
          // Guardamos el conteo inicial y si ya había reaccionado
          _contadorReacciones = reporteData['reaccion_count'] ?? 0;
          _yaReacciono = reaccionData != null; // Si encuentra un ID, significa que ya reaccionó
          
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

  // --- NUEVA FUNCIÓN PARA EL BOTÓN DE "ME GUSTA" ---
  Future<void> _toggleReaccion() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;

    // Cambiamos la interfaz inmediatamente para que se sienta instantáneo (Optimistic UI)
    setState(() {
      _yaReacciono = !_yaReacciono;
      _contadorReacciones += _yaReacciono ? 1 : -1;
    });

    try {
      if (_yaReacciono) {
        // Le dio a "Tengo el problema" -> Insertamos
        await supabase.from('reacciones').insert({
          'reporte_id': widget.reporteId,
          'usuario_id': userId,
        });
      } else {
        // Le quitó el "Tengo el problema" -> Borramos
        await supabase
            .from('reacciones')
            .delete()
            .match({'reporte_id': widget.reporteId, 'usuario_id': userId});
      }
    } catch (e) {
      // Si falla por falta de internet o error, revertimos el botón a como estaba
      if (mounted) {
        setState(() {
          _yaReacciono = !_yaReacciono;
          _contadorReacciones += _yaReacciono ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al procesar tu reacción'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- FUNCIÓN DEL ADMINISTRADOR PARA CAMBIAR ESTADO ---
  Future<void> _actualizarEstado(String nuevoEstado) async {
    if (nuevoEstado == _estadoActual) return;

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
    
    // EXTRACCIÓN SEGURA DE DATOS DEL CREADOR
    final perfilCreador = reporte['perfiles']; 
    final nombreCreador = perfilCreador?['nombre'] ?? 'Usuario Desconocido';
    final avatarUrl = perfilCreador?['avatar_url'];
    
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
            // 1. IMAGEN DEL REPORTE
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
                          radius: 24,
                          backgroundColor: const Color(0xFF800000).withValues(alpha: 0.1),
                          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null ? const Icon(Icons.person, color:  Color(0xFF800000)) : null,
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
                  
                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 10),

                  // 6. ¡NUEVO! SECCIÓN DE REACCIONES EN LA PARTE INFERIOR
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Lado Izquierdo: Contador visual
                      Row(
                        children: [
                          Icon(Icons.group, color: Colors.grey[600]),
                          const SizedBox(width: 8),
                          Text(
                            "$_contadorReacciones ${_contadorReacciones == 1 ? 'persona tiene' : 'personas tienen'}\neste problema",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey[800]),
                          ),
                        ],
                      ),
                      
                      // Lado Derecho: El botón interactivo
                      ElevatedButton.icon(
                        onPressed: _toggleReaccion,
                        icon: Icon(
                          _yaReacciono ? Icons.check_circle : Icons.warning_amber_rounded,
                          color: _yaReacciono ? Colors.white : const Color(0xFF800000),
                        ),
                        label: Text(
                          _yaReacciono ? "Ya reportado" : "A mí también",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _yaReacciono ? const Color(0xFF800000) : Colors.white,
                          foregroundColor: _yaReacciono ? Colors.white : const Color(0xFF800000),
                          elevation: _yaReacciono ? 2 : 0,
                          side: BorderSide(
                            color: _yaReacciono ? Colors.transparent : const Color(0xFF800000),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ],
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