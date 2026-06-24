-- ============================================
-- MIGRACIÓN: FeriaApp v1 → v2.1 (Re-Vistete integrado)
-- No recrea tablas existentes, solo ALTER + CREATE nuevas
-- Eventos quedan ABIERTOS para revisión manual
-- ============================================

-- ============================================
-- 1. NUEVAS TABLAS DE CATÁLOGO (no existen)
-- ============================================

CREATE TABLE IF NOT EXISTS segmentos_edad (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(20) UNIQUE NOT NULL,
    nombre          VARCHAR(50) NOT NULL,
    rango_anios     VARCHAR(30),
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS generos (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(20) UNIQUE NOT NULL,
    nombre          VARCHAR(50) NOT NULL,
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS categorias_ropa (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(30) UNIQUE NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    grupo           VARCHAR(50) NOT NULL CHECK (grupo IN (
        'ropa_base','accesorios_textiles','accesorios_cuero',
        'calzado','joyeria_bijouteria','juguetes','hogar_cultura','bebe'
    )),
    descripcion     TEXT,
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS subcategorias_ropa (
    id              SERIAL PRIMARY KEY,
    categoria_id    INTEGER NOT NULL REFERENCES categorias_ropa(id) ON DELETE CASCADE,
    codigo          VARCHAR(30) UNIQUE NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    especificaciones TEXT,
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS niveles_calidad (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(30) UNIQUE NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    canal_asignado  VARCHAR(20) NOT NULL CHECK (canal_asignado IN ('online','feria','retazo')),
    descripcion     TEXT,
    criterios       TEXT,
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS temporadas (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(20) UNIQUE NOT NULL,
    nombre          VARCHAR(50) NOT NULL,
    meses_inicio    INTEGER,
    meses_fin       INTEGER,
    activo          BOOLEAN DEFAULT TRUE
);

-- ============================================
-- 2. ALTER TABLE: PRODUCTOS (existente, agregar columnas)
-- ============================================

-- Renombrar columnas existentes para compatibilidad
ALTER TABLE productos RENAME COLUMN categoria_id TO categoria_feriaapp_id;
ALTER TABLE productos RENAME COLUMN subcategoria_id TO subcategoria_feriaapp_id;

-- Agregar columnas nuevas (solo si no existen)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='codigo_barras') THEN
        ALTER TABLE productos ADD COLUMN codigo_barras VARCHAR(50) UNIQUE;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='categoria_revistete_id') THEN
        ALTER TABLE productos ADD COLUMN categoria_revistete_id INTEGER REFERENCES categorias_ropa(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='subcategoria_revistete_id') THEN
        ALTER TABLE productos ADD COLUMN subcategoria_revistete_id INTEGER REFERENCES subcategorias_ropa(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='genero_id') THEN
        ALTER TABLE productos ADD COLUMN genero_id INTEGER REFERENCES generos(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='segmento_edad_id') THEN
        ALTER TABLE productos ADD COLUMN segmento_edad_id INTEGER REFERENCES segmentos_edad(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='talla') THEN
        ALTER TABLE productos ADD COLUMN talla VARCHAR(20);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='talla_numerica') THEN
        ALTER TABLE productos ADD COLUMN talla_numerica INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='medidas') THEN
        ALTER TABLE productos ADD COLUMN medidas JSONB;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='precio_online') THEN
        ALTER TABLE productos ADD COLUMN precio_online INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='precio_feria') THEN
        ALTER TABLE productos ADD COLUMN precio_feria INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='precio_standard') THEN
        ALTER TABLE productos ADD COLUMN precio_standard INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='precio_final') THEN
        ALTER TABLE productos ADD COLUMN precio_final INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='nivel_calidad_id') THEN
        ALTER TABLE productos ADD COLUMN nivel_calidad_id INTEGER REFERENCES niveles_calidad(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='temporada_id') THEN
        ALTER TABLE productos ADD COLUMN temporada_id INTEGER REFERENCES temporadas(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='temporadas_en_inventario') THEN
        ALTER TABLE productos ADD COLUMN temporadas_en_inventario INTEGER DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='descripcion_defectos') THEN
        ALTER TABLE productos ADD COLUMN descripcion_defectos TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='marca') THEN
        ALTER TABLE productos ADD COLUMN marca VARCHAR(100);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='evaluado_por_id') THEN
        ALTER TABLE productos ADD COLUMN evaluado_por_id INTEGER REFERENCES usuarios(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='fecha_evaluacion') THEN
        ALTER TABLE productos ADD COLUMN fecha_evaluacion TIMESTAMPTZ;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='fotos') THEN
        ALTER TABLE productos ADD COLUMN fotos JSONB DEFAULT '[]';
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='productos' AND column_name='etiqueta_id') THEN
        ALTER TABLE productos ADD COLUMN etiqueta_id VARCHAR(50) UNIQUE;
    END IF;
