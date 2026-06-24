-- ============================================
-- FERIAAPP v2.1: MIGRACIÓN DATOS HISTÓRICOS + VISTAS DETALLE
-- 
-- NOTAS IMPORTANTES:
-- - journal_ventas en MySQL v1 tenía notas con resumen (ej: "2 poleras + 1 pantalón = $8000")
-- - No había lineas_venta desagregadas (venta única por evento, notas como detalle)
-- - Las transacciones por compra se registraban en journal_egresos (compra_reventa/compra_vecinos)
-- - Reclasificación automática para productos sin talla (alimentos, artesanía, libros, etc.)
-- - Productos con talla (ropa) quedan para revisión manual
-- ============================================

-- ============================================
-- 1. RECLASIFICACIÓN AUTOMÁTICA: PRODUCTOS SIN TALLA
-- ============================================

-- Alimentos Orgánicos / Comerciales → sin categoría Re-Vistete (son Granja Toquí)
UPDATE productos SET
    categoria_revistete_id = NULL,
    genero_id = NULL,
    segmento_edad_id = NULL,
    nivel_calidad_id = (SELECT id FROM niveles_calidad WHERE codigo = 'sin_marca'),
    condicion = 'sin_marca',
    estado = 'disponible',
    evaluado_por_id = 1,
    fecha_evaluacion = NOW(),
    updated_at = NOW()
WHERE categoria_feriaapp_id IN (1, 2)  -- Alimentos
  AND categoria_revistete_id IS NULL;

-- Artesanía → hogar_cultura / artesania_hogar
UPDATE productos SET
    categoria_revistete_id = (SELECT id FROM categorias_ropa WHERE codigo = 'artesania_hogar'),
    genero_id = (SELECT id FROM generos WHERE codigo = 'unisex'),
    segmento_edad_id = (SELECT id FROM segmentos_edad WHERE codigo = 'adulto'),
    nivel_calidad_id = (SELECT id FROM niveles_calidad WHERE codigo = 'sin_marca'),
    condicion = 'sin_marca',
    temporada_id = (SELECT id FROM temporadas WHERE codigo = 'atemporal'),
    estado = 'disponible',
    evaluado_por_id = 1,
    fecha_evaluacion = NOW(),
    updated_at = NOW()
WHERE categoria_feriaapp_id = 4  -- Artesanía
  AND categoria_revistete_id IS NULL;

-- Antigüedades → hogar_cultura / decoracion
UPDATE productos SET
    categoria_revistete_id = (SELECT id FROM categorias_ropa WHERE codigo = 'decoracion'),
    genero_id = (SELECT id FROM generos WHERE codigo = 'unisex'),
    segmento_edad_id = (SELECT id FROM segmentos_edad WHERE codigo = 'adulto'),
    nivel_calidad_id = (SELECT id FROM niveles_calidad WHERE codigo = 'sin_marca'),
    condicion = 'sin_marca',
    temporada_id = (SELECT id FROM temporadas WHERE codigo = 'atemporal'),
    estado = 'disponible',
    evaluado_por_id = 1,
    fecha_evaluacion = NOW(),
    updated_at = NOW()
WHERE categoria_feriaapp_id = 5  -- Antigüedades
  AND categoria_revistete_id IS NULL;

-- Libros, CDs, Vinilos, Casettes, Revistas → hogar_cultura
UPDATE productos SET
    categoria_revistete_id = CASE
        WHEN nombre ILIKE '%novela%' OR nombre ILIKE '%diccionario%' OR nombre ILIKE '%filosof%' 
             OR nombre ILIKE '%historia%' OR nombre ILIKE '%ciencia%' THEN 
            (SELECT id FROM categorias_ropa WHERE codigo = 'libros')
        WHEN nombre ILIKE '%cd%' OR nombre ILIKE '%vinilo%' OR nombre ILIKE '%casette%' 
             OR nombre ILIKE '%revista%' THEN 
            (SELECT id FROM categorias_ropa WHERE codigo = 'revistas')
        ELSE (SELECT id FROM categorias_ropa WHERE codigo = 'libros')
    END,
    genero_id = (SELECT id FROM generos WHERE codigo = 'unisex'),
    segmento_edad_id = (SELECT id FROM segmentos_edad WHERE codigo = 'adulto'),
    nivel_calidad_id = (SELECT id FROM niveles_calidad WHERE codigo = 'sin_marca'),
    condicion = 'sin_marca',
    temporada_id = (SELECT id FROM temporadas WHERE codigo = 'atemporal'),
    estado = 'disponible',
    evaluado_por_id = 1,
    fecha_evaluacion = NOW(),
    updated_at = NOW()
