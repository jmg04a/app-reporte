import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_screen.dart';
import 'profile_screen.dart';
import '../reportes/create_report_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _indiceActual = 0;

  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  // Variables de estado interno para conservar la sesión en toda la app
  String _nombreUsuario = 'Cargando...';
  String _rolUsuario = '';
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
  }

  Future<void> _cargarDatosUsuario() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId != null) {
        final userData = await supabase
            .from('perfiles')
            .select('nombre, rol, avatar_url')
            .eq('id', userId)
            .maybeSingle();

        if (userData != null && mounted) {
          setState(() {
            _nombreUsuario = userData['nombre'] ?? 'Usuario Desconocido';
            _rolUsuario = userData['rol'] ?? 'usuario';
            _avatarUrl = userData['avatar_url'];
          });
        }
      }
    } catch (e) {
      debugPrint("Error al cargar datos del usuario: $e");
    }
  }

  Future<void> _salirDeLaApp() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Salir de la App"),
        content: const Text("¿Estás seguro de que deseas cerrar la aplicación?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF800000),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sí, salir"),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      if (kIsWeb) return;
      if (Platform.isAndroid || Platform.isIOS) {
        SystemNavigator.pop();
      } else {
        exit(0);
      }
    }
  }

  // --- FUNCIÓN QUE CONSTRUYE LA PANTALLA CORRECTA ---
  Widget _construirPantalla() {
    if (_indiceActual == 3) {
      return ProfileScreen(
        nombre: _nombreUsuario,
        rol: _rolUsuario,
        avatarUrl: _avatarUrl,
        
        // ¡LA MAGIA OCURRE AQUÍ!
        // Escuchamos los callbacks del Perfil y actualizamos la barra principal
        onNombreCambiado: (nuevoNombre) {
          setState(() => _nombreUsuario = nuevoNombre);
        },
        onAvatarCambiado: (nuevaUrl) {
          setState(() => _avatarUrl = nuevaUrl);
        },
      );
    }
    
    // Si no es el perfil, mostramos el Home
    return HomeScreen(key: _homeKey);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _salirDeLaApp();
      },
      child: Scaffold(
        body: _construirPantalla(),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _indiceActual,
          onDestinationSelected: (int index) async {
            if (index == 1) {
              _homeKey.currentState?.abrirPantallaFiltros();
            } else if (index == 2) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CreateReportScreen()),
              );
              _homeKey.currentState?.cargarReportes();
              setState(() => _indiceActual = 0);
            } else {
              setState(() => _indiceActual = index);
            }
          },
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFF800000).withValues(alpha: 0.2),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: Color(0xFF800000)),
              label: 'Inicio',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search, color: Color(0xFF800000)),
              label: 'Buscar',
            ),
            NavigationDestination(
              icon: Icon(Icons.add_circle_outline),
              selectedIcon: Icon(Icons.add_circle, color: Color(0xFF800000)),
              label: 'Reportar',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: Color(0xFF800000)),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}