END $$;

-- Actualizar constraint de estado si existe
ALTER TABLE productos DROP CONSTRAINT IF EXISTS productos_estado_check;
ALTER TABLE productos ADD CONSTRAINT productos_estado_check CHECK (estado IN (
    'disponible','reservado','vendido','retazo','donado','en_evaluacion'
));

-- Agregar índices nuevos
CREATE INDEX IF NOT EXISTS idx_productos_codigo ON productos(codigo_barras);
CREATE INDEX IF NOT EXISTS idx_productos_categoria_revistete ON productos(categoria_revistete_id);
CREATE INDEX IF NOT EXISTS idx_productos_genero ON productos(genero_id);
CREATE INDEX IF NOT EXISTS idx_productos_segmento ON productos(segmento_edad_id);
CREATE INDEX IF NOT EXISTS idx_productos_nivel_calidad ON productos(nivel_calidad_id);

-- ============================================
-- 3. NUEVAS TABLAS: PRECIOS, FLUJO, ETIQUETAS
-- ============================================

CREATE TABLE IF NOT EXISTS precios_standard (
    id              SERIAL PRIMARY KEY,
    producto_id     INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    canal           VARCHAR(20) NOT NULL CHECK (canal IN ('online','feria','retazo')),
    precio_standard INTEGER NOT NULL,
    moneda          VARCHAR(3) DEFAULT 'CLP',
    vigente_desde   DATE NOT NULL,
    vigente_hasta   DATE,
    creado_por_id   INTEGER REFERENCES usuarios(id),
    UNIQUE (producto_id, canal, vigente_desde)
);

CREATE TABLE IF NOT EXISTS flujo_prenda (
    id              SERIAL PRIMARY KEY,
    producto_id     INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    canal_origen    VARCHAR(20) NOT NULL,
    canal_destino   VARCHAR(20) NOT NULL,
    nivel_calidad_origen_id INTEGER REFERENCES niveles_calidad(id),
    nivel_calidad_destino_id INTEGER REFERENCES niveles_calidad(id),
    motivo          TEXT,
    evaluado_por_id INTEGER REFERENCES usuarios(id),
    fecha_movimiento TIMESTAMPTZ DEFAULT NOW(),
    notas           TEXT
);

CREATE TABLE IF NOT EXISTS etiquetas (
    id              SERIAL PRIMARY KEY,
    producto_id     INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    tipo_codigo     VARCHAR(20) NOT NULL CHECK (tipo_codigo IN ('qr','barcode','rfid')),
    codigo          VARCHAR(100) UNIQUE NOT NULL,
    formato_data    TEXT,
    impresa         BOOLEAN DEFAULT FALSE,
    fecha_impresion TIMESTAMPTZ,
    estado          VARCHAR(20) DEFAULT 'activa' CHECK (estado IN ('activa','perdida','danada','retirada')),
    ultima_lectura  TIMESTAMPTZ,
    ubicacion_actual VARCHAR(100) DEFAULT 'bodega'
);

CREATE INDEX IF NOT EXISTS idx_etiquetas_codigo ON etiquetas(codigo);

