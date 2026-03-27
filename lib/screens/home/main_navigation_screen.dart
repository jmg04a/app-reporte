import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- IMPORTANTE: Conecta este archivo con tu main.dart ---
import '../../main.dart'; // <--- AJUSTA ESTA RUTA HACIA TU main.dart SI ES NECESARIO

import '../reportes/filter_screen.dart'; 
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

  String _nombreUsuario = 'Cargando...';
  String _rolUsuario = '';
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();

    // ESCUCHAMOS EL TECLADO GLOBAL
    globalTabIndex.addListener(() {
      // Solo actualizamos si el valor es Home (0) o Perfil (3)
      if (mounted && (globalTabIndex.value == 0 || globalTabIndex.value == 3)) {
        setState(() {
          _indiceActual = globalTabIndex.value;
        });
      }
    });
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

  Widget _construirPantalla() {
    if (_indiceActual == 3) {
      return ProfileScreen(
        nombre: _nombreUsuario,
        rol: _rolUsuario,
        avatarUrl: _avatarUrl,
        onNombreCambiado: (nuevoNombre) {
          setState(() => _nombreUsuario = nuevoNombre);
        },
        onAvatarCambiado: (nuevaUrl) {
          setState(() => _avatarUrl = nuevaUrl);
        },
      );
    }
    
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
              // 1. BÚSQUEDA: Abre encima de la barra
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FilterScreen()),
              );
            } else if (index == 2) {
              // 2. CREAR REPORTE: Abre encima de la barra
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateReportScreen()),
              );
              _homeKey.currentState?.cargarReportes();
              
              // Regresamos al Home y sincronizamos el control global
              setState(() => _indiceActual = 0);
              globalTabIndex.value = 0; 
            } else {
              // 0 y 3 (HOME Y PERFIL): Cambian de pestaña en la misma barra
              setState(() => _indiceActual = index);
              globalTabIndex.value = index; 
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
              icon: Icon(Icons.add),
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