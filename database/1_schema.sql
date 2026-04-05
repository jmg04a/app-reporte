-- ==============================================================================
-- PROYECTO: Sistema de Reportes ITL
-- DESCRIPCIÓN: Script de inicialización de Base de Datos para Supabase.
-- INCLUYE: Tablas, Relaciones, Índices, Funciones, Triggers y Políticas RLS.
-- ==============================================================================

--Nota: Reemplazar "insertar_dominio" con el dominio de su preferencia

BEGIN; -- Iniciamos transacción de seguridad

-- ------------------------------------------------------------------------------
-- 0. EXTENSIONES REQUERIDAS
-- ------------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ------------------------------------------------------------------------------
-- 1. CREACIÓN DE TABLAS (Catálogos)
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cat_carreras (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre text NOT NULL,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.cat_categorias (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre text NOT NULL,
    icono text,
    color text,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.cat_lugares (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre text NOT NULL,
    tipo text NOT NULL,
    parent_id bigint REFERENCES public.cat_lugares(id),
    created_at timestamp with time zone DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 2. CREACIÓN DE TABLAS (Usuarios y Perfiles)
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.perfiles (
    id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email text,
    nombre text,
    rol text NOT NULL DEFAULT 'usuario',
    tipo_usuario text,
    avatar_url text,
    banned boolean DEFAULT false,
    updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.estudiantes (
    usuario_id uuid PRIMARY KEY REFERENCES public.perfiles(id) ON DELETE CASCADE,
    numero_control text NOT NULL UNIQUE,
    carrera_id bigint REFERENCES public.cat_carreras(id),
    created_at timestamp with time zone DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 3. CREACIÓN DE TABLAS (Operación Principal)
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.reportes (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id uuid NOT NULL REFERENCES public.perfiles(id) ON DELETE CASCADE,
    categoria_id bigint NOT NULL REFERENCES public.cat_categorias(id),
    titulo text NOT NULL,
    descripcion text,
    evidencia_url text,
    estado text NOT NULL DEFAULT 'pendiente',
    prioridad text NOT NULL DEFAULT 'media',
    reaccion_count integer DEFAULT 0,
    visible boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.reporte_ubicaciones (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reporte_id bigint NOT NULL REFERENCES public.reportes(id) ON DELETE CASCADE,
    lugar_id bigint NOT NULL REFERENCES public.cat_lugares(id),
    detalles_extra text,
    created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.reacciones (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    reporte_id bigint NOT NULL REFERENCES public.reportes(id) ON DELETE CASCADE,
    usuario_id uuid NOT NULL REFERENCES public.perfiles(id) ON DELETE CASCADE,
    created_at timestamp with time zone DEFAULT now(),
    UNIQUE (reporte_id, usuario_id) 
);

-- ------------------------------------------------------------------------------
-- 4. CREACIÓN DE TABLAS (Auditoría)
-- ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.bitacora_accesos (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id uuid REFERENCES public.perfiles(id) ON DELETE SET NULL,
    email text,
    fecha_ingreso timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.bitacora_auditoria (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id uuid REFERENCES public.perfiles(id) ON DELETE SET NULL,
    accion text NOT NULL,
    id_referencia text,
    detalles text,
    created_at timestamp with time zone DEFAULT now()
);

-- ------------------------------------------------------------------------------
-- 5. ÍNDICES DE RENDIMIENTO
-- ------------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_estudiantes_carrera_id ON public.estudiantes(carrera_id);
CREATE INDEX IF NOT EXISTS idx_reporte_ubicaciones_lugar ON public.reporte_ubicaciones(lugar_id);
CREATE INDEX IF NOT EXISTS idx_reporte_ubicaciones_reporte ON public.reporte_ubicaciones(reporte_id);
CREATE INDEX IF NOT EXISTS idx_reportes_categoria ON public.reportes(categoria_id);
CREATE INDEX IF NOT EXISTS idx_reportes_estado ON public.reportes(estado);
CREATE INDEX IF NOT EXISTS idx_reportes_visible ON public.reportes(visible);
CREATE INDEX IF NOT EXISTS idx_reportes_titulo_buscador ON public.reportes USING gin (titulo gin_trgm_ops);

-- ------------------------------------------------------------------------------
-- 6. FUNCIONES DE NEGOCIO (Lógica Backend)
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.soy_admin() 
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.perfiles
    WHERE id = auth.uid() AND rol = 'admin'
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.actualizar_contador_reacciones() 
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.reportes SET reaccion_count = COALESCE(reaccion_count, 0) + 1 WHERE id = NEW.reporte_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.reportes SET reaccion_count = GREATEST(COALESCE(reaccion_count, 0) - 1, 0) WHERE id = OLD.reporte_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.validar_dominio_itl() 
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
BEGIN
  IF NEW.email NOT ILIKE '%@insertar_dominio' THEN
    RAISE EXCEPTION 'Acceso denegado. Solo se permiten correos institucionales @insertar_dominio';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.manejar_nuevo_usuario() 
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
DECLARE
  _carrera_id bigint;
  _numero_control text;
BEGIN
  _numero_control := substring(NEW.email from 'alu\.([0-9]+)@');

  INSERT INTO public.perfiles (id, email, nombre, rol, tipo_usuario)
  VALUES (
    NEW.id, 
    NEW.email, 
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'Usuario Nuevo'), 
    'usuario',
    CASE WHEN _numero_control IS NOT NULL THEN 'estudiante' ELSE 'docente' END
  )
  ON CONFLICT (id) DO UPDATE SET 
    email = EXCLUDED.email,
    tipo_usuario = EXCLUDED.tipo_usuario;

  IF _numero_control IS NOT NULL AND NEW.raw_user_meta_data->>'carrera_id' IS NOT NULL THEN
    _carrera_id := (NEW.raw_user_meta_data->>'carrera_id')::bigint;
    INSERT INTO public.estudiantes (usuario_id, numero_control, carrera_id)
    VALUES (NEW.id, _numero_control, _carrera_id)
    ON CONFLICT (numero_control) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------------------------
-- 7. FUNCIONES DE AUDITORÍA
-- ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.registrar_acceso() 
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
BEGIN
  IF OLD.last_sign_in_at IS DISTINCT FROM NEW.last_sign_in_at THEN
    INSERT INTO public.bitacora_accesos (usuario_id, email, fecha_ingreso)
    VALUES (NEW.id, NEW.email, now());
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_log_catalogos() 
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
BEGIN
  IF (TG_OP = 'DELETE') THEN
    INSERT INTO public.bitacora_auditoria (usuario_id, accion, id_referencia, detalles)
    VALUES (auth.uid(), 'BORRADO_CATALOGO_' || TG_TABLE_NAME, OLD.id::text, 'Nombre borrado: ' || OLD.nombre);
  END IF;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_log_perfiles() 
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.rol <> NEW.rol THEN
    INSERT INTO public.bitacora_auditoria (usuario_id, accion, id_referencia, detalles)
    VALUES (auth.uid(), 'CAMBIO_ROL', NEW.id::text, 'De ' || OLD.rol || ' a ' || NEW.rol);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_log_reportes() 
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER 
SET search_path TO 'public' AS $$
DECLARE
  usuario_actual uuid;
BEGIN
  usuario_actual := auth.uid();
  
  IF (TG_OP = 'DELETE') THEN
    INSERT INTO public.bitacora_auditoria (usuario_id, accion, id_referencia, detalles)
    VALUES (usuario_actual, 'ELIMINAR_REPORTE', OLD.id::text, 'Titulo: ' || OLD.titulo);
    RETURN OLD;
  ELSIF (TG_OP = 'UPDATE') THEN
    IF (OLD.estado <> NEW.estado) THEN
      INSERT INTO public.bitacora_auditoria (usuario_id, accion, id_referencia, detalles)
      VALUES (usuario_actual, 'CAMBIO_ESTADO', NEW.id::text, 'De ' || OLD.estado || ' a ' || NEW.estado);
    END IF;
    RETURN NEW;
  END IF;
  RETURN NULL; 
END;
$$;

-- ------------------------------------------------------------------------------
-- 8. TRIGGERS (Disparadores de eventos)
-- ------------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trigger_validar_dominio ON auth.users;
CREATE TRIGGER trigger_validar_dominio BEFORE INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.validar_dominio_itl();

DROP TRIGGER IF EXISTS trigger_manejar_nuevo_usuario ON auth.users;
CREATE TRIGGER trigger_manejar_nuevo_usuario AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.manejar_nuevo_usuario();

DROP TRIGGER IF EXISTS trigger_registrar_acceso ON auth.users;
CREATE TRIGGER trigger_registrar_acceso AFTER UPDATE ON auth.users FOR EACH ROW EXECUTE FUNCTION public.registrar_acceso();

DROP TRIGGER IF EXISTS trigger_reacciones ON public.reacciones;
CREATE TRIGGER trigger_reacciones AFTER INSERT OR DELETE ON public.reacciones FOR EACH ROW EXECUTE FUNCTION public.actualizar_contador_reacciones();

DROP TRIGGER IF EXISTS audit_carreras ON public.cat_carreras;
CREATE TRIGGER audit_carreras AFTER DELETE ON public.cat_carreras FOR EACH ROW EXECUTE FUNCTION public.audit_log_catalogos();

DROP TRIGGER IF EXISTS audit_categorias ON public.cat_categorias;
CREATE TRIGGER audit_categorias AFTER DELETE ON public.cat_categorias FOR EACH ROW EXECUTE FUNCTION public.audit_log_catalogos();

DROP TRIGGER IF EXISTS audit_lugares ON public.cat_lugares;
CREATE TRIGGER audit_lugares AFTER DELETE ON public.cat_lugares FOR EACH ROW EXECUTE FUNCTION public.audit_log_catalogos();

-- Desconectamos la función genérica si existía
DROP TRIGGER IF EXISTS trigger_auditoria_perfiles ON public.perfiles;
CREATE TRIGGER trigger_auditoria_perfiles AFTER UPDATE ON public.perfiles FOR EACH ROW EXECUTE FUNCTION public.audit_log_perfiles();

DROP TRIGGER IF EXISTS trigger_auditoria_reportes ON public.reportes;
CREATE TRIGGER trigger_auditoria_reportes AFTER DELETE OR UPDATE ON public.reportes FOR EACH ROW EXECUTE FUNCTION public.audit_log_reportes();

-- Limpiamos funciones viejas
DROP FUNCTION IF EXISTS public.audit_log_general();

-- ------------------------------------------------------------------------------
-- 9. SEGURIDAD A NIVEL DE FILAS (RLS - Row Level Security)
-- ------------------------------------------------------------------------------

ALTER TABLE public.bitacora_accesos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bitacora_auditoria ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cat_carreras ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cat_categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cat_lugares ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estudiantes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reacciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reporte_ubicaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reportes ENABLE ROW LEVEL SECURITY;

-- Políticas de Catálogos
DROP POLICY IF EXISTS "Lectura publica carreras" ON public.cat_carreras;
CREATE POLICY "Lectura publica carreras" ON public.cat_carreras FOR SELECT USING (true);

DROP POLICY IF EXISTS "Lectura publica categorias" ON public.cat_categorias;
CREATE POLICY "Lectura publica categorias" ON public.cat_categorias FOR SELECT USING (true);

DROP POLICY IF EXISTS "Lectura publica lugares" ON public.cat_lugares;
CREATE POLICY "Lectura publica lugares" ON public.cat_lugares FOR SELECT USING (true);

-- Políticas de Perfiles y Estudiantes
DROP POLICY IF EXISTS "Lectura de perfiles solo a logueados" ON public.perfiles;
CREATE POLICY "Lectura de perfiles solo a logueados" ON public.perfiles FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Editar propio perfil" ON public.perfiles;
CREATE POLICY "Editar propio perfil" ON public.perfiles FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "Lectura de estudiantes a logueados" ON public.estudiantes;
CREATE POLICY "Lectura de estudiantes a logueados" ON public.estudiantes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Actualizar propia carrera" ON public.estudiantes;
CREATE POLICY "Actualizar propia carrera" ON public.estudiantes FOR UPDATE TO authenticated USING (usuario_id = auth.uid()) WITH CHECK (usuario_id = auth.uid());

-- Políticas de Reportes
DROP POLICY IF EXISTS "Lectura maestra de reportes" ON public.reportes;
CREATE POLICY "Lectura maestra de reportes" ON public.reportes FOR SELECT USING (
  visible = true OR usuario_id = auth.uid() OR (auth.role() = 'authenticated' AND public.soy_admin() = true)
);

DROP POLICY IF EXISTS "Crear reportes propios" ON public.reportes;
CREATE POLICY "Crear reportes propios" ON public.reportes FOR INSERT WITH CHECK (auth.uid() = usuario_id);

DROP POLICY IF EXISTS "Dueños actualizan sus reportes" ON public.reportes;
CREATE POLICY "Dueños actualizan sus reportes" ON public.reportes FOR UPDATE TO authenticated USING (usuario_id = auth.uid());

DROP POLICY IF EXISTS "Admins actualizan todo" ON public.reportes;
CREATE POLICY "Admins actualizan todo" ON public.reportes FOR UPDATE TO authenticated USING (public.soy_admin() = true);

-- Políticas de Ubicaciones
DROP POLICY IF EXISTS "Leer ubicaciones" ON public.reporte_ubicaciones;
CREATE POLICY "Leer ubicaciones" ON public.reporte_ubicaciones FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Insertar ubicaciones propias" ON public.reporte_ubicaciones;
CREATE POLICY "Insertar ubicaciones propias" ON public.reporte_ubicaciones FOR INSERT TO authenticated WITH CHECK (
  auth.uid() = (SELECT r.usuario_id FROM public.reportes r WHERE r.id = reporte_id)
);

DROP POLICY IF EXISTS "Actualizar ubicaciones propias" ON public.reporte_ubicaciones;
CREATE POLICY "Actualizar ubicaciones propias" ON public.reporte_ubicaciones FOR UPDATE TO authenticated USING (
  auth.uid() = (SELECT r.usuario_id FROM public.reportes r WHERE r.id = reporte_id)
) WITH CHECK (
  auth.uid() = (SELECT r.usuario_id FROM public.reportes r WHERE r.id = reporte_id)
);

-- Políticas de Reacciones
DROP POLICY IF EXISTS "Leer reacciones" ON public.reacciones;
CREATE POLICY "Leer reacciones" ON public.reacciones FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Reaccionar a reportes ajenos" ON public.reacciones;
CREATE POLICY "Reaccionar a reportes ajenos" ON public.reacciones FOR INSERT TO authenticated WITH CHECK (
  auth.uid() = usuario_id AND auth.uid() <> (SELECT r.usuario_id FROM public.reportes r WHERE r.id = reporte_id)
);

DROP POLICY IF EXISTS "Borrar propias reacciones" ON public.reacciones;
CREATE POLICY "Borrar propias reacciones" ON public.reacciones FOR DELETE TO authenticated USING (auth.uid() = usuario_id);

-- Políticas de Auditoría
DROP POLICY IF EXISTS "Admin ve accesos" ON public.bitacora_accesos;
CREATE POLICY "Admin ve accesos" ON public.bitacora_accesos FOR SELECT USING (public.soy_admin() = true);

DROP POLICY IF EXISTS "Admin ve auditoria" ON public.bitacora_auditoria;
CREATE POLICY "Admin ve auditoria" ON public.bitacora_auditoria FOR SELECT USING (public.soy_admin() = true);

-- ------------------------------------------------------------------------------
-- 10. CONFIGURACIÓN DE ALMACENAMIENTO (STORAGE)
-- ------------------------------------------------------------------------------

-- 10.1 BUCKET: EVIDENCIAS
INSERT INTO storage.buckets (id, name, public)
VALUES ('evidencias', 'evidencias', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Lectura publica de evidencias" ON storage.objects;
CREATE POLICY "Lectura publica de evidencias"
ON storage.objects FOR SELECT
USING ( bucket_id = 'evidencias' );

DROP POLICY IF EXISTS "Usuarios logueados pueden subir evidencias" ON storage.objects;
CREATE POLICY "Usuarios logueados pueden subir evidencias"
ON storage.objects FOR INSERT
WITH CHECK ( 
  bucket_id = 'evidencias' 
  AND auth.role() = 'authenticated' 
);

DROP POLICY IF EXISTS "Usuarios pueden actualizar y borrar sus propias fotos" ON storage.objects;
CREATE POLICY "Usuarios pueden actualizar y borrar sus propias fotos"
ON storage.objects FOR ALL
USING ( 
  bucket_id = 'evidencias' 
  AND auth.uid() = owner 
)
WITH CHECK ( 
  bucket_id = 'evidencias' 
  AND auth.uid() = owner 
);

-- 10.2 BUCKET: AVATARS
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Lectura publica de avatars" ON storage.objects;
CREATE POLICY "Lectura publica de avatars"
ON storage.objects FOR SELECT
USING ( bucket_id = 'avatars' );

DROP POLICY IF EXISTS "Usuarios logueados pueden subir avatars" ON storage.objects;
CREATE POLICY "Usuarios logueados pueden subir avatars"
ON storage.objects FOR INSERT
WITH CHECK ( 
  bucket_id = 'avatars' 
  AND auth.role() = 'authenticated' 
);

DROP POLICY IF EXISTS "Usuarios pueden actualizar y borrar sus propios avatars" ON storage.objects;
CREATE POLICY "Usuarios pueden actualizar y borrar sus propios avatars"
ON storage.objects FOR ALL
USING ( 
  bucket_id = 'avatars' 
  AND auth.uid() = owner 
)
WITH CHECK ( 
  bucket_id = 'avatars' 
  AND auth.uid() = owner 
);

COMMIT; -- Aplicamos todos los cambios de forma segura