-- ============================================
-- 4. ALTER TABLE: EVENTOS FERIA (cambiar default)
-- ============================================

ALTER TABLE eventos_feria ALTER COLUMN estado SET DEFAULT 'activo';

-- Agregar columnas de revisión manual
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='eventos_feria' AND column_name='total_confirmado') THEN
        ALTER TABLE eventos_feria ADD COLUMN total_confirmado INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='eventos_feria' AND column_name='diferencia') THEN
        ALTER TABLE eventos_feria ADD COLUMN diferencia INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='eventos_feria' AND column_name='revisado_por_id') THEN
        ALTER TABLE eventos_feria ADD COLUMN revisado_por_id INTEGER REFERENCES usuarios(id);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='eventos_feria' AND column_name='fecha_revision') THEN
        ALTER TABLE eventos_feria ADD COLUMN fecha_revision TIMESTAMPTZ;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='eventos_feria' AND column_name='fecha_cierre') THEN
        ALTER TABLE eventos_feria ADD COLUMN fecha_cierre TIMESTAMPTZ;
    END IF;
END $$;

-- ============================================
-- 5. ALTER TABLE: VENTAS (tracking rebajas)
-- ============================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='journal_ventas' AND column_name='precio_standard_total') THEN
        ALTER TABLE journal_ventas ADD COLUMN precio_standard_total INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='journal_ventas' AND column_name='precio_final_total') THEN
        ALTER TABLE journal_ventas ADD COLUMN precio_final_total INTEGER NOT NULL DEFAULT 0;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='journal_ventas' AND column_name='diferencia_rebaja') THEN
        ALTER TABLE journal_ventas ADD COLUMN diferencia_rebaja INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='journal_ventas' AND column_name='porcentaje_rebaja') THEN
        ALTER TABLE journal_ventas ADD COLUMN porcentaje_rebaja NUMERIC(5,2);
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='journal_ventas' AND column_name='tipo_rebaja') THEN
        ALTER TABLE journal_ventas ADD COLUMN tipo_rebaja VARCHAR(30) CHECK (tipo_rebaja IN (
            'ninguna','rebaja_cliente_frecuente','compra_masiva','prenda_especial',
            'promocion_temporal','error_correccion','mora_negociada','trueque_valor_menor','otro'
        ));
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='journal_ventas' AND column_name='motivo_rebaja') THEN
        ALTER TABLE journal_ventas ADD COLUMN motivo_rebaja TEXT;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='journal_ventas' AND column_name='aprobado_por_id') THEN
        ALTER TABLE journal_ventas ADD COLUMN aprobado_por_id INTEGER REFERENCES usuarios(id);
    END IF;
END $$;

-- ============================================
-- 6. NUEVA TABLA: REBAJAS DETALLE
-- ============================================

CREATE TABLE IF NOT EXISTS venta_rebajas (
    id              SERIAL PRIMARY KEY,
    venta_id        INTEGER NOT NULL REFERENCES journal_ventas(id) ON DELETE CASCADE,
    linea_venta_id  INTEGER REFERENCES lineas_venta(id),
    precio_standard INTEGER NOT NULL,
    precio_final    INTEGER NOT NULL,
    diferencia      INTEGER GENERATED ALWAYS AS (precio_final - precio_standard) STORED,
    tipo_rebaja     VARCHAR(30) DEFAULT 'ninguna' CHECK (tipo_rebaja IN (
        'ninguna','rebaja_cliente_frecuente','compra_masiva','prenda_especial',
        'promocion_temporal','error_correccion','mora_negociada','trueque_valor_menor','otro'
    )),
    porcentaje_rebaja NUMERIC(5,2) GENERATED ALWAYS AS (
        CASE WHEN precio_standard > 0 
        THEN ((precio_standard - precio_final)::NUMERIC / precio_standard * 100) 
        ELSE 0 END
    ) STORED,
    nota_rebaja     TEXT,
    aprobado_por_id INTEGER REFERENCES usuarios(id),
    fecha_registro  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 7. ALTER TABLE: LÍNEAS VENTA (precio standard)
-- ============================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='lineas_venta' AND column_name='precio_unitario_standard') THEN
        ALTER TABLE lineas_venta ADD COLUMN precio_unitario_standard INTEGER;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='lineas_venta' AND column_name='precio_unitario_final') THEN
        ALTER TABLE lineas_venta RENAME COLUMN precio_unitario TO precio_unitario_final;
    END IF;
