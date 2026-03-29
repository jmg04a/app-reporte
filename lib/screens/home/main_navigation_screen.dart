import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- IMPORTANTE: Conecta este archivo con tu main.dart ---
import '../../main.dart'; 

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

  // ¡SE ELIMINÓ LA FUNCIÓN _construirPantalla()!

  @override
@override
  Widget build(BuildContext context) {
    // Lógica inteligente: Si el índice de la barra es 3 (Perfil), mostramos el índice 1 del Stack.
    // De lo contrario, mostramos el índice 0 del Stack (Home).
    int stackIndex = _indiceActual == 3 ? 1 : 0;
    
    // ¡NUEVO! Detectamos si es Mac para los atajos
    final bool isMac = !kIsWeb && Platform.isMacOS; 

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _salirDeLaApp();
      },
      // =========================================================
      // ¡NUEVO! ENVOLVEMOS EL SCAFFOLD PARA ATRAPAR EL TECLADO
      // =========================================================
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.arrowUp, control: !isMac, meta: isMac): () {
            // Solo scrolleamos si estamos en la pestaña de Inicio
            if (_indiceActual == 0) _homeKey.currentState?.scrollToTop();
          },
          const SingleActivator(LogicalKeyboardKey.home): () {
            if (_indiceActual == 0) _homeKey.currentState?.scrollToTop();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            // =========================================================
            // AQUÍ ESTÁ LA MAGIA: INDEXEDSTACK PARA PRESERVAR EL ESTADO
            // =========================================================
            body: IndexedStack(
              index: stackIndex,
              children: [
                // Índice 0 del Stack: HomeScreen (Se mantiene vivo siempre)
                HomeScreen(key: _homeKey),
                
                // Índice 1 del Stack: ProfileScreen (Se mantiene vivo siempre)
                ProfileScreen(
                  nombre: _nombreUsuario,
                  rol: _rolUsuario,
                  avatarUrl: _avatarUrl,
                  onNombreCambiado: (nuevoNombre) {
                    setState(() => _nombreUsuario = nuevoNombre);
                  },
                  onAvatarCambiado: (nuevaUrl) {
                    setState(() => _avatarUrl = nuevaUrl);
                  },
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _indiceActual,
              onDestinationSelected: (int index) async {
                if (index == 1) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FilterScreen()),
                  );
                } else if (index == 2) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CreateReportScreen()),
                  );
                  _homeKey.currentState?.cargarReportes();
                  
                  setState(() => _indiceActual = 0);
                  globalTabIndex.value = 0; 
                } else {
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
        ),
      ),
    );
  }
}