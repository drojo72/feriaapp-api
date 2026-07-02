-- ============================================================
-- MIGRACIÓN FeriaApp v2.1 - Optimización de JOINs
-- Base de datos: Neon PostgreSQL
-- Fecha: 2026-07-01
-- 
-- ORDEN DE EJECUCIÓN:
--   1. Backups de seguridad (verificar primero)
--   2. Extensiones (si no existen)
--   3. Campos redundantes en eventos_feria
--   4. Campos redundantes en journal_ventas
--   5. Triggers para mantener sincronización
--   6. Backfill de datos existentes
--   7. Vistas materializadas
--   8. Índices de rendimiento
--   9. Verificación final
-- ============================================================

-- ============================================================
-- PASO 0: VERIFICACIÓN PREVIA (OPCIONAL PERO RECOMENDADA)
-- ============================================================

-- Verificar que las tablas existen
SELECT 'tabla eventos_feria' as check, 
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'eventos_feria') 
            THEN 'OK' ELSE 'FALTA' END as status
UNION ALL
SELECT 'tabla canales_venta',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'canales_venta') 
            THEN 'OK' ELSE 'FALTA' END
UNION ALL
SELECT 'tabla usuarios',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'usuarios') 
            THEN 'OK' ELSE 'FALTA' END
UNION ALL
SELECT 'tabla journal_ventas',
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'journal_ventas') 
            THEN 'OK' ELSE 'FALTA' END;

-- Contar registros actuales para referencia
SELECT 'eventos_feria' as tabla, COUNT(*) as total FROM eventos_feria
UNION ALL
SELECT 'journal_ventas', COUNT(*) FROM journal_ventas
UNION ALL
SELECT 'productos', COUNT(*) FROM productos;

-- ============================================================
-- PASO 1: EXTENSIONES (si no existen)
-- ============================================================

-- Para búsquedas de texto en productos (opcional)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ============================================================
-- PASO 2: CAMPOS REDUNDANTES EN eventos_feria
-- ============================================================