END $$;

-- ============================================
-- 8. SEED DATA: NUEVOS CATÁLOGOS
-- ============================================

INSERT INTO segmentos_edad (codigo, nombre, rango_anios) VALUES
('adulto', 'Adulto', '18+'),
('adolescente', 'Adolescente', '13-17'),
('nino', 'Niño', '3-12'),
('nina', 'Niña', '3-12'),
('bebe', 'Bebé', '0-24m')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO generos (codigo, nombre) VALUES
('hombre', 'Hombre'),
('mujer', 'Mujer'),
('unisex', 'Unisex')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO categorias_ropa (codigo, nombre, grupo, descripcion) VALUES
('pantalones', 'Pantalones', 'ropa_base', 'Jeans, formales, cargo, deportivos'),
('buzos', 'Buzos / Polerones', 'ropa_base', 'Canguro, cierre, oversize'),
('shorts', 'Shorts', 'ropa_base', 'Casual, deportivo, baño'),
('calzas', 'Calzas', 'ropa_base', 'Deportivas, térmicas, moda'),
('polera_mc', 'Polera manga corta', 'ropa_base', 'Básica, estampada, polo'),
('polera_ml', 'Polera manga larga', 'ropa_base', 'Básica, térmica, estampada'),
('camisas', 'Camisas', 'ropa_base', 'Formal, casual, flannel'),
('blusas', 'Blusas', 'ropa_base', 'Casual, formal, boho'),
('vestidos', 'Vestidos', 'ropa_base', 'Casual, formal, cocktail'),
('vestidos_fiesta', 'Vestidos de fiesta', 'ropa_base', 'Gala, noche, matrimonio'),
('chalecos', 'Chalecos', 'ropa_base', 'Acolchado, tejido, formal'),
('chompas', 'Chompas / Sweaters', 'ropa_base', 'Tejido, cuello V, cuello alto'),
('chaquetas', 'Chaquetas', 'ropa_base', 'Cuero, jean, bomber, blazer'),
('abrigos', 'Abrigos', 'ropa_base', 'Largo, medio, parka, trench'),
('pijamas', 'Pijamas', 'ropa_base', 'Set, pieza única, térmico'),
('ropa_interior', 'Ropa interior', 'ropa_base', 'Sostén, calzones, calzoncillos, moldeadores, primera capa'),
('traje_bano', 'Traje de baño', 'ropa_base', 'Entero, bikini, short baño'),
('gorras', 'Gorras (jockey)', 'accesorios_textiles', 'Snapback, trucker, curva'),
('gorros', 'Gorros', 'accesorios_textiles', 'Lana, beanie, con pompón'),
('sombreros', 'Sombreros', 'accesorios_textiles', 'Panamá, vaquero, playa'),
('panuelos', 'Pañuelos / Bandanas', 'accesorios_textiles', 'Seda, algodón, estampado'),
('chales', 'Chales / Pashminas', 'accesorios_textiles', 'Tejido, ligero, ceremonial'),
('bufandas', 'Bufandas', 'accesorios_textiles', 'Lana, seda, infinito'),
('ponchos', 'Ponchos', 'accesorios_textiles', 'Tejido, lana, étnico'),
('guantes', 'Guantes', 'accesorios_textiles', 'Cuero, lana, táctil'),
('cinturones', 'Cinturones', 'accesorios_cuero', 'Casual, formal, reversible'),
('carteras', 'Carteras', 'accesorios_cuero', 'Billetera, clutch, sobre'),
('bolsos', 'Bolsos', 'accesorios_cuero', 'Tote, crossbody, mochila urbana'),
('mochilas', 'Mochilas', 'accesorios_cuero', 'Escolar, trekking, urbana'),
('zapatillas', 'Zapatillas', 'calzado', 'Urbana, deportiva, running'),
('zapato_vestir', 'Zapato de vestir', 'calzado', 'Oxford, mocasín, tacón'),
('botas', 'Botas', 'calzado', 'Chelsea, trekking, lluvia'),
('bototos', 'Bototos', 'calzado', 'Trabajo, seguridad, moto'),
('pantuflas', 'Pantuflas', 'calzado', 'Casa, térmica, antideslizante'),
('chalas', 'Chalas / Sandalias', 'calzado', 'Playa, urbana, ortopédica'),
('aros', 'Aros', 'joyeria_bijouteria', 'Colgante, botón, argolla'),
('cadenas', 'Cadenas', 'joyeria_bijouteria', 'Gargantilla, larga, medallón'),
('collares', 'Collares', 'joyeria_bijouteria', 'Piedra, metal, artesanal'),
('pulseras', 'Pulseras', 'joyeria_bijouteria', 'Cadena, cuero, tejida'),
('anillos', 'Anillos', 'joyeria_bijouteria', 'Ajustable, talla fija, sello'),
('llaveros', 'Llaveros', 'joyeria_bijouteria', 'Metálico, cuero, artesanal'),
('prendedores', 'Prendedores / Broches', 'joyeria_bijouteria', 'Vintage, artesanal, temático'),
('bijouteria_artesana', 'Bijoutería artesana', 'joyeria_bijouteria', 'Piezas únicas, autoría local'),
('juguetes_bateria', 'Juguetes a batería', 'juguetes', 'Con control, robot, vehículo'),
('peluches', 'Peluches', 'juguetes', 'Pequeño, mediano, grande'),
('juegos_didacticos', 'Juegos didácticos', 'juguetes', 'Madera, plástico, magnético'),
('juguetes_madera', 'Juguetes de madera', 'juguetes', 'Rompecabezas, construcción'),
('munecos_accion', 'Muñecos de acción', 'juguetes', 'Licencia, articulado, vintage'),
('autos_juguete', 'Autos', 'juguetes', 'Die-cast, a control, pista'),
('otros_juguetes', 'Otros juguetes', 'juguetes', 'Categoría residual'),
('libros', 'Libros', 'hogar_cultura', 'Ficción, no ficción, infantil, académico'),
('revistas', 'Revistas', 'hogar_cultura', 'Moda, diseño, hobbies, vintage'),
('decoracion', 'Decoración', 'hogar_cultura', 'Cuadros, espejos, objetos'),
('lamparas', 'Lámparas', 'hogar_cultura', 'Mesa, pie, pared, vintage'),
('artesania_hogar', 'Artesanía', 'hogar_cultura', 'Cerámica, tejido, madera'),
('loza', 'Loza / Vajilla', 'hogar_cultura', 'Platos, tazas, juegos'),
('servicio', 'Servicio', 'hogar_cultura', 'Otros artículos de hogar'),
('piluchos', 'Piluchos / Bodies', 'bebe', 'Manga corta, larga, sin mangas'),
('panties_bebe', 'Panties (bebé)', 'bebe', 'Cubrepañal, estampado'),
('enteritos', 'Enteritos', 'bebe', 'Mameluco, pijama enterizo'),
('pechera', 'Pechera / Babero', 'bebe', 'Tela, plástico, diseño')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO niveles_calidad (codigo, nombre, canal_asignado, descripcion, criterios) VALUES
('marca', 'Como nueva de marca', 'online', 'Etiqueta original o sin uso aparente', '{"fotos": "profesional", "medidas": "exactas", "defectos": "ninguno"}'),
('boutique', 'Como nueva de boutique', 'online', 'Sin etiqueta pero sin uso', '{"fotos": "profesional", "medidas": "exactas", "defectos": "ninguno"}'),
('intervenida', 'Ropa intervenida', 'online', 'Reparada/alterada profesionalmente', '{"fotos": "profesional", "medidas": "exactas", "nota": "describir_intervencion"}'),
('primera_sel', 'Primera selección', 'feria', '+2 temporadas sin vender online', '{"precio": "reducido", "transparencia": "temporadas_en_inventario"}'),
('sin_marca', 'Sin marca, buen estado', 'feria', 'Detalles menores permitidos', '{"precio": "accesible", "nota": "detalles_menores"}'),
('donacion', 'Ropa donación', 'feria', 'Estado digno, funcional', '{"precio": "simbólico", "programa": "dignidad"}'),
('digna', 'Digna de portar', 'feria', 'Con detalles, sin hoyos', '{"precio": "accesible", "transparencia": "defectos_descritos"}'),
('retazo', 'Retazo de género', 'retazo', 'No viable para venta', '{"destino": "artesania_patchwork_relleno"}')
ON CONFLICT (codigo) DO NOTHING;