WHERE categoria_feriaapp_id = 6  -- Otros (Libros, CDs, etc.)
  AND categoria_revistete_id IS NULL;

-- Juguetes reciclados → juguetes
UPDATE productos SET
    categoria_revistete_id = CASE
        WHEN nombre ILIKE '%coleccionable%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'munecos_accion')
        WHEN nombre ILIKE '%beb%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'juguetes_madera')
        ELSE (SELECT id FROM categorias_ropa WHERE codigo = 'otros_juguetes')
    END,
    genero_id = (SELECT id FROM generos WHERE codigo = 'unisex'),
    segmento_edad_id = CASE
        WHEN nombre ILIKE '%beb%' THEN (SELECT id FROM segmentos_edad WHERE codigo = 'bebe')
        ELSE (SELECT id FROM segmentos_edad WHERE codigo = 'nino')
    END,
    nivel_calidad_id = (SELECT id FROM niveles_calidad WHERE codigo = 'donacion'),
    condicion = 'donacion',
    temporada_id = (SELECT id FROM temporadas WHERE codigo = 'atemporal'),
    estado = 'disponible',
    evaluado_por_id = 1,
    fecha_evaluacion = NOW(),
    updated_at = NOW()
WHERE categoria_feriaapp_id = 7  -- Juguetes
  AND categoria_revistete_id IS NULL;

-- Aros y Pins de Artesanía → joyeria_bijouteria
UPDATE productos SET
    categoria_revistete_id = CASE
        WHEN nombre ILIKE '%aro%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'aros')
        WHEN nombre ILIKE '%pin%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'prendedores')
        ELSE (SELECT id FROM categorias_ropa WHERE codigo = 'bijouteria_artesana')
    END,
    genero_id = (SELECT id FROM generos WHERE codigo = 'unisex'),
    segmento_edad_id = (SELECT id FROM segmentos_edad WHERE codigo = 'adulto'),
    nivel_calidad_id = (SELECT id FROM niveles_calidad WHERE codigo = 'sin_marca'),
    condicion = 'sin_marca',
    temporada_id = (SELECT id FROM temporadas WHERE codigo = 'atemporal'),
    estado = 'disponible',
    evaluado_por_id = 1,
    fecha_evaluacion = NOW(),
    updated_at = NOW()
WHERE categoria_feriaapp_id = 4  -- Artesanía
  AND (nombre ILIKE '%aro%' OR nombre ILIKE '%pin%')
  AND categoria_revistete_id IS NULL;

-- ============================================
-- 2. RECLASIFICACIÓN SEMI-AUTOMÁTICA: ROPA (con sugerencias)
-- ============================================

