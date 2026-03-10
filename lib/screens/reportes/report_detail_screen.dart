import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReportDetailScreen extends StatefulWidget {
  final int reporteId; // Recibimos el ID desde la pantalla anterior

  const ReportDetailScreen({super.key, required this.reporteId});

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  Map<String, dynamic>? _reporteCompleto;
  String _ubicacionExacta = "Cargando...";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _cargarDetalles();
  }

  Future<void> _cargarDetalles() async {
    try {
      final supabase = Supabase.instance.client;
      
      // 1. Descargamos todos los datos del reporte y su categoría
      final reporteData = await supabase.from('reportes').select('''
        *,
        cat_categorias (nombre, icono, color)
      ''').eq('id', widget.reporteId).single();

      // 2. Descargamos el nombre del lugar exacto
      final ubicacionData = await supabase.from('reporte_ubicaciones').select('''
        cat_lugares (nombre)
      ''').eq('reporte_id', widget.reporteId).maybeSingle();

      if (mounted) {
        setState(() {
          _reporteCompleto = reporteData;
          _ubicacionExacta = ubicacionData?['cat_lugares']?['nombre'] ?? 'Ubicación no especificada';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_reporteCompleto == null) {
      return const Scaffold(body: Center(child: Text("No se encontró el reporte")));
    }

    final reporte = _reporteCompleto!;
    final categoria = reporte['cat_categorias'];
    final imageUrl = reporte['evidencia_url'];
    final estado = reporte['estado'] ?? 'desconocido';

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
            // 1. FOTO EN GRANDE (Si tiene)
            if (imageUrl != null)
              Container(
                width: double.infinity,
                // Le ponemos un límite máximo de altura por si es una foto panorámica vertical muy larga
                constraints: const BoxConstraints(maxHeight: 500), 
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain, // <--- LA MAGIA ESTÁ AQUÍ
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
                    Text("Sin evidencia fotográfica", style: TextStyle(color: Colors.grey))
                  ],
                ),
              ),

            // 2. DATOS DEL REPORTE
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Estado y Categoría
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        label: Text(estado.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        backgroundColor: _getColorEstado(estado),
                      ),
                      Chip(
                        avatar: Icon(Icons.category, color: _getColorFromHex(categoria['color']), size: 18),
                        label: Text(categoria['nombre']),
                        backgroundColor: _getColorFromHex(categoria['color']).withValues(alpha: 0.1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),

                  // Título
                  Text(reporte['titulo'], style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),

                  // Ubicación
                  const Text("Ubicación", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF800000)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_ubicacionExacta, style: const TextStyle(fontSize: 16))),
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),

                  // Descripción
                  const Text("Descripción del problema", style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(
                    reporte['descripcion'] ?? 'Sin descripción adicional.',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}