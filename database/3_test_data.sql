WITH reportes_insertados AS (
  INSERT INTO public.reportes (usuario_id, categoria_id, titulo, descripcion, evidencia_url)
  SELECT 
    -- Selecciona un ID de usuario al azar de los que existen
    (SELECT id FROM public.perfiles ORDER BY random() LIMIT 1), 
    
    floor(random() * 5 + 1)::bigint, 
    'Dummy test ' || i, 
    'Rellenando espacio en la pantalla. Fila número ' || i,
    'https://picsum.photos/id/' || i || '/1024/1024' 
  FROM generate_series(1, 1000) AS i
  RETURNING id
)
-- Paso 2: Usamos esos IDs atrapados para asignarles un lugar aleatorio
INSERT INTO public.reporte_ubicaciones (reporte_id, lugar_id, detalles_extra)
SELECT 
  id,
  -- 🛑 EL NUEVO TRUCO: Selecciona un ID de lugar al azar de los que existen
  (SELECT id FROM public.cat_lugares ORDER BY random() LIMIT 1), 
  
  'Ubicación generada para pruebas de estrés de memoria'
FROM reportes_insertados;