-- Ropa Mujer (subcat 8) - sugerir categorías basadas en nombre
UPDATE productos SET
    categoria_revistete_id = CASE
        WHEN nombre ILIKE '%blusa%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'blusas')
        WHEN nombre ILIKE '%polera%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'polera_mc')
        WHEN nombre ILIKE '%pantalón%' OR nombre ILIKE '%pantalon%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'pantalones')
        WHEN nombre ILIKE '%chaleco%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'chalecos')
        WHEN nombre ILIKE '%poleron%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'buzos')
        WHEN nombre ILIKE '%chaqueta%' OR nombre ILIKE '%parca%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'chaquetas')
        WHEN nombre ILIKE '%deportiva%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'polera_mc')
        WHEN nombre ILIKE '%chal%' OR nombre ILIKE '%poncho%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'ponchos')
        WHEN nombre ILIKE '%bufanda%' OR nombre ILIKE '%pañuelo%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'bufandas')
        WHEN nombre ILIKE '%interior%' OR nombre ILIKE '%calzón%' OR nombre ILIKE '%sostén%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'ropa_interior')
        WHEN nombre ILIKE '%zapato%' OR nombre ILIKE '%zapatilla%' OR nombre ILIKE '%bota%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'zapatillas')
        ELSE NULL  -- dejar NULL para revisión manual
    END,
    genero_id = (SELECT id FROM generos WHERE codigo = 'mujer'),
    segmento_edad_id = (SELECT id FROM segmentos_edad WHERE codigo = 'adulto'),
    nivel_calidad_id = CASE
        WHEN categoria_revistete_id IS NOT NULL THEN (SELECT id FROM niveles_calidad WHERE codigo = 'sin_marca')
        ELSE NULL
    END,
    condicion = CASE
        WHEN categoria_revistete_id IS NOT NULL THEN 'sin_marca'
        ELSE NULL
    END,
    temporada_id = CASE
        WHEN categoria_revistete_id IS NOT NULL THEN (SELECT id FROM temporadas WHERE codigo = 'atemporal')
        ELSE NULL
    END,
    estado = CASE
        WHEN categoria_revistete_id IS NOT NULL THEN 'disponible'
        ELSE 'en_evaluacion'
    END,
    evaluado_por_id = CASE WHEN categoria_revistete_id IS NOT NULL THEN 1 ELSE NULL END,
    fecha_evaluacion = CASE WHEN categoria_revistete_id IS NOT NULL THEN NOW() ELSE NULL END,
    updated_at = NOW()
WHERE categoria_feriaapp_id = 3  -- Moda
  AND subcategoria_feriaapp_id = 8  -- Mujer
  AND categoria_revistete_id IS NULL;

-- Ropa Hombre (subcat 9) - sugerir categorías
UPDATE productos SET
    categoria_revistete_id = CASE
        WHEN nombre ILIKE '%camisa%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'camisas')
        WHEN nombre ILIKE '%polera%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'polera_mc')
        WHEN nombre ILIKE '%pantalón%' OR nombre ILIKE '%pantalon%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'pantalones')
        WHEN nombre ILIKE '%chaleco%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'chalecos')
        WHEN nombre ILIKE '%poleron%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'buzos')
        WHEN nombre ILIKE '%chaqueta%' OR nombre ILIKE '%parca%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'chaquetas')
        WHEN nombre ILIKE '%deportiva%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'polera_mc')
        WHEN nombre ILIKE '%interior%' OR nombre ILIKE '%calzoncillo%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'ropa_interior')
        WHEN nombre ILIKE '%zapato%' OR nombre ILIKE '%zapatilla%' OR nombre ILIKE '%bota%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'zapatillas')
        ELSE NULL
    END,
    genero_id = (SELECT id FROM generos WHERE codigo = 'hombre'),
    segmento_edad_id = (SELECT id FROM segmentos_edad WHERE codigo = 'adulto'),
    nivel_calidad_id = CASE WHEN categoria_revistete_id IS NOT NULL THEN (SELECT id FROM niveles_calidad WHERE codigo = 'sin_marca') ELSE NULL END,
    condicion = CASE WHEN categoria_revistete_id IS NOT NULL THEN 'sin_marca' ELSE NULL END,
    temporada_id = CASE WHEN categoria_revistete_id IS NOT NULL THEN (SELECT id FROM temporadas WHERE codigo = 'atemporal') ELSE NULL END,
    estado = CASE WHEN categoria_revistete_id IS NOT NULL THEN 'disponible' ELSE 'en_evaluacion' END,
    evaluado_por_id = CASE WHEN categoria_revistete_id IS NOT NULL THEN 1 ELSE NULL END,
    fecha_evaluacion = CASE WHEN categoria_revistete_id IS NOT NULL THEN NOW() ELSE NULL END,
    updated_at = NOW()
WHERE categoria_feriaapp_id = 3
  AND subcategoria_feriaapp_id = 9  -- Hombre
  AND categoria_revistete_id IS NULL;