INSERT INTO temporadas (codigo, nombre, meses_inicio, meses_fin) VALUES
('primavera', 'Primavera', 9, 11),
('verano', 'Verano', 12, 2),
('otono', 'Otoño', 3, 5),
('invierno', 'Invierno', 6, 8),
('atemporal', 'Atemporal', NULL, NULL)
ON CONFLICT (codigo) DO NOTHING;

-- ============================================
-- 9. ÍNDICES ADICIONALES PARA NUEVAS TABLAS
-- ============================================

CREATE INDEX IF NOT EXISTS idx_categorias_ropa_grupo ON categorias_ropa(grupo);
CREATE INDEX IF NOT EXISTS idx_categorias_ropa_activo ON categorias_ropa(activo);
CREATE INDEX IF NOT EXISTS idx_subcategorias_ropa_categoria ON subcategorias_ropa(categoria_id);
CREATE INDEX IF NOT EXISTS idx_subcategorias_ropa_activo ON subcategorias_ropa(activo);
CREATE INDEX IF NOT EXISTS idx_niveles_calidad_canal ON niveles_calidad(canal_asignado);
CREATE INDEX IF NOT EXISTS idx_flujo_prenda_producto ON flujo_prenda(producto_id);
CREATE INDEX IF NOT EXISTS idx_flujo_prenda_fecha ON flujo_prenda(fecha_movimiento);
CREATE INDEX IF NOT EXISTS idx_precios_standard_producto ON precios_standard(producto_id);
CREATE INDEX IF NOT EXISTS idx_precios_standard_vigente ON precios_standard(vigente_desde, vigente_hasta);
CREATE INDEX IF NOT EXISTS idx_venta_rebajas_venta ON venta_rebajas(venta_id);
CREATE INDEX IF NOT EXISTS idx_venta_rebajas_linea ON venta_rebajas(linea_venta_id);

