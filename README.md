# 🐈‍⬛ Sistema de Reportes ITL

Una aplicación móvil multiplataforma diseñada para optimizar la gestión y el seguimiento de reportes de infraestructura, mantenimiento y seguridad dentro del Instituto Tecnológico de la Laguna.

## 🚀 Características Principales

El sistema está construido con una arquitectura moderna y escalable, enfocada en la experiencia de usuario y el rendimiento:

* **Autenticación Institucional:** Registro e inicio de sesión seguro validando el dominio `@correo.itlalaguna.edu.mx`.
* **Role-Based Access Control (RBAC):** Interfaces dinámicas que se adaptan si el usuario es Estudiante, Personal o Administrador.
* **Interfaz de Usuario Optimista (Optimistic UI):** Reacciones y cambios de estado instantáneos que se sincronizan en segundo plano para una experiencia sin interrupciones.
* **Gestión Inteligente de Caché:** Implementación de persistencia local para datos de perfil y un administrador de caché agresivo para imágenes (`flutter_cache_manager`), reduciendo el consumo de datos y RAM.
* **Soporte Offline para Borradores:** Autoguardado local de reportes en proceso (`SharedPreferences`) para evitar pérdida de datos si la aplicación se cierra inesperadamente.
* **Motor de Búsqueda Dinámico:** Constructor de consultas complejas (PostgREST) para filtrar reportes por texto, categoría, ubicación exacta y estado.
* **Paginación Eficiente (Infinite Scroll):** Carga perezosa de reportes para mantener un bajo consumo de memoria (configurado con un `cacheExtent` optimizado para mitigar parpadeos).

## 🛠️ Stack Tecnológico

* **Frontend:** [Flutter](https://flutter.dev/) & Dart
* **Backend as a Service (BaaS):** [Supabase](https://supabase.com/)
  * *Auth:* Gestión de sesiones y recuperación de contraseñas.
  * *Database:* PostgreSQL relacional con políticas de seguridad a nivel de fila (RLS).
  * *Storage:* Almacenamiento binario para evidencias fotográficas y avatares.

## ⚙️ Requisitos Previos

Antes de ejecutar el proyecto, asegúrate de tener instalado:
1. Flutter SDK (Última versión estable)
2. Dart SDK
3. Un archivo `.env` en la raíz del proyecto con las credenciales de Supabase:
   ```env
   SUPABASE_URL=tu_url_aqui
   SUPABASE_ANON_KEY=tu_clave_aqui

## 💻 Instalación y Ejecución

1. Clona este repositorio:
```bash
git clone https://github.com/jmg04a/app-reporte.git
```
2. Instala las dependencias
```bash
cd reporte-itl
flutter pub get
```
3. Ejecuta la aplicación en tu emulador o dispositivo físico:
```bash
flutter run
```

## 🗄️ Configuración de la Base de Datos (Fase de Pruebas)

Toda la infraestructura del backend (tablas, relaciones, funciones, triggers, reglas RLS y buckets de Storage) está documentada y versionada en este repositorio.

Para levantar tu propio entorno en Supabase, ejecuta los scripts dentro de la carpeta `database/` en el **SQL Editor** siguiendo este orden estricto:

1. **`01_esquema.sql` (Infraestructura):** Define las tablas, relaciones y funciones de seguridad (con blindaje `search_path`). También configura los disparadores (triggers) y los buckets de almacenamiento `evidencias` y `avatars` con sus respectivas políticas RLS.
2. **`02_seed.sql` (Catálogos Base):** Inserta los datos maestros necesarios para que la aplicación sea funcional desde el primer inicio, como el catálogo de carreras, edificios y las categorías de reportes.
3. **`03_test_data.sql` (Opcional - Pruebas de Estrés):** Genera automáticamente 1,000 reportes aleatorios vinculados a usuarios y ubicaciones existentes. Este script es fundamental para validar el rendimiento del *Infinite Scroll*, la persistencia de la caché de imágenes y la gestión de memoria RAM de la aplicación.

> **Nota importante:** Los scripts de esquema y seed utilizan transacciones de base de datos (`BEGIN; ... COMMIT;`) para garantizar que la configuración se aplique de forma atómica y segura.

## 📋 Próximas Mejoras (Roadmap / To-Do)

El proyecto se encuentra en constante evolución. Las siguientes tareas están planeadas para futuras versiones:

- [ ] **Diccionario de Errores:** Centralizar el manejo de excepciones para traducir errores técnicos de Supabase a mensajes genéricos y amigables para el usuario final.
- [ ] **Atajos Avanzados:** Implementar soporte extendido de atajos de teclado (Shortcuts) dedicados para la versión de escritorio (Windows, macOS, Linux).
- [ ] **Modularización de BD:** Refactorizar la arquitectura para abstraer la conexión y consultas de Supabase en repositorios o servicios modulares.
- [ ] **Pantalla de Ajustes:** Crear un menú de configuración para manejar preferencias locales de la aplicación.
- [ ] **Dark Mode:** Soporte nativo para Tema Oscuro y opciones de personalización de la paleta de colores.
- [ ] **Branding Oficial:** Diseño e integración de recursos gráficos finales (ícono de la app, logotipo y *Splash Screen* mejorado).
- [x] **Scripts de la BD:** Para que cualquiera pueda replicarla y probar la aplicación.