-- Ropa Niños (subcat 10)
UPDATE productos SET
    categoria_revistete_id = CASE
        WHEN nombre ILIKE '%zapato%' OR nombre ILIKE '%zapatilla%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'zapatillas')
        WHEN nombre ILIKE '%deportiva%' THEN (SELECT id FROM categorias_ropa WHERE codigo = 'polera_mc')
        ELSE (SELECT id FROM categorias_ropa WHERE codigo = 'polera_mc')  -- default niño
    END,
    genero_id = (SELECT id FROM generos WHERE codigo = 'unisex'),
    segmento_edad_id = (SELECT id FROM segmentos_edad WHERE codigo = 'nino'),
    nivel_calidad_id = (SELECT id FROM niveles_calidad WHERE codigo = 'donacion'),
    condicion = 'donacion',
    temporada_id = (SELECT id FROM temporadas WHERE codigo = 'atemporal'),
    estado = 'disponible',
    evaluado_por_id = 1,
    fecha_evaluacion = NOW(),
    updated_at = NOW()
WHERE categoria_feriaapp_id = 3
  AND subcategoria_feriaapp_id = 10  -- Niños
  AND categoria_revistete_id IS NULL;

-- ============================================
-- 3. REPORTE POST-RECLASIFICACIÓN
-- ============================================

SELECT '=== RESULTADO RECLASIFICACIÓN AUTOMÁTICA ===' as seccion;

-- Productos reclasificados automáticamente
SELECT 
    'Reclasificados automáticamente' as estado,
    COUNT(*) as cantidad
FROM productos
WHERE categoria_revistete_id IS NOT NULL;

-- Productos pendientes de revisión manual (sin talla asignada)
SELECT 
    'Pendientes revisión manual' as estado,
    COUNT(*) as cantidad
FROM productos
WHERE categoria_revistete_id IS NULL;

-- Detalle de pendientes
SELECT 
    p.id,
    p.nombre,
    cf.nombre as categoria_feriaapp,
    sf.nombre as subcategoria_feriaapp,
    'Revisar: asignar talla, medidas, calidad exacta' as accion_sugerida
FROM productos p
LEFT JOIN categorias_producto cf ON p.categoria_feriaapp_id = cf.id
LEFT JOIN subcategorias_producto sf ON p.subcategoria_feriaapp_id = sf.id
WHERE p.categoria_revistete_id IS NULL
ORDER BY p.categoria_feriaapp_id, p.id;

-- ============================================
-- 4. VISTAS DETALLE PARA CORRECCIONES FINAS
-- ============================================

-- Vista: productos con campos incompletos para corrección
CREATE OR REPLACE VIEW v_productos_pendientes_correccion AS
SELECT 
    p.id,
    p.nombre,
    p.etiqueta_id,
    p.codigo_barras,
    cf.nombre as categoria_feriaapp,
    sf.nombre as subcategoria_feriaapp,
    cr.nombre as categoria_revistete,
    sr.nombre as subcategoria_revistete,
    g.nombre as genero,
    se.nombre as segmento_edad,
    nc.nombre as nivel_calidad,
    t.nombre as temporada,
    p.talla,
    p.talla_numerica,
    p.medidas,
    p.precio_online,
    p.precio_feria,
    p.precio_standard,
    p.precio_final,
    p.condicion,
    p.estado,
    p.temporadas_en_inventario,
    p.descripcion_defectos,
    p.marca,
    p.fotos,
    p.notas,
    -- Flags de completitud
    CASE WHEN p.talla IS NULL THEN '❌' ELSE '✅' END as tiene_talla,
    CASE WHEN p.medidas IS NULL THEN '❌' ELSE '✅' END as tiene_medidas,
    CASE WHEN p.precio_online IS NULL THEN '❌' ELSE '✅' END as tiene_precio_online,
    CASE WHEN p.precio_feria IS NULL THEN '❌' ELSE '✅' END as tiene_precio_feria,
    CASE WHEN p.marca IS NULL THEN '❌' ELSE '✅' END as tiene_marca,
    CASE WHEN p.fotos = '[]' OR p.fotos IS NULL THEN '❌' ELSE '✅' END as tiene_fotos,
    CASE WHEN p.etiqueta_id IS NULL THEN '❌' ELSE '✅' END as tiene_etiqueta,
    -- Score de completitud (0-7)
    (CASE WHEN p.talla IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN p.medidas IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN p.precio_online IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN p.precio_feria IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN p.marca IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN p.fotos != '[]' AND p.fotos IS NOT NULL THEN 1 ELSE 0 END +
     CASE WHEN p.etiqueta_id IS NOT NULL THEN 1 ELSE 0 END) as score_completitud
