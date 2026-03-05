import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart';
// 1. IMPORTAMOS LA NUEVA PANTALLA
import '../reportes/create_report_screen.dart'; 

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> cerrarSesion(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Panel de Reportes"),
        backgroundColor: const Color(0xFF800000), // Color Guinda
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => cerrarSesion(context),
            tooltip: "Cerrar Sesión",
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 100, color: Colors.green),
            const SizedBox(height: 20),
            const Text(
              "¡Bienvenido al Sistema!",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text("Aquí aparecerán los reportes.", style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 40),
            
            // 2. BOTÓN ACTUALIZADO PARA NAVEGAR A LA PANTALLA REAL
            ElevatedButton.icon(
              onPressed: () {
                // Navegación a la pantalla de crear reporte
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CreateReportScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text("Crear nuevo reporte", style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF800000), // Color guinda ITL
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}