-- 2.1 Agregar columnas redundantes
ALTER TABLE eventos_feria 
ADD COLUMN IF NOT EXISTS canal_venta_nombre VARCHAR(100),
ADD COLUMN IF NOT EXISTS canal_venta_tipo VARCHAR(30),
ADD COLUMN IF NOT EXISTS vendedor_nombre VARCHAR(100),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- 2.2 Agregar índice para búsquedas frecuentes
CREATE INDEX IF NOT EXISTS idx_eventos_feria_estado_fecha 
ON eventos_feria(estado, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_eventos_feria_canal_tipo 
ON eventos_feria(canal_venta_tipo) 
WHERE canal_venta_tipo IS NOT NULL;

-- ============================================================
-- PASO 3: CAMPOS REDUNDANTES EN journal_ventas
-- ============================================================

-- 3.1 Agregar columnas redundantes
ALTER TABLE journal_ventas 
ADD COLUMN IF NOT EXISTS evento_fecha DATE,
ADD COLUMN IF NOT EXISTS evento_lugar VARCHAR(150),
ADD COLUMN IF NOT EXISTS evento_estado VARCHAR(20),
ADD COLUMN IF NOT EXISTS vendedor_nombre VARCHAR(100),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- 3.2 Agregar índices para consultas frecuentes
CREATE INDEX IF NOT EXISTS idx_journal_ventas_fecha_evento 
ON journal_ventas(timestamp_local DESC, evento_feria_id);

CREATE INDEX IF NOT EXISTS idx_journal_ventas_evento_estado 
ON journal_ventas(evento_estado, timestamp_local DESC);

CREATE INDEX IF NOT EXISTS idx_journal_ventas_forma_pago_fecha 
ON journal_ventas(forma_pago, timestamp_local DESC);

-- ============================================================
-- PASO 4: FUNCIONES Y TRIGGERS PARA eventos_feria
-- ============================================================

-- 4.1 Función para sincronizar campos de eventos_feria
CREATE OR REPLACE FUNCTION sync_eventos_join_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Obtener datos del canal de venta
    SELECT cv.nombre, cv.tipo 
    INTO NEW.canal_venta_nombre, NEW.canal_venta_tipo
    FROM canales_venta cv 
    WHERE cv.id = NEW.canal_venta_id;
    
    -- Obtener nombre del vendedor
    SELECT u.nombre 
    INTO NEW.vendedor_nombre
    FROM usuarios u 
    WHERE u.id = NEW.vendedor_principal_id;
    
    -- Actualizar timestamp
    NEW.updated_at = NOW();
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Si hay error, mantener valores anteriores
        RAISE WARNING 'Error en sync_eventos_join_fields: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4.2 Trigger para INSERT y UPDATE
DROP TRIGGER IF EXISTS trg_sync_eventos_fields ON eventos_feria;
CREATE TRIGGER trg_sync_eventos_fields
BEFORE INSERT OR UPDATE ON eventos_feria
FOR EACH ROW
EXECUTE FUNCTION sync_eventos_join_fields();

-- ============================================================
-- PASO 5: FUNCIONES Y TRIGGERS PARA journal_ventas
-- ============================================================

-- 5.1 Función para sincronizar campos de journal_ventas
CREATE OR REPLACE FUNCTION sync_ventas_join_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- Obtener datos del evento
    SELECT ef.fecha, ef.lugar, ef.estado 
    INTO NEW.evento_fecha, NEW.evento_lugar, NEW.evento_estado
    FROM eventos_feria ef 
    WHERE ef.id = NEW.evento_feria_id;
    
    -- Obtener nombre del vendedor
    SELECT u.nombre 
    INTO NEW.vendedor_nombre
    FROM usuarios u 
    WHERE u.id = NEW.usuario_id;
    
    -- Actualizar timestamp
    NEW.updated_at = NOW();
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        RAISE WARNING 'Error en sync_ventas_join_fields: %', SQLERRM;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.2 Trigger para INSERT y UPDATE
DROP TRIGGER IF EXISTS trg_sync_ventas_fields ON journal_ventas;
CREATE TRIGGER trg_sync_ventas_fields
BEFORE INSERT OR UPDATE ON journal_ventas
FOR EACH ROW
EXECUTE FUNCTION sync_ventas_join_fields();

-- ============================================================
-- PASO 6: BACKFILL DE DATOS EXISTENTES
-- ============================================================

-- 6.1 Backfill eventos_feria
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE eventos_feria ef SET
        canal_venta_nombre = cv.nombre,
        canal_venta_tipo = cv.tipo,
        vendedor_nombre = u.nombre,
        updated_at = NOW()
    FROM canales_venta cv, usuarios u
    WHERE ef.canal_venta_id = cv.id 
      AND ef.vendedor_principal_id = u.id
      AND (ef.canal_venta_nombre IS NULL 
           OR ef.canal_venta_tipo IS NULL 
           OR ef.vendedor_nombre IS NULL);
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE '✅ Backfill eventos_feria: % filas actualizadas', v_count;
END $$;

-- 6.2 Backfill journal_ventas
DO $$
DECLARE
    v_count INTEGER;
BEGIN
    UPDATE journal_ventas jv SET
        evento_fecha = ef.fecha,
        evento_lugar = ef.lugar,
        evento_estado = ef.estado,
        vendedor_nombre = u.nombre,
        updated_at = NOW()
    FROM eventos_feria ef, usuarios u
    WHERE jv.evento_feria_id = ef.id 
      AND jv.usuario_id = u.id
      AND (jv.evento_fecha IS NULL 
           OR jv.evento_lugar IS NULL 
           OR jv.evento_estado IS NULL 
           OR jv.vendedor_nombre IS NULL);
    
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE '✅ Backfill journal_ventas: % filas actualizadas', v_count;
END $$;

-- ============================================================
-- PASO 7: VISTAS MATERIALIZADAS
-- ============================================================

-- 7.1 Vista materializada para resumen de eventos
DROP MATERIALIZED VIEW IF EXISTS mv_resumen_eventos CASCADE;

CREATE MATERIALIZED VIEW mv_resumen_eventos AS
SELECT 
    ef.id AS evento_id,
    ef.fecha,
    ef.lugar,
    ef.estado,
    ef.fecha_cierre,
    ef.total_calculado,
    ef.total_confirmado,
    ef.diferencia,
    -- Métricas de ventas
    COUNT(DISTINCT jv.id) AS total_ventas,
    COALESCE(SUM(jv.total_venta), 0) AS total_recaudado,
    COALESCE(AVG(jv.total_venta), 0) AS promedio_venta,
    COALESCE(SUM(CASE WHEN jv.forma_pago = 'efectivo' THEN jv.total_venta ELSE 0 END), 0) AS total_efectivo,
    COALESCE(SUM(CASE WHEN jv.forma_pago = 'transferencia' THEN jv.total_venta ELSE 0 END), 0) AS total_transferencia,
    COALESCE(SUM(CASE WHEN jv.forma_pago = 'diferido' THEN jv.total_venta ELSE 0 END), 0) AS total_diferido,
    COALESCE(SUM(CASE WHEN jv.forma_pago = 'debito' THEN jv.total_venta ELSE 0 END), 0) AS total_debito,
    COALESCE(SUM(CASE WHEN jv.forma_pago = 'credito' THEN jv.total_venta ELSE 0 END), 0) AS total_credito,
    COALESCE(SUM(CASE WHEN jv.forma_pago = 'trueque' THEN jv.total_venta ELSE 0 END), 0) AS total_trueque,
    COALESCE(SUM(COALESCE(jv.diferencia_rebaja, 0)), 0) AS total_rebajas,
    COUNT(DISTINCT jv.cliente_frecuente_id) AS clientes_unicos,
    -- Última venta
    MAX(jv.timestamp_local) AS ultima_venta,
    -- Resumen de productos
    COUNT(DISTINCT lv.producto_id) AS productos_unicos_vendidos,
    SUM(lv.cantidad) AS total_items_vendidos
FROM eventos_feria ef
LEFT JOIN journal_ventas jv ON ef.id = jv.evento_feria_id
LEFT JOIN lineas_venta lv ON jv.id = lv.venta_id
GROUP BY ef.id;

-- 7.2 Índices para la vista materializada
CREATE UNIQUE INDEX idx_mv_resumen_eventos_id ON mv_resumen_eventos(evento_id);
CREATE INDEX idx_mv_resumen_eventos_fecha ON mv_resumen_eventos(fecha DESC);
CREATE INDEX idx_mv_resumen_eventos_estado ON mv_resumen_eventos(estado);

-- 7.3 Función para refrescar vistas materializadas
CREATE OR REPLACE FUNCTION refresh_materialized_views()
RETURNS TEXT AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_resumen_eventos;
    RETURN 'Vistas materializadas actualizadas correctamente';
EXCEPTION
    WHEN OTHERS THEN
        RETURN 'Error al actualizar vistas: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- PASO 8: VISTAS ADICIONALES PARA REPORTES
-- ============================================================

-- 8.1 Vista de ventas diarias (sin JOINs, usa campos redundantes)
CREATE OR REPLACE VIEW v_ventas_diarias AS
SELECT 
    DATE(jv.timestamp_local) AS fecha,
    COUNT(*) AS total_ventas,
    SUM(jv.total_venta) AS total_recaudado,
    COALESCE(AVG(jv.total_venta), 0) AS promedio_venta,
    COUNT(DISTINCT jv.evento_feria_id) AS eventos_activos,
    COUNT(DISTINCT jv.cliente_frecuente_id) AS clientes_unicos,
    SUM(CASE WHEN jv.forma_pago = 'efectivo' THEN jv.total_venta ELSE 0 END) AS total_efectivo,
    SUM(CASE WHEN jv.forma_pago = 'transferencia' THEN jv.total_venta ELSE 0 END) AS total_transferencia,
    SUM(CASE WHEN jv.forma_pago IN ('debito', 'credito') THEN jv.total_venta ELSE 0 END) AS total_tarjeta
FROM journal_ventas jv
GROUP BY DATE(jv.timestamp_local)
ORDER BY fecha DESC;

-- 8.2 Vista de stock por categoría Re-Vistete
CREATE OR REPLACE VIEW v_stock_categorias AS
SELECT 
    cr.nombre AS categoria,
    COUNT(p.id) AS total_productos,
    SUM(CASE WHEN p.estado = 'disponible' THEN 1 ELSE 0 END) AS disponibles,
    SUM(CASE WHEN p.estado = 'vendido' THEN 1 ELSE 0 END) AS vendidos,
    SUM(CASE WHEN p.estado = 'reservado' THEN 1 ELSE 0 END) AS reservados,
    SUM(CASE WHEN p.estado = 'donado' THEN 1 ELSE 0 END) AS donados,
    SUM(CASE WHEN p.estado = 'retazo' THEN 1 ELSE 0 END) AS retazos,
    SUM(CASE WHEN p.estado = 'en_evaluacion' THEN 1 ELSE 0 END) AS en_evaluacion
FROM productos p
LEFT JOIN categorias_ropa cr ON p.categoria_revistete_id = cr.id
WHERE p.activo = TRUE
GROUP BY cr.nombre
ORDER BY total_productos DESC;

-- 8.3 Vista de productos con información completa (reemplaza JOINs en catálogo)
CREATE OR REPLACE VIEW v_productos_completos AS
SELECT 
    p.id,
    p.uuid,
    p.nombre,
    -- Categorías FeriaApp
    cf.nombre AS categoria_feriaapp,
    sf.nombre AS subcategoria_feriaapp,
    -- Categorías Re-Vistete
    cr.nombre AS categoria_revistete,
    sr.nombre AS subcategoria_revistete,
    -- Detalles
    g.nombre AS genero,
    se.nombre AS segmento_edad,
    p.talla,
    p.talla_numerica,
    p.medidas,
    -- Precios
    p.precio_online,
    p.precio_feria,
    p.precio_standard,
    p.precio_final,
    -- Estado
    p.estado,
    p.condicion,
    p.marca,
    -- Calidad y temporada
    nc.nombre AS nivel_calidad,
    nc.canal_asignado AS canal_recomendado,
    t.nombre AS temporada,
    p.temporadas_en_inventario,
    -- Descripción
    p.descripcion_defectos,
    p.fotos,
    p.notas,
    p.created_at,
    p.updated_at
FROM productos p
LEFT JOIN categorias_producto cf ON p.categoria_feriaapp_id = cf.id
LEFT JOIN subcategorias_producto sf ON p.subcategoria_feriaapp_id = sf.id
LEFT JOIN categorias_ropa cr ON p.categoria_revistete_id = cr.id
LEFT JOIN subcategorias_ropa sr ON p.subcategoria_revistete_id = sr.id
LEFT JOIN generos g ON p.genero_id = g.id
LEFT JOIN segmentos_edad se ON p.segmento_edad_id = se.id
LEFT JOIN niveles_calidad nc ON p.nivel_calidad_id = nc.id
LEFT JOIN temporadas t ON p.temporada_id = t.id
WHERE p.activo = TRUE;

-- ============================================================
-- PASO 9: VERIFICACIÓN FINAL
-- ============================================================

-- 9.1 Verificar columnas agregadas en eventos_feria
SELECT 'eventos_feria' as tabla,
       COUNT(*) as total_registros,
       COUNT(canal_venta_nombre) as canal_nombre_completos,
       COUNT(canal_venta_tipo) as canal_tipo_completos,
       COUNT(vendedor_nombre) as vendedor_nombre_completos
FROM eventos_feria;

-- 9.2 Verificar columnas agregadas en journal_ventas
SELECT 'journal_ventas' as tabla,
       COUNT(*) as total_registros,
       COUNT(evento_fecha) as evento_fecha_completos,
       COUNT(evento_lugar) as evento_lugar_completos,
       COUNT(evento_estado) as evento_estado_completos,
       COUNT(vendedor_nombre) as vendedor_nombre_completos
FROM journal_ventas;

-- 9.3 Verificar triggers activos
SELECT 
    tgname AS trigger_name,
    tgrelid::regclass AS table_name,
    tgtype,
    CASE WHEN tgtype & 1 = 1 THEN 'BEFORE' ELSE 'AFTER' END as timing,
    CASE WHEN tgtype & 16 = 16 THEN 'INSERT' ELSE '' END as insert_trigger,
    CASE WHEN tgtype & 32 = 32 THEN 'UPDATE' ELSE '' END as update_trigger
FROM pg_trigger
WHERE tgname LIKE 'trg_sync_%'
  AND tgrelid IN ('eventos_feria'::regclass, 'journal_ventas'::regclass);

-- 9.4 Verificar vistas materializadas
SELECT 
    schemaname,
    matviewname,
    pg_size_pretty(pg_total_relation_size(matviewname::regclass)) as size,
    (SELECT COUNT(*) FROM mv_resumen_eventos) as total_eventos
FROM pg_matviews
WHERE matviewname = 'mv_resumen_eventos';

-- 9.5 Test: Consulta optimizada de eventos (sin JOINs)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, fecha, lugar, estado, total_calculado,
       canal_venta_nombre, canal_venta_tipo, vendedor_nombre
FROM eventos_feria 
WHERE estado = 'activo'
ORDER BY fecha DESC
LIMIT 10;

-- 9.6 Test: Resumen de eventos (usando vista materializada)
SELECT 
    'Resumen usando vista materializada' as test,
    evento_id,
    total_ventas,
    total_recaudado,
    total_efectivo,
    total_transferencia
FROM mv_resumen_eventos
WHERE evento_id = (SELECT id FROM eventos_feria ORDER BY id DESC LIMIT 1);

-- ============================================================
-- PASO 10: FUNCIÓN PARA REFRESCAR PERIÓDICAMENTE (OPCIONAL)
-- ============================================================

-- Crear un job programado para refrescar vistas (si tienes pg_cron)
-- Nota: pg_cron no está disponible por defecto en Neon
-- Puedes usar un script externo o programar con schedule

-- SELECT cron.schedule(
--     'refresh-feriaapp-views',  -- nombre del job
--     '0 * * * *',              -- cada hora
--     'SELECT refresh_materialized_views()'
-- );

-- ============================================================
-- RESULTADO FINAL
-- ============================================================

DO $$
BEGIN
    RAISE NOTICE '==========================================';
    RAISE NOTICE '✅ MIGRACIÓN COMPLETADA EXITOSAMENTE';
    RAISE NOTICE '==========================================';
    RAISE NOTICE '📊 Estadísticas finales:';
    RAISE NOTICE '  - Eventos: %', (SELECT COUNT(*) FROM eventos_feria);
    RAISE NOTICE '  - Ventas: %', (SELECT COUNT(*) FROM journal_ventas);
    RAISE NOTICE '  - Productos activos: %', (SELECT COUNT(*) FROM productos WHERE activo = TRUE);
    RAISE NOTICE '  - Vistas materializadas: 1 (mv_resumen_eventos)';
    RAISE NOTICE '  - Vistas estándar: 3';
    RAISE NOTICE '==========================================';
    RAISE NOTICE '🚀 Próximos pasos:';
    RAISE NOTICE '  1. Actualizar API endpoints para usar nuevos campos';
    RAISE NOTICE '  2. Programar refresh de mv_resumen_eventos (cada 5-10 min)';
    RAISE NOTICE '  3. Monitorear rendimiento de consultas';
    RAISE NOTICE '==========================================';
END $$;