FROM productos p
LEFT JOIN categorias_producto cf ON p.categoria_feriaapp_id = cf.id
LEFT JOIN subcategorias_producto sf ON p.subcategoria_feriaapp_id = sf.id
LEFT JOIN categorias_ropa cr ON p.categoria_revistete_id = cr.id
LEFT JOIN subcategorias_ropa sr ON p.subcategoria_revistete_id = sr.id
LEFT JOIN generos g ON p.genero_id = g.id
LEFT JOIN segmentos_edad se ON p.segmento_edad_id = se.id
LEFT JOIN niveles_calidad nc ON p.nivel_calidad_id = nc.id
LEFT JOIN temporadas t ON p.temporada_id = t.id
WHERE p.activo = TRUE
ORDER BY score_completitud ASC, p.id;

-- Vista: ventas con detalle completo (histórico + notas parseadas)
CREATE OR REPLACE VIEW v_ventas_detalle AS
SELECT 
    jv.id,
    jv.uuid,
    jv.timestamp_local,
    jv.timestamp_sync,
    ef.fecha as fecha_evento,
    ef.lugar,
    cv.nombre as canal_venta,
    u.nombre as vendedor,
    d.nombre as dispositivo,
    jv.perfil_cliente,
    cf.nombre as cliente_frecuente,
    jv.forma_pago,
    jv.estado_pago,
    jv.total_venta,
    jv.precio_standard_total,
    jv.precio_final_total,
    jv.diferencia_rebaja,
    jv.porcentaje_rebaja,
    jv.tipo_rebaja,
    jv.motivo_rebaja,
    au.nombre as aprobado_por,
    jv.venta_directa_sin_bodega,
    jv.garantia_devolucion,
    jv.sync_estado,
    jv.notas,
    -- Parseo simple de notas: buscar montos y cantidades
    (SELECT COUNT(*) FROM lineas_venta lv WHERE lv.venta_id = jv.id) as cantidad_lineas,
    jv.created_at
FROM journal_ventas jv
LEFT JOIN eventos_feria ef ON jv.evento_feria_id = ef.id
LEFT JOIN canales_venta cv ON ef.canal_venta_id = cv.id
LEFT JOIN usuarios u ON jv.usuario_id = u.id
LEFT JOIN dispositivos d ON jv.dispositivo_id = d.id
LEFT JOIN clientes_frecuentes cf ON jv.cliente_frecuente_id = cf.id
LEFT JOIN usuarios au ON jv.aprobado_por_id = au.id
ORDER BY jv.timestamp_local DESC;

-- Vista: líneas de venta con producto completo
CREATE OR REPLACE VIEW v_lineas_venta_detalle AS
SELECT 
    lv.id,
    lv.venta_id,
    jv.timestamp_local as fecha_venta,
    ef.fecha as fecha_evento,
    cv.nombre as canal,
    p.nombre as producto,
    p.etiqueta_id,
    p.codigo_barras,
    cr.nombre as categoria_revistete,
    g.nombre as genero,
    se.nombre as segmento_edad,
    lv.cantidad,
    lv.precio_unitario_standard,
    lv.precio_unitario_final,
    lv.subtotal,
    -- Diferencia por línea
    COALESCE(lv.precio_unitario_final, 0) - COALESCE(lv.precio_unitario_standard, lv.precio_unitario_final, 0) as diferencia_linea,
    lv.notas,
    vr.tipo_rebaja as tipo_rebaja_linea,
    vr.porcentaje_rebaja as pct_rebaja_linea,
    vr.nota_rebaja
FROM lineas_venta lv
LEFT JOIN journal_ventas jv ON lv.venta_id = jv.id
LEFT JOIN eventos_feria ef ON jv.evento_feria_id = ef.id
LEFT JOIN canales_venta cv ON ef.canal_venta_id = cv.id
LEFT JOIN productos p ON lv.producto_id = p.id
LEFT JOIN categorias_ropa cr ON p.categoria_revistete_id = cr.id
LEFT JOIN generos g ON p.genero_id = g.id
LEFT JOIN segmentos_edad se ON p.segmento_edad_id = se.id
LEFT JOIN venta_rebajas vr ON vr.linea_venta_id = lv.id
ORDER BY jv.timestamp_local DESC, lv.id;

