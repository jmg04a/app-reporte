import 'dart:io'; 
import 'package:flutter/foundation.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:window_manager/window_manager.dart'; 

import 'screens/splash/splash_screen.dart'; 
import 'screens/reportes/filter_screen.dart'; 
import 'screens/reportes/create_report_screen.dart'; 

/// Llave global para el navegador de la aplicación.
///
/// Permite el acceso al [NavigatorState] para realizar enrutamiento imperativo
/// desde cualquier parte del código, incluso fuera del árbol de widgets principal.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Notificador de estado para el índice de la barra de navegación.
///
/// Gestiona y sincroniza el estado activo del `BottomNavigationBar` a lo largo 
/// de toda la aplicación de manera global.
final ValueNotifier<int> globalTabIndex = ValueNotifier<int>(0);

/// Empuja una nueva ruta globalmente previniendo el apilamiento duplicado.
///
/// Evalúa la pila de navegación actual y elimina las rutas secundarias intermedias
/// para mantener la pila limpia, regresar al `MainNavigationScreen` raíz, y prevenir 
/// el consumo excesivo de memoria por vistas superpuestas.
///
/// Parámetros:
/// * [nombreRuta]: El identificador en texto de la ruta (ej. '/buscar').
/// * [pantalla]: El widget que se va a renderizar en la pantalla.
void _abrirPantallaGlobal(String nombreRuta, Widget pantalla) {
  bool isAlreadyOnTop = false;
  
  // Inspecciona la ruta superior sin mutar la pila de navegación.
  navigatorKey.currentState?.popUntil((route) {
    isAlreadyOnTop = route.settings.name == nombreRuta;
    return true; 
  });

  // Aborta si la ruta objetivo ya se está mostrando activamente.
  if (isAlreadyOnTop) return;

  // Limpia las rutas secundarias intermedias para volver al root.
  navigatorKey.currentState?.popUntil((route) => route.isFirst);
  
  // Empuja la nueva ruta con sus respectivos RouteSettings.
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      settings: RouteSettings(name: nombreRuta),
      builder: (_) => pantalla
    )
  );
}

/// Punto de entrada principal de la aplicación Reportes ITL.
///
/// Se encarga de inicializar los bindings de Flutter, configurar los límites 
/// estrictos de memoria caché para imágenes, preparar la ventana nativa en sistemas
/// de escritorio (Windows, Linux, macOS), cargar el archivo `.env` y establecer
/// la conexión con el backend asíncrono.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  PaintingBinding.instance.imageCache.maximumSize = 20; // Máximo 20 imágenes en RAM
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 15; // 15 MB de tope

  // Inicialización de la ventana para plataformas de escritorio.
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(900, 860),         
      minimumSize: Size(600, 700),   
      center: true,                  
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: "Reportes ITL",         
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Inicialización de variables de entorno.
  await dotenv.load(fileName: "assets/.env");

  // Inicialización del servicio BaaS de Supabase.
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const MyApp());
}

/// Instancia única (Singleton) del cliente de base de datos.
///
/// Se utiliza para realizar todas las transacciones y consultas a Supabase
/// de manera global en la aplicación.
final supabase = Supabase.instance.client;

/// Widget raíz de la interfaz de usuario.
///
/// Configura el [MaterialApp], define el tema visual principal usando 
/// `ColorScheme` y envuelve la aplicación en un [CallbackShortcuts] para 
/// habilitar la navegación rápida mediante el teclado en entornos de escritorio.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Verificación de plataforma para asignar modificadores correctos (Meta en macOS, Control en el resto).
    final bool isMac = !kIsWeb && Platform.isMacOS;

    return CallbackShortcuts(
      bindings: {
        // Desmontar la ruta actual (Cerrar modal/pantalla).
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (navigatorKey.currentState?.canPop() == true) {
            navigatorKey.currentState?.pop();
          }
        },

        // Disparar la vista global de búsqueda.
        SingleActivator(LogicalKeyboardKey.keyF, control: !isMac, meta: isMac,includeRepeats: false): () {
          _abrirPantallaGlobal('/buscar', const FilterScreen());
        },
        SingleActivator(LogicalKeyboardKey.keyK, control: !isMac, meta: isMac,includeRepeats: false): () {
          _abrirPantallaGlobal('/buscar', const FilterScreen());
        },

        // Disparar la vista de creación de reportes.
        SingleActivator(LogicalKeyboardKey.keyN, control: !isMac, meta: isMac,includeRepeats: false): () {
          _abrirPantallaGlobal('/crear_reporte', const CreateReportScreen());
        },

        // Navegar a la raíz principal (Inicio).
        SingleActivator(LogicalKeyboardKey.keyH, control: !isMac, meta: isMac,includeRepeats: false): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst); 
          globalTabIndex.value = 0; 
        },
        SingleActivator(LogicalKeyboardKey.digit1, control: !isMac, meta: isMac,includeRepeats: false): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 0; 
        },

        // Navegar a la raíz principal (Perfil).
        SingleActivator(LogicalKeyboardKey.keyP, control: !isMac, meta: isMac,includeRepeats: false): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 3; 
        },
        SingleActivator(LogicalKeyboardKey.comma, control: !isMac, meta: isMac,includeRepeats: false): () {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
          globalTabIndex.value = 3; 
        },
      },
      child: Focus(
        autofocus: true, 
        child: MaterialApp(
          navigatorKey: navigatorKey, 
          title: 'Reportes ITL',
          debugShowCheckedModeBanner: false, 
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF800000), 
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: const SplashScreen(), 
        ),
      ),
    );
  }
}