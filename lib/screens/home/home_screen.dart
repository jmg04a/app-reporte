import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart';

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
          // BOTÓN DE SALIR
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
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 10),
            const Text("Aquí aparecerán los reportes."),
            const SizedBox(height: 30),
            
            // Botón temporal para probar navegación
            ElevatedButton(
              onPressed: () {
                // Aquí iremos a la pantalla de "Crear Reporte" luego
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Próximamente: Formulario de Reporte")),
                );
              },
              child: const Text("Crear Nuevo Reporte"),
            ),
          ],
        ),
      ),
    );
  }
}