-- Vista: egresos/insumos con detalle completo
CREATE OR REPLACE VIEW v_egresos_detalle AS
SELECT 
    je.id,
    je.fecha,
    u.nombre as usuario,
    d.nombre as dispositivo,
    je.tipo,
    je.proveedor,
    p.nombre as producto,
    je.descripcion,
    je.cantidad,
    je.precio_unitario,
    je.total,
    je.forma_pago,
    je.sync_estado,
    je.timestamp_local,
    je.timestamp_sync,
    je.notas
FROM journal_egresos je
LEFT JOIN usuarios u ON je.usuario_id = u.id
LEFT JOIN dispositivos d ON je.dispositivo_id = d.id
LEFT JOIN productos p ON je.producto_id = p.id
ORDER BY je.fecha DESC;

CREATE OR REPLACE VIEW v_insumos_detalle AS
SELECT 
    ji.id,
    ji.fecha,
    u.nombre as usuario,
    d.nombre as dispositivo,
    ji.tipo,
    ji.descripcion,
    ji.monto,
    ji.forma_pago,
    ji.sync_estado,
    ji.timestamp_local,
    ji.timestamp_sync,
    ji.notas
FROM journal_insumos ji
LEFT JOIN usuarios u ON ji.usuario_id = u.id
LEFT JOIN dispositivos d ON ji.dispositivo_id = d.id
ORDER BY ji.fecha DESC;

-- Vista: eventos con resumen + detalle de ventas
CREATE OR REPLACE VIEW v_eventos_resumen_detalle AS
SELECT 
    ef.id,
    ef.fecha,
    ef.lugar,
    cv.nombre as canal_venta,
    cv.tipo as tipo_canal,
    u.nombre as vendedor_principal,
    ef.estado,
    ef.total_calculado,
    ef.total_confirmado,
    ef.diferencia,
    ru.nombre as revisado_por,
    ef.fecha_revision,
    ef.fecha_cierre,
    -- Métricas de ventas
    COUNT(jv.id) as total_ventas,
    SUM(jv.total_venta) as suma_ventas,
    SUM(CASE WHEN jv.forma_pago = 'efectivo' THEN jv.total_venta ELSE 0 END) as ventas_efectivo,
    SUM(CASE WHEN jv.forma_pago = 'transferencia' THEN jv.total_venta ELSE 0 END) as ventas_transferencia,
    SUM(CASE WHEN jv.forma_pago = 'diferido' THEN jv.total_venta ELSE 0 END) as ventas_diferido,
    SUM(CASE WHEN jv.venta_directa_sin_bodega THEN jv.total_venta ELSE 0 END) as ventas_directas,
    SUM(COALESCE(jv.diferencia_rebaja, 0)) as total_rebajas,
    AVG(COALESCE(jv.porcentaje_rebaja, 0)) as rebaja_promedio_pct,
    -- Métricas de productos
    COUNT(DISTINCT lv.producto_id) as productos_vendidos_distintos,
    SUM(lv.cantidad) as unidades_vendidas,
    ef.notas,
    ef.created_at
FROM eventos_feria ef
LEFT JOIN canales_venta cv ON ef.canal_venta_id = cv.id
LEFT JOIN usuarios u ON ef.vendedor_principal_id = u.id
LEFT JOIN usuarios ru ON ef.revisado_por_id = ru.id
LEFT JOIN journal_ventas jv ON ef.id = jv.evento_feria_id
LEFT JOIN lineas_venta lv ON jv.id = lv.venta_id
GROUP BY ef.id, ef.fecha, ef.lugar, cv.nombre, cv.tipo, u.nombre, 
         ef.estado, ef.total_calculado, ef.total_confirmado, ef.diferencia,
         ru.nombre, ef.fecha_revision, ef.fecha_cierre, ef.notas, ef.created_at
ORDER BY ef.fecha DESC;

-- ============================================
-- 5. FUNCIÓN: PARSEAR NOTAS DE VENTA V1 (extractor de items)
-- ============================================

CREATE OR REPLACE FUNCTION parsear_notas_venta_v1(p_nota TEXT)
RETURNS TABLE(item TEXT, cantidad INTEGER, precio_unitario INTEGER, subtotal INTEGER) AS $$
DECLARE
    v_linea TEXT;
    v_items TEXT[];
