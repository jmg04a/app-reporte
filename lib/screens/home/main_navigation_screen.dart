import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import '../../main.dart'; 
import '../reportes/filter_screen.dart'; 
import 'home_screen.dart';
import 'profile_screen.dart';
import '../reportes/create_report_screen.dart';

/// Root application shell after authentication.
///
/// Manages the primary [BottomNavigationBar] and preserves the state of 
/// the main feed ([HomeScreen]) and user profile ([ProfileScreen]) 
/// using an [IndexedStack] to prevent unnecessary widget rebuilds.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _indiceActual = 0;
  
  /// GlobalKey used to delegate hardware keyboard events (like 'Scroll to Top')
  /// down to the active [HomeScreenState].
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  String _nombreUsuario = 'Cargando...';
  String _rolUsuario = '';
  String? _avatarUrl;

  // Variables para el monitor de red
  late StreamSubscription<InternetStatus> _suscripcionInternet;
  bool _tieneInternet = true;
  bool _esPrimerArranque = true;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();

    // --- Monitor de Internet Real (Hardware + Ping) ---
    _suscripcionInternet = InternetConnection().onStatusChange.listen(_estadoRedCambio);

    // Sync local navigation state with global keyboard shortcut events.
    globalTabIndex.addListener(() {
      if (mounted && (globalTabIndex.value == 0 || globalTabIndex.value == 3)) {
        setState(() {
          _indiceActual = globalTabIndex.value;
        });
      }
    });
  }

  @override
  void dispose() {
    _suscripcionInternet.cancel(); // Evita fugas de memoria
    super.dispose();
  }

  /// Lógica del Banner de Conexión
  void _estadoRedCambio(InternetStatus status) {
    final hayConexion = status == InternetStatus.connected;

    if (_tieneInternet != hayConexion) {
      if (mounted) setState(() => _tieneInternet = hayConexion);

      if (!hayConexion) {
        // Mostrar Banner Rojo
        ScaffoldMessenger.of(context).showMaterialBanner(
          MaterialBanner(
            backgroundColor: const Color(0xFF800000), // Guinda ITL
            leading: const Icon(Icons.wifi_off, color: Colors.white),
            content: const Text(
              "Sin conexión a Internet. Verifica tu red.",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                child: const Text("Entendido", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      } else {
        // Ocultar Banner Rojo y mostrar SnackBar Verde (solo si no es el primer arranque)
        ScaffoldMessenger.of(context).clearMaterialBanners();
        if (!_esPrimerArranque) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.wifi, color: Colors.white),
                  SizedBox(width: 10),
                  Text("¡Conexión restaurada!"),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
    _esPrimerArranque = false;
  }

  /// Fetches basic user metadata to populate the profile tab reactively.
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

  /// Intercepts the back button at the root level to prevent accidental 
  /// app closures, requiring explicit user confirmation.
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

  @override
  Widget build(BuildContext context) {
    // Maps the 4-item NavigationBar index to the 2-item IndexedStack.
    int stackIndex = _indiceActual == 3 ? 1 : 0;
    
    // Evaluate hardware platform to apply correct modifier keys (Cmd/Ctrl).
    final bool isMac = !kIsWeb && Platform.isMacOS;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _salirDeLaApp();
      },
      // Root-level keyboard event listener. Prevents child screens from
      // competing for Focus and ensures global hotkeys always register.
      child: CallbackShortcuts(
        bindings: {
          SingleActivator(LogicalKeyboardKey.arrowUp, control: !isMac, meta: isMac): () {
            if (_indiceActual == 0) _homeKey.currentState?.scrollToTop();
          },
          const SingleActivator(LogicalKeyboardKey.home): () {
            if (_indiceActual == 0) _homeKey.currentState?.scrollToTop();
          },
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: IndexedStack(
              index: stackIndex,
              children: [
                HomeScreen(key: _homeKey),
                
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
                  // Push imperative route over the shell for search view.
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FilterScreen()),
                  );
                } else if (index == 2) {
                  // Push imperative route for creation, awaiting its pop to refresh the feed.
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