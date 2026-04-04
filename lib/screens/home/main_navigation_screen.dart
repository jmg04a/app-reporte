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
  
  /// GlobalKeys used to delegate hardware keyboard events (like 'Refresh' or 'Scroll to Top')
  /// down to the active child states.
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  final GlobalKey<ProfileScreenState> _profileKey = GlobalKey<ProfileScreenState>();

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
        _cambiarPestana(globalTabIndex.value); // Cambiado a la nueva función centralizada
      }
    });
  }

  @override
  void dispose() {
    _suscripcionInternet.cancel(); // Evita fugas de memoria
    super.dispose();
  }

  // --- NUEVA FUNCIÓN DIRECTORA ---
  void _cambiarPestana(int nuevoIndice) {
    setState(() => _indiceActual = nuevoIndice);
    globalTabIndex.value = nuevoIndice;

    // Esperamos a que Flutter termine de dibujar el cambio de pestaña y luego delegamos el foco
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (nuevoIndice == 0) {
        _homeKey.currentState?.pedirFoco();
      } else if (nuevoIndice == 3) {
        _profileKey.currentState?.pedirFoco();
      }
    });
  }

  /// Lógica del Banner de Conexión
  void _estadoRedCambio(InternetStatus status) {
    final hayConexion = status == InternetStatus.connected;

    if (_tieneInternet != hayConexion) {
      if (mounted) setState(() => _tieneInternet = hayConexion);

      if (!hayConexion) {
        // Mostrar Banner Rojo
        ScaffoldMessenger.of(context).clearMaterialBanners();

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

          ScaffoldMessenger.of(context).clearSnackBars();

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
    
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _salirDeLaApp();
      },
      child: Scaffold(
        body: IndexedStack(
          index: stackIndex,
          children: [
            HomeScreen(key: _homeKey),
            ProfileScreen(
              key: _profileKey, 
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
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FilterScreen()),
              );
              _cambiarPestana(_indiceActual); // Recuperar foco en pestaña actual
            } else if (index == 2) {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const CreateReportScreen()),
              );
              _homeKey.currentState?.cargarReportes();
              _cambiarPestana(0); // Volver al Home y pedir foco
            } else {
              _cambiarPestana(index); // Cambio de pestaña normal
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