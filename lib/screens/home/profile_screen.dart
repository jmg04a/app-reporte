import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../auth/login_screen.dart'; // Asegúrate de que esta ruta sea correcta

class ProfileScreen extends StatelessWidget {
  final String nombre;
  final String rol;
  final String? avatarUrl;

  const ProfileScreen({super.key, required this.nombre, required this.rol, this.avatarUrl});

  Future<void> _cerrarSesion(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cerrar Sesión"),
        content: const Text("¿Estás seguro de que deseas salir de tu cuenta?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sí, cerrar sesión"),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        // pushAndRemoveUntil borra todo el historial de pantallas para que no puedan regresar dándole "Atrás"
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false, 
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mi Perfil"),
        backgroundColor: const Color(0xFF800000),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // FOTO DE PERFIL
            CircleAvatar(
              radius: 60,
              backgroundColor: const Color(0xFF800000).withValues(alpha: 0.1),
              backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
              child: avatarUrl == null ? const Icon(Icons.person, size: 60, color: Color(0xFF800000)) : null,
            ),
            const SizedBox(height: 20),
            
            // DATOS DEL USUARIO
            Text(nombre, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: rol == 'admin' ? Colors.amber.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: rol == 'admin' ? Colors.amber : Colors.blue)
              ),
              child: Text(
                rol.toUpperCase(),
                style: TextStyle(
                  color: rol == 'admin' ? Colors.orange[800] : Colors.blue[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 12
                ),
              ),
            ),
            const SizedBox(height: 50),
            
            // BOTÓN DE CERRAR SESIÓN
            ElevatedButton.icon(
              onPressed: () => _cerrarSesion(context),
              icon: const Icon(Icons.logout),
              label: const Text("CERRAR SESIÓN", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
              ),
            ),
          ],
        ),
      ),
    );
  }
}