BEGIN
    -- Divide la nota por saltos de línea o comas
    v_items := string_to_array(p_nota, E'\n');

    FOREACH v_linea IN ARRAY v_items
    LOOP
        -- Patrón: "X item = $Y" o "X item a $Y" o "item $Y"
        -- Extrae cantidad, nombre y precio usando regex
        item := trim(v_linea);
        cantidad := COALESCE((regexp_match(v_linea, '(\d+)\s*(?:x|X|por)'))[1]::INTEGER, 1);
        precio_unitario := COALESCE(
            (regexp_match(v_linea, '\$?\s*(\d+(?:\.\d+)?)'))[1]::INTEGER,
            0
        );
        subtotal := cantidad * precio_unitario;

        IF item IS NOT NULL AND length(item) > 0 THEN
            RETURN NEXT;
        END IF;
    END LOOP;
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 6. TRIGGER: Auto-crear líneas de venta desde notas (para migración histórica)
-- ============================================

CREATE OR REPLACE FUNCTION auto_lineas_desde_notas()
RETURNS TRIGGER AS $$
DECLARE
    v_item RECORD;
    v_producto_id INTEGER;
BEGIN
    -- Solo para ventas históricas migradas (sin líneas existentes)
    IF NOT EXISTS (SELECT 1 FROM lineas_venta WHERE venta_id = NEW.id) AND NEW.notas IS NOT NULL THEN
        FOR v_item IN SELECT * FROM parsear_notas_venta_v1(NEW.notas)
        LOOP
            -- Buscar producto por nombre aproximado
            SELECT id INTO v_producto_id
            FROM productos
            WHERE nombre ILIKE '%' || v_item.item || '%'
            LIMIT 1;

            INSERT INTO lineas_venta (
                venta_id, producto_id, cantidad,
                precio_unitario_standard, precio_unitario_final, subtotal, notas
            ) VALUES (
                NEW.id, v_producto_id, v_item.cantidad,
                v_item.precio_unitario, v_item.precio_unitario, v_item.subtotal,
                'Auto-generado desde notas v1: ' || v_item.item
            );
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Nota: Este trigger se activa al insertar ventas históricas
-- DROP TRIGGER IF EXISTS trg_auto_lineas_notas ON journal_ventas;
-- CREATE TRIGGER trg_auto_lineas_notas
-- AFTER INSERT ON journal_ventas
-- FOR EACH ROW EXECUTE FUNCTION auto_lineas_desde_notas();

-- ============================================
-- 7. VERIFICACIÓN FINAL
-- ============================================

SELECT '=== VISTAS CREADAS ===' as seccion;
SELECT table_name as vista
FROM information_schema.views
WHERE table_schema = 'public'
AND table_name IN (
    'v_productos_disponibles',
    'v_productos_pendientes_correccion',
    'v_rebajas_por_evento',
    'v_ventas_detalle',
    'v_lineas_venta_detalle',
    'v_egresos_detalle',
    'v_insumos_detalle',
    'v_eventos_resumen_detalle'
);

SELECT '=== FUNCIONES CREADAS ===' as seccion;
SELECT routine_name as funcion
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name IN (
    'calcular_precio_sugerido',
    'mover_prenda_canal',
    'update_productos_updated_at',
    'incrementar_temporada_inventario',
    'validar_cierre_evento',
    'parsear_notas_venta_v1',
    'auto_lineas_desde_notas'
);

SELECT '=== ESTADO PRODUCTOS POST-RECLASIFICACIÓN ===' as seccion;
SELECT 
    cr.nombre as categoria_revistete,
    g.nombre as genero,
    se.nombre as segmento_edad,
    nc.nombre as nivel_calidad,
    COUNT(*) as cantidad
FROM productos p
LEFT JOIN categorias_ropa cr ON p.categoria_revistete_id = cr.id
LEFT JOIN generos g ON p.genero_id = g.id
LEFT JOIN segmentos_edad se ON p.segmento_edad_id = se.id
LEFT JOIN niveles_calidad nc ON p.nivel_calidad_id = nc.id
WHERE p.activo = TRUE
GROUP BY cr.nombre, g.nombre, se.nombre, nc.nombre
ORDER BY cr.nombre, g.nombre;