-- ============================================
-- 10. VISTAS ÚTILES
-- ============================================

CREATE OR REPLACE VIEW v_productos_disponibles AS
SELECT 
    p.id,
    p.uuid,
    p.nombre,
    p.etiqueta_id,
    p.codigo_barras,
    p.marca,
    p.talla,
    p.condicion,
    p.estado,
    p.precio_online,
    p.precio_feria,
    p.precio_standard,
    p.precio_final,
    p.temporadas_en_inventario,
    p.descripcion_defectos,
    p.fotos,
    p.created_at,
    p.updated_at,
    g.nombre AS genero,
    se.nombre AS segmento_edad,
    cr.nombre AS categoria_revistete,
    sr.nombre AS subcategoria_revistete,
    cf.nombre AS categoria_feriaapp,
    sf.nombre AS subcategoria_feriaapp,
    nc.nombre AS nivel_calidad,
    nc.canal_asignado AS canal_recomendado,
    t.nombre AS temporada
FROM productos p
LEFT JOIN generos g ON p.genero_id = g.id
LEFT JOIN segmentos_edad se ON p.segmento_edad_id = se.id
LEFT JOIN categorias_ropa cr ON p.categoria_revistete_id = cr.id
LEFT JOIN subcategorias_ropa sr ON p.subcategoria_revistete_id = sr.id
LEFT JOIN categorias_producto cf ON p.categoria_feriaapp_id = cf.id
LEFT JOIN subcategorias_producto sf ON p.subcategoria_feriaapp_id = sf.id
LEFT JOIN niveles_calidad nc ON p.nivel_calidad_id = nc.id
LEFT JOIN temporadas t ON p.temporada_id = t.id
WHERE p.activo = TRUE AND p.estado IN ('disponible', 'en_evaluacion');

CREATE OR REPLACE VIEW v_rebajas_por_evento AS
SELECT 
    ef.id AS evento_id,
    ef.fecha,
    ef.lugar,
    ef.estado,
    COUNT(jv.id) AS total_ventas,
    SUM(jv.precio_standard_total) AS total_standard,
    SUM(jv.precio_final_total) AS total_final,
    SUM(COALESCE(jv.diferencia_rebaja, 0)) AS total_rebajas,
    ROUND(AVG(COALESCE(jv.porcentaje_rebaja, 0))::NUMERIC, 2) AS rebaja_promedio_pct
FROM eventos_feria ef
LEFT JOIN journal_ventas jv ON ef.id = jv.evento_feria_id
GROUP BY ef.id, ef.fecha, ef.lugar, ef.estado;

-- ============================================
-- 11. FUNCIONES AUXILIARES
-- ============================================

CREATE OR REPLACE FUNCTION calcular_precio_sugerido(
    p_producto_id INTEGER,
    p_canal VARCHAR(20)
) RETURNS INTEGER AS $$
DECLARE
    v_precio INTEGER;
    v_nivel VARCHAR(30);
    v_temporadas INTEGER;
BEGIN
    SELECT nivel_calidad_id, temporadas_en_inventario 
    INTO v_nivel, v_temporadas
    FROM productos WHERE id = p_producto_id;
    
    SELECT COALESCE(
        CASE p_canal
            WHEN 'online' THEN precio_online
            WHEN 'feria' THEN precio_feria
            WHEN 'retazo' THEN precio_standard * 0.2
            ELSE precio_standard
        END,
        precio_standard,
        0
    ) INTO v_precio
    FROM productos WHERE id = p_producto_id;
    
    IF p_canal = 'feria' AND v_temporadas > 2 THEN
        v_precio := v_precio * (1 - (FLOOR(v_temporadas::FLOAT / 2) * 0.1));
    END IF;
    
    RETURN GREATEST(v_precio, 0)::INTEGER;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION mover_prenda_canal(
    p_producto_id INTEGER,
    p_canal_origen VARCHAR(20),
    p_canal_destino VARCHAR(20),
    p_motivo TEXT,
    p_usuario_id INTEGER
) RETURNS VOID AS $$
BEGIN
    INSERT INTO flujo_prenda (
        producto_id, canal_origen, canal_destino, 
        nivel_calidad_origen_id, nivel_calidad_destino_id,
        motivo, evaluado_por_id
    ) VALUES (
        p_producto_id, p_canal_origen, p_canal_destino,
        (SELECT nivel_calidad_id FROM productos WHERE id = p_producto_id),
        NULL,
        p_motivo, p_usuario_id
    );
    
    UPDATE productos SET 
        estado = CASE 
            WHEN p_canal_destino = 'retazo' THEN 'retazo'
            WHEN p_canal_destino = 'online' THEN 'disponible'
            WHEN p_canal_destino = 'feria' THEN 'disponible'
            ELSE estado
        END,
        updated_at = NOW()
    WHERE id = p_producto_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 12. TRIGGERS
-- ============================================

CREATE OR REPLACE FUNCTION update_productos_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_productos_updated_at ON productos;
CREATE TRIGGER trg_productos_updated_at
BEFORE UPDATE ON productos
FOR EACH ROW EXECUTE FUNCTION update_productos_updated_at();

