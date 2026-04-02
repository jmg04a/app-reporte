import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_report_screen.dart'; 

/// Comprehensive detail view for a specific report.
///
/// Implements Role-Based Access Control (RBAC) at the UI level:
/// - **Admins:** Can mutate the resolution state (Pending -> In Progress -> Resolved) and soft-delete.
/// - **Creators:** Can edit the payload (if pending) and soft-delete their own reports.
/// - **Standard Users:** Can view details and toggle their "Me too" reaction.
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
  
  // --- RBAC and State Variables ---
  bool _isAdmin = false;
  bool _isCreator = false; 
  String _estadoActual = 'pendiente';

  // --- Reaction Mechanics Variables ---
  bool _yaReacciono = false;
  int _contadorReacciones = 0;

  final List<String> _estadosDisponibles = ['pendiente', 'en proceso', 'resuelto'];

  @override
  void initState() {
    super.initState();
    _cargarDetalles();
  }

  /// Fetches the comprehensive payload for the requested report.
  ///
  /// Resolves all required foreign keys (category, user, location) and 
  /// performs parallel checks to establish the current user's RBAC privileges 
  /// and previous reaction state.
  Future<void> _cargarDetalles() async {
    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser!.id;

      // Determine administrative privileges
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

      // Fetch primary payload with inner joins
      final reporteData = await supabase.from('reportes').select('''
        *,
        cat_categorias (nombre, icono, color),
        perfiles (
          nombre,
          avatar_url,
          estudiantes (numero_control)
        )
      ''').eq('id', widget.reporteId).single();

      final ubicacionData = await supabase.from('reporte_ubicaciones').select('''
        cat_lugares (nombre)
      ''').eq('reporte_id', widget.reporteId).maybeSingle();

      // Determine if the current user has already reacted to this report
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
          
          _contadorReacciones = reporteData['reaccion_count'] ?? 0;
          _yaReacciono = reaccionData != null; 
          _isCreator = reporteData['usuario_id'] == currentUserId; 
          
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

  /// Mutates the resolution state of the report (Admin only).
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

      if (!mounted) return;

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

  /// Toggles the user's reaction to the report.
  ///
  /// Implements an Optimistic UI approach: the local state (reaction count and toggle) 
  /// is mutated immediately before the network request finishes, providing instant 
  /// feedback. If the network request fails, the state is rolled back in the `catch` block.
  Future<void> _toggleReaccion() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser!.id;

    // Optimistic update
    setState(() {
      _yaReacciono = !_yaReacciono;
      _contadorReacciones += _yaReacciono ? 1 : -1;
    });

    try {
      if (_yaReacciono) {
        await supabase.from('reacciones').insert({
          'reporte_id': widget.reporteId,
          'usuario_id': userId,
        });
      } else {
        await supabase
            .from('reacciones')
            .delete()
            .match({'reporte_id': widget.reporteId, 'usuario_id': userId});
      }
    } catch (e) {
      // Rollback on failure
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

  /// Executes a "Soft Delete" on the report.
  ///
  /// Instead of a destructive SQL DELETE, it sets the `visible` flag to false. 
  /// This maintains referential integrity in the database and preserves historical 
  /// data for administrative audits while hiding it from the public feeds.
  Future<void> _borrarReporte() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 10),
            Text("Eliminar Reporte"),
          ],
        ),
        content: const Text("¿Estás seguro de que deseas eliminar este reporte? Se ocultará del sistema y ya no será visible."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sí, eliminar"),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        await Supabase.instance.client
            .from('reportes')
            .update({'visible': false})
            .eq('id', widget.reporteId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reporte eliminado exitosamente'), backgroundColor: Colors.green),
          );
          Navigator.pop(context); 
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al eliminar: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

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

  String _formatearFecha(String? fechaIso) {
    if (fechaIso == null) return 'Fecha desconocida';
    try {
      final fecha = DateTime.parse(fechaIso).toLocal();
      final meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
      
      final ampm = fecha.hour >= 12 ? 'PM' : 'AM';
      int hora = fecha.hour > 12 ? fecha.hour - 12 : fecha.hour;
      if (hora == 0) hora = 12;
      final minutos = fecha.minute.toString().padLeft(2, '0');
      
      return '${fecha.day} de ${meses[fecha.month - 1]}, ${fecha.year} a las $hora:$minutos $ampm';
    } catch (e) {
      return 'Fecha no válida';
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
    
    final perfilCreador = reporte['perfiles']; 
    final nombreCreador = perfilCreador?['nombre'] ?? 'Usuario Desconocido';
    final avatarUrl = perfilCreador?['avatar_url'];
    final fechaFormateada = _formatearFecha(reporte['created_at']); 
    
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
        actions: [
          // Edit permission explicitly constrained to the original creator 
          // and only when the report is still in 'pending' status.
          if (_isCreator && _estadoActual.toLowerCase() == 'pendiente')
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: "Editar reporte",
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateReportScreen(reporteExistente: _reporteCompleto),
                  ),
                );
                _cargarDetalles(); 
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                              
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.access_time, size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(fechaFormateada, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text("Ubicación", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF800000)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_ubicacionExacta, style: const TextStyle(fontSize: 16))),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 15), child: Divider()),

                  const Text("Descripción del problema", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    reporte['descripcion'] ?? 'Sin descripción adicional.',
                    style: const TextStyle(fontSize: 16),
                  ),
                  
                  const SizedBox(height: 30),
                  const Divider(),
                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
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
                      
                      // --- Reaction Action Button ---
                      // Implements frontend RBAC to prevent self-voting.
                      // If the current user is the creator of the report (_isCreator), 
                      // the onPressed callback is set to null, implicitly mutating the 
                      // Material widget state to 'disabled' and preventing API calls.
                      ElevatedButton.icon(
                        onPressed: _isCreator ? null : _toggleReaccion,
                        icon: Icon(
                          _isCreator 
                              ? Icons.person 
                              : (_yaReacciono ? Icons.check_circle : Icons.warning_amber_rounded),
                          color: _isCreator 
                              ? Colors.grey.shade600 
                              : (_yaReacciono ? Colors.white : const Color(0xFF800000)),
                        ),
                        label: Text(
                          _isCreator 
                              ? "Tu reporte" 
                              : (_yaReacciono ? "Ya reportado" : "A mí también"),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          // Dynamic styling based on Optimistic UI state and RBAC status
                          backgroundColor: _yaReacciono ? const Color(0xFF800000) : Colors.white,
                          foregroundColor: _yaReacciono ? Colors.white : const Color(0xFF800000),
                          disabledBackgroundColor: Colors.grey.shade200, 
                          disabledForegroundColor: Colors.grey.shade500,
                          elevation: _yaReacciono && !_isCreator ? 2 : 0,
                          side: BorderSide(
                            color: _isCreator || _yaReacciono 
                                ? Colors.transparent 
                                : const Color(0xFF800000),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),

                  if (_isAdmin || _isCreator) ...[
                    const Divider(),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _borrarReporte,
                        icon: const Icon(Icons.delete_forever),
                        label: const Text("ELIMINAR REPORTE", style: TextStyle(fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

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