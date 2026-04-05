-- ==========================================================
-- SCRIPT: INSERTAR CATÁLOGO DE CARRERAS (EJEMPLO GENÉRICO)
-- ==========================================================

INSERT INTO public.cat_carreras (nombre)
VALUES 
    ('INGENIERÍA EN SISTEMAS COMPUTACIONALES'),
    ('INGENIERÍA INDUSTRIAL'),
    ('INGENIERÍA CIVIL'),
    ('LICENCIATURA EN ADMINISTRACIÓN'),
    ('LICENCIATURA EN DERECHO'),
    ('LICENCIATURA EN CONTADURÍA'),
    ('ARQUITECTURA'),
    ('MEDICINA GENERAL');

-- Verificamos que se hayan insertado correctamente
SELECT * FROM public.cat_carreras ORDER BY id ASC;

-- ==========================================================
-- SCRIPT: INSERTAR ZONAS Y AULAS (JERARQUÍA RECURSIVA GENÉRICA)
-- ==========================================================

DO $$
DECLARE
    v_parent_id int8;
BEGIN
    -- Limpiamos la tabla primero (Opcional, borra si ya tienes datos que quieres conservar)
    -- TRUNCATE TABLE public.cat_lugares CASCADE;

    -- ==========================================
    -- EDIFICIO A: Aulas Generales
    -- ==========================================
    INSERT INTO public.cat_lugares (nombre, tipo) VALUES ('Edificio A', 'Edificio') RETURNING id INTO v_parent_id;
    INSERT INTO public.cat_lugares (nombre, tipo, parent_id) VALUES 
        ('Aula A-101', 'Aula', v_parent_id),
        ('Aula A-102', 'Aula', v_parent_id),
        ('Aula A-103', 'Aula', v_parent_id),
        ('Aula A-201', 'Aula', v_parent_id),
        ('Aula A-202', 'Aula', v_parent_id);

    -- ==========================================
    -- EDIFICIO B: Laboratorios de Ciencias y Tecnología
    -- ==========================================
    INSERT INTO public.cat_lugares (nombre, tipo) VALUES ('Edificio B (Laboratorios)', 'Edificio') RETURNING id INTO v_parent_id;
    INSERT INTO public.cat_lugares (nombre, tipo, parent_id) VALUES 
        ('Laboratorio de Cómputo 1', 'Aula', v_parent_id),
        ('Laboratorio de Cómputo 2', 'Aula', v_parent_id),
        ('Laboratorio de Química', 'Aula', v_parent_id),
        ('Laboratorio de Física', 'Aula', v_parent_id),
        ('Bodega de Reactivos', 'Aula', v_parent_id);

    -- ==========================================
    -- EDIFICIO ADMINISTRATIVO
    -- ==========================================
    INSERT INTO public.cat_lugares (nombre, tipo) VALUES ('Edificio Administrativo', 'Edificio') RETURNING id INTO v_parent_id;
    INSERT INTO public.cat_lugares (nombre, tipo, parent_id) VALUES 
        ('Dirección General', 'Aula', v_parent_id),
        ('Servicios Escolares', 'Aula', v_parent_id),
        ('Recursos Humanos', 'Aula', v_parent_id),
        ('Sala de Juntas', 'Aula', v_parent_id),
        ('Enfermería', 'Aula', v_parent_id);

    -- ==========================================
    -- ÁREAS COMUNES
    -- ==========================================
    INSERT INTO public.cat_lugares (nombre, tipo) VALUES ('Zonas Comunes', 'Edificio') RETURNING id INTO v_parent_id;
    INSERT INTO public.cat_lugares (nombre, tipo, parent_id) VALUES 
        ('Biblioteca Universitaria', 'Aula', v_parent_id),
        ('Cafetería Principal', 'Aula', v_parent_id),
        ('Auditorio', 'Aula', v_parent_id),
        ('Centro de Copiado', 'Aula', v_parent_id);

    -- ==========================================
    -- ZONAS DEPORTIVAS
    -- ==========================================
    INSERT INTO public.cat_lugares (nombre, tipo) VALUES ('Complejo Deportivo', 'Edificio') RETURNING id INTO v_parent_id;
    INSERT INTO public.cat_lugares (nombre, tipo, parent_id) VALUES 
        ('Gimnasio Techado', 'Aula', v_parent_id),
        ('Cancha de Fútbol', 'Aula', v_parent_id),
        ('Canchas de Básquetbol', 'Aula', v_parent_id),
        ('Vestidores Generales', 'Aula', v_parent_id);

END $$;

SELECT 
    hijo.nombre AS aula, 
    padre.nombre AS edificio_perteneciente
FROM public.cat_lugares hijo
JOIN public.cat_lugares padre ON hijo.parent_id = padre.id
ORDER BY padre.id ASC;

-- ==========================================================
-- SCRIPT: INSERTAR CATEGORÍAS DE REPORTES
-- ==========================================================

INSERT INTO public.cat_categorias (nombre, icono, color)
VALUES 
    ('Mantenimiento', 'build', '#FF9800'),       -- Naranja
    ('Mobiliario', 'chair', '#795548'),          -- Café
    ('Tecnología', 'computer', '#2196F3'),       -- Azul
    ('Limpieza', 'cleaning_services', '#4CAF50'),-- Verde
    ('Seguridad', 'security', '#F44336');        -- Rojo

-- Verificamos que se insertaron correctamente
SELECT * FROM public.cat_categorias ORDER BY id ASC;