CREATE OR REPLACE FUNCTION incrementar_temporada_inventario()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.temporada_id IS DISTINCT FROM NEW.temporada_id AND NEW.temporada_id IS NOT NULL THEN
        NEW.temporadas_en_inventario = COALESCE(OLD.temporadas_en_inventario, 0) + 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_temporada_inventario ON productos;
CREATE TRIGGER trg_temporada_inventario
BEFORE UPDATE ON productos
FOR EACH ROW EXECUTE FUNCTION incrementar_temporada_inventario();

CREATE OR REPLACE FUNCTION validar_cierre_evento()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.estado = 'cerrado' AND OLD.estado != 'cerrado' THEN
        IF NEW.revisado_por_id IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar evento sin revisión manual. Asigne revisado_por_id.';
        END IF;
        IF NEW.total_confirmado IS NULL THEN
            RAISE EXCEPTION 'No se puede cerrar evento sin total_confirmado. Revise manualmente.';
        END IF;
        NEW.fecha_cierre = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_validar_cierre_evento ON eventos_feria;
CREATE TRIGGER trg_validar_cierre_evento
BEFORE UPDATE ON eventos_feria
FOR EACH ROW EXECUTE FUNCTION validar_cierre_evento();

-- ============================================
-- 13. RESET DE SECUENCIAS PARA NUEVAS TABLAS
-- ============================================

SELECT setval('segmentos_edad_id_seq', 5, true);
SELECT setval('generos_id_seq', 3, true);
SELECT setval('categorias_ropa_id_seq', 50, true);
SELECT setval('niveles_calidad_id_seq', 8, true);
SELECT setval('temporadas_id_seq', 5, true);

-- ============================================
-- 14. VERIFICACIÓN POST-MIGRACIÓN
-- ============================================

-- Comentario: Ejecutar estas queries para verificar
/*
SELECT 'Segmentos edad' as tabla, COUNT(*) as registros FROM segmentos_edad
UNION ALL SELECT 'Géneros', COUNT(*) FROM generos
UNION ALL SELECT 'Categorías ropa', COUNT(*) FROM categorias_ropa
UNION ALL SELECT 'Niveles calidad', COUNT(*) FROM niveles_calidad
UNION ALL SELECT 'Temporadas', COUNT(*) FROM temporadas
UNION ALL SELECT 'Productos', COUNT(*) FROM productos
UNION ALL SELECT 'Eventos feria', COUNT(*) FROM eventos_feria;

SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'productos' 
AND column_name IN ('categoria_revistete_id', 'genero_id', 'segmento_edad_id', 
    'precio_online', 'precio_feria', 'nivel_calidad_id', 'temporada_id', 
    'temporadas_en_inventario', 'descripcion_defectos', 'marca', 'fotos')
ORDER BY ordinal_position;
*/

-- ============================================
-- NOTAS DE ROLLBACK (manual)
-- ============================================
/*
DROP TRIGGER IF EXISTS trg_validar_cierre_evento ON eventos_feria;
DROP TRIGGER IF EXISTS trg_temporada_inventario ON productos;
DROP TRIGGER IF EXISTS trg_productos_updated_at ON productos;
DROP FUNCTION IF EXISTS validar_cierre_evento();
DROP FUNCTION IF EXISTS incrementar_temporada_inventario();
DROP FUNCTION IF EXISTS update_productos_updated_at();
DROP FUNCTION IF EXISTS mover_prenda_canal(INTEGER, VARCHAR, VARCHAR, TEXT, INTEGER);
DROP FUNCTION IF EXISTS calcular_precio_sugerido(INTEGER, VARCHAR);
DROP VIEW IF EXISTS v_rebajas_por_evento;
DROP VIEW IF EXISTS v_productos_disponibles;
DROP TABLE IF EXISTS venta_rebajas;
DROP TABLE IF EXISTS precios_standard;
DROP TABLE IF EXISTS flujo_prenda;
DROP TABLE IF EXISTS etiquetas;
*/
