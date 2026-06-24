-- ============================================
-- FERIAAPP + RE-VISTETE v2.1
-- Schema completo con segmentación moda circular
-- Eventos quedan ABIERTOS para revisión manual
-- ============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- 1. CATÁLOGOS BASE (compartidos FeriaApp + Re-Vistete)
-- ============================================

CREATE TABLE canales_venta (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    tipo            VARCHAR(30) NOT NULL CHECK (tipo IN (
        'feria_dominical','feria_chic','feria_artesanal','feria_navidena',
        'feria_cerrada','instagram','marketplace','presencial_stgo',
        'presencial_directo','online'
    )),
    descripcion     TEXT,
    activo          BOOLEAN DEFAULT TRUE,
    fecha_inicio    DATE,
    fecha_cierre    DATE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE segmentos_edad (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(20) UNIQUE NOT NULL,
    nombre          VARCHAR(50) NOT NULL,
    rango_anios     VARCHAR(30), -- ej: "0-2", "13-17", "18+"
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE generos (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(20) UNIQUE NOT NULL,
    nombre          VARCHAR(50) NOT NULL,
    activo          BOOLEAN DEFAULT TRUE
);

-- ============================================
-- 2. CATEGORÍAS RE-VISTETE (moda circular detallada)
-- ============================================

CREATE TABLE categorias_ropa (
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

CREATE TABLE subcategorias_ropa (
    id              SERIAL PRIMARY KEY,
    categoria_id    INTEGER NOT NULL REFERENCES categorias_ropa(id) ON DELETE CASCADE,
    codigo          VARCHAR(30) UNIQUE NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    especificaciones TEXT, -- JSON con variantes
    activo          BOOLEAN DEFAULT TRUE
);

-- ============================================
-- 3. NIVELES DE CALIDAD Y CANALES (Re-Vistete)
-- ============================================

CREATE TABLE niveles_calidad (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(30) UNIQUE NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    canal_asignado  VARCHAR(20) NOT NULL CHECK (canal_asignado IN ('online','feria','retazo')),
    descripcion     TEXT,
    criterios       TEXT, -- JSON con reglas de evaluación
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE temporadas (
    id              SERIAL PRIMARY KEY,
    codigo          VARCHAR(20) UNIQUE NOT NULL,
    nombre          VARCHAR(50) NOT NULL,
    meses_inicio    INTEGER,
    meses_fin       INTEGER,
    activo          BOOLEAN DEFAULT TRUE
);

-- ============================================
-- 4. CATEGORÍAS FERIAAPP/TOQUÍ (originales)
-- ============================================

CREATE TABLE categorias_producto (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    sector_puesto   VARCHAR(20) NOT NULL CHECK (sector_puesto IN (
        'infantil','alimentos','hombres','mujeres','accesorios','fondo','artesania','sin_sector'
    )),
    tipo_origen     VARCHAR(20) NOT NULL CHECK (tipo_origen IN (
        'propio','vecino','reventa','donacion','huerta'
    )),
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE subcategorias_producto (
    id              SERIAL PRIMARY KEY,
    categoria_id    INTEGER NOT NULL REFERENCES categorias_producto(id) ON DELETE CASCADE,
    nombre          VARCHAR(100) NOT NULL,
    activo          BOOLEAN DEFAULT TRUE
);

CREATE TABLE categoria_canal (
    categoria_id    INTEGER NOT NULL REFERENCES categorias_producto(id) ON DELETE CASCADE,
    canal_id        INTEGER NOT NULL REFERENCES canales_venta(id) ON DELETE CASCADE,
    PRIMARY KEY (categoria_id, canal_id)
);

-- ============================================
-- 5. USUARIOS Y DISPOSITIVOS (Auth v2)
-- ============================================

CREATE TABLE usuarios (
    id              SERIAL PRIMARY KEY,
    uuid            UUID DEFAULT uuid_generate_v4() UNIQUE,
    nombre          VARCHAR(100) NOT NULL,
    rol             VARCHAR(20) NOT NULL CHECK (rol IN (
        'propietario','esposa','hija_mayor','hija_menor','externo'
    )),
    password_hash   VARCHAR(255) NOT NULL,
    activo          BOOLEAN DEFAULT TRUE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE dispositivos (
    id              SERIAL PRIMARY KEY,
    uuid            UUID DEFAULT uuid_generate_v4() UNIQUE,
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
    nombre          VARCHAR(100) NOT NULL,
    tipo            VARCHAR(20) NOT NULL CHECK (tipo IN ('movil','desktop')),
    platform        VARCHAR(20),
    public_key      TEXT,
    ultimo_sync     TIMESTAMPTZ,
    confianza       INTEGER DEFAULT 0,
    revocado        BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE refresh_tokens (
    id              SERIAL PRIMARY KEY,
    dispositivo_id  INTEGER NOT NULL REFERENCES dispositivos(id) ON DELETE CASCADE,
    token_hash      VARCHAR(255) NOT NULL,
    expira_en       TIMESTAMPTZ NOT NULL,
    usado_en        TIMESTAMPTZ,
    revocado        BOOLEAN DEFAULT FALSE,
    ip_origen       INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Trigger: revocar tokens anteriores
CREATE OR REPLACE FUNCTION revocar_tokens_anteriores()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE refresh_tokens
    SET revocado = TRUE
    WHERE dispositivo_id = NEW.dispositivo_id
      AND id != NEW.id
      AND usado_en IS NULL;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_revocar_tokens_anteriores
AFTER INSERT ON refresh_tokens
FOR EACH ROW EXECUTE FUNCTION revocar_tokens_anteriores();

-- ============================================
-- 6. PRODUCTOS (unificado FeriaApp + Re-Vistete)
-- ============================================

CREATE TABLE productos (
    id              SERIAL PRIMARY KEY,
    uuid            UUID DEFAULT uuid_generate_v4() UNIQUE,

    -- Identificación
    nombre          VARCHAR(150) NOT NULL,
    etiqueta_id     VARCHAR(50) UNIQUE,
    codigo_barras   VARCHAR(50) UNIQUE,

    -- Categorización dual (FeriaApp o Re-Vistete)
    categoria_feriaapp_id INTEGER REFERENCES categorias_producto(id),
    categoria_revistete_id INTEGER REFERENCES categorias_ropa(id),
    subcategoria_feriaapp_id INTEGER REFERENCES subcategorias_producto(id),
    subcategoria_revistete_id INTEGER REFERENCES subcategorias_ropa(id),

    -- Segmentación Re-Vistete
    genero_id       INTEGER REFERENCES generos(id),
    segmento_edad_id INTEGER REFERENCES segmentos_edad(id),

    -- Medidas y tallaje
    talla           VARCHAR(20),
    talla_numerica  INTEGER,
    medidas         JSONB, -- {largo: 102, ancho: 50, manga: 60, cintura: 76, cadera: 96}

    -- Precios por canal (Re-Vistete)
    precio_online   INTEGER,
    precio_feria    INTEGER,
    precio_standard INTEGER, -- referencia
    precio_final    INTEGER, -- editable en venta
    moneda          VARCHAR(3) DEFAULT 'CLP',

    -- Nivel de calidad (Re-Vistete)
    nivel_calidad_id INTEGER REFERENCES niveles_calidad(id),
    condicion       VARCHAR(30) CHECK (condicion IN (
        'como_nueva_marca','como_nueva_boutique','intervenida',
        'primera_seleccion','sin_marca','donacion','digna_portar','retazo'
    )),

    -- Estado y stock
    estado          VARCHAR(20) DEFAULT 'disponible' CHECK (estado IN (
        'disponible','reservado','vendido','retazo','donado','en_evaluacion'
    )),
    temporada_id    INTEGER REFERENCES temporadas(id),
    temporadas_en_inventario INTEGER DEFAULT 0,

    -- Descripción y defectos
    descripcion     TEXT,
    descripcion_defectos TEXT,
    marca           VARCHAR(100),

    -- Fotos (URLs en R2/Cloudflare)
    fotos           JSONB DEFAULT '[]',

    -- Metadata
    activo          BOOLEAN DEFAULT TRUE,
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW(),
    evaluado_por_id INTEGER REFERENCES usuarios(id),
    fecha_evaluacion TIMESTAMPTZ
);

CREATE INDEX idx_productos_estado ON productos(estado);
CREATE INDEX idx_productos_etiqueta ON productos(etiqueta_id);
CREATE INDEX idx_productos_codigo ON productos(codigo_barras);
CREATE INDEX idx_productos_categoria_feriaapp ON productos(categoria_feriaapp_id);
CREATE INDEX idx_productos_categoria_revistete ON productos(categoria_revistete_id);
CREATE INDEX idx_productos_genero ON productos(genero_id);
CREATE INDEX idx_productos_segmento ON productos(segmento_edad_id);
CREATE INDEX idx_productos_nivel_calidad ON productos(nivel_calidad_id);
CREATE INDEX idx_productos_condicion ON productos(condicion);

-- ============================================
-- 7. PRECIOS STANDARD POR CANAL (histórico)
-- ============================================

CREATE TABLE precios_standard (
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

-- ============================================
-- 8. FLUJO DE PRENDA (tracking de movimiento entre canales)
-- ============================================

CREATE TABLE flujo_prenda (
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

-- ============================================
-- 9. ETIQUETAS (QR/Barcode)
-- ============================================

CREATE TABLE etiquetas (
    id              SERIAL PRIMARY KEY,
    producto_id     INTEGER NOT NULL REFERENCES productos(id) ON DELETE CASCADE,
    tipo_codigo     VARCHAR(20) NOT NULL CHECK (tipo_codigo IN ('qr','barcode','rfid')),
    codigo          VARCHAR(100) UNIQUE NOT NULL,
    formato_data    TEXT, -- JSON con datos embebidos
    impresa         BOOLEAN DEFAULT FALSE,
    fecha_impresion TIMESTAMPTZ,
    estado          VARCHAR(20) DEFAULT 'activa' CHECK (estado IN ('activa','perdida','danada','retirada')),
    ultima_lectura  TIMESTAMPTZ,
    ubicacion_actual VARCHAR(100) DEFAULT 'bodega'
);

CREATE INDEX idx_etiquetas_codigo ON etiquetas(codigo);

-- ============================================
-- 10. CLIENTES Y DEUDAS
-- ============================================

CREATE TABLE clientes_frecuentes (
    id              SERIAL PRIMARY KEY,
    nombre          VARCHAR(100) NOT NULL,
    contacto        VARCHAR(100),
    perfil          VARCHAR(20) DEFAULT 'sin_definir' CHECK (perfil IN ('clase_media','obrero','sin_definir')),
    producto_preferido_id INTEGER REFERENCES productos(id),
    activo          BOOLEAN DEFAULT TRUE,
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE deudas_diferidas (
    id              SERIAL PRIMARY KEY,
    cliente_id      INTEGER NOT NULL REFERENCES clientes_frecuentes(id),
    venta_id        INTEGER,
    monto           INTEGER NOT NULL,
    fecha_venta     DATE NOT NULL,
    fecha_saldado   DATE,
    estado          VARCHAR(20) DEFAULT 'pendiente' CHECK (estado IN ('pendiente','saldado')),
    notas           TEXT
);

-- ============================================
-- 11. EVENTOS DE FERIA (ABIERTOS por defecto)
-- ============================================

CREATE TABLE eventos_feria (
    id              SERIAL PRIMARY KEY,
    canal_venta_id  INTEGER NOT NULL REFERENCES canales_venta(id),
    fecha           DATE NOT NULL,
    lugar           VARCHAR(150),
    vendedor_principal_id INTEGER NOT NULL REFERENCES usuarios(id),
    -- ESTADO: siempre inicia como 'activo', nunca 'cerrado' automático
    estado          VARCHAR(20) DEFAULT 'activo' CHECK (estado IN ('planificado','activo','cerrado')),
    total_calculado INTEGER DEFAULT 0,
    total_confirmado INTEGER, -- revisión manual
    diferencia      INTEGER, -- total_confirmado - total_calculado
    revisado_por_id INTEGER REFERENCES usuarios(id),
    fecha_revision  TIMESTAMPTZ,
    fecha_cierre    TIMESTAMPTZ, -- NULL hasta cierre manual
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 12. VENTAS (tracking completo + rebajas)
-- ============================================

CREATE TABLE journal_ventas (
    id              SERIAL PRIMARY KEY,
    uuid            UUID DEFAULT uuid_generate_v4() UNIQUE,
    evento_feria_id INTEGER NOT NULL REFERENCES eventos_feria(id),
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id),
    dispositivo_id  INTEGER NOT NULL REFERENCES dispositivos(id),

    timestamp_local TIMESTAMPTZ NOT NULL,
    timestamp_sync  TIMESTAMPTZ,

    -- Segmentación
    perfil_cliente  VARCHAR(20) DEFAULT 'sin_definir',
    producto_ancla_id INTEGER REFERENCES productos(id),

    -- Pago
    forma_pago      VARCHAR(20) NOT NULL CHECK (forma_pago IN (
        'efectivo','transferencia','diferido','debito','credito','trueque'
    )),
    estado_pago     VARCHAR(20) DEFAULT 'pagado' CHECK (estado_pago IN ('pagado','mora','pendiente','trueque')),
    cliente_frecuente_id INTEGER REFERENCES clientes_frecuentes(id),

    -- Flags
    venta_directa_sin_bodega BOOLEAN DEFAULT FALSE,
    garantia_devolucion     BOOLEAN DEFAULT FALSE,

    -- Totales y rebajas
    precio_standard_total   INTEGER, -- suma de precios standard
    precio_final_total      INTEGER NOT NULL DEFAULT 0, -- precio real cobrado
    diferencia_rebaja       INTEGER GENERATED ALWAYS AS (precio_final_total - COALESCE(precio_standard_total, precio_final_total)) STORED,
    porcentaje_rebaja       NUMERIC(5,2) GENERATED ALWAYS AS (
        CASE WHEN COALESCE(precio_standard_total, 0) > 0
        THEN ((precio_standard_total - precio_final_total)::NUMERIC / precio_standard_total * 100)
        ELSE 0 END
    ) STORED,

    tipo_rebaja     VARCHAR(30) CHECK (tipo_rebaja IN (
        'ninguna','rebaja_cliente_frecuente','compra_masiva','prenda_especial',
        'promocion_temporal','error_correccion','mora_negociada','trueque_valor_menor','otro'
    )),
    motivo_rebaja   TEXT,
    aprobado_por_id INTEGER REFERENCES usuarios(id),

    -- Totales
    total_venta     INTEGER NOT NULL DEFAULT 0,

    -- Sync
    sync_estado     VARCHAR(20) DEFAULT 'pendiente' CHECK (sync_estado IN ('pendiente','sincronizado','conflicto')),
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 13. LÍNEAS DE VENTA
-- ============================================

CREATE TABLE lineas_venta (
    id              SERIAL PRIMARY KEY,
    venta_id        INTEGER NOT NULL REFERENCES journal_ventas(id) ON DELETE CASCADE,
    producto_id     INTEGER REFERENCES productos(id),
    item_donacion_id INTEGER,
    cantidad        NUMERIC(8,2) NOT NULL DEFAULT 1.00,
    precio_unitario_standard INTEGER,
    precio_unitario_final INTEGER NOT NULL,
    subtotal        INTEGER NOT NULL,
    notas           TEXT
);

-- ============================================
-- 14. REBAJAS DETALLE (tracking individual)
-- ============================================

CREATE TABLE venta_rebajas (
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
-- 15. EGRESOS E INSUMOS (Granja Toquí)
-- ============================================

CREATE TABLE journal_egresos (
    id              SERIAL PRIMARY KEY,
    fecha           DATE NOT NULL,
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id),
    dispositivo_id  INTEGER NOT NULL REFERENCES dispositivos(id),
    tipo            VARCHAR(20) NOT NULL CHECK (tipo IN ('compra_reventa','compra_vecinos','otro')),
    proveedor       VARCHAR(150),
    producto_id     INTEGER REFERENCES productos(id),
    descripcion     TEXT,
    cantidad        NUMERIC(8,2),
    precio_unitario INTEGER,
    total           INTEGER NOT NULL,
    forma_pago      VARCHAR(20) NOT NULL CHECK (forma_pago IN ('efectivo','transferencia')),
    notas           TEXT,
    sync_estado     VARCHAR(20) DEFAULT 'pendiente',
    timestamp_local TIMESTAMPTZ NOT NULL,
    timestamp_sync  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE journal_insumos (
    id              SERIAL PRIMARY KEY,
    fecha           DATE NOT NULL,
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id),
    dispositivo_id  INTEGER NOT NULL REFERENCES dispositivos(id),
    tipo            VARCHAR(30) NOT NULL CHECK (tipo IN (
        'alimento_gallinas','reposicion_gallinas','infraestructura',
        'plantines_semillas','otro'
    )),
    descripcion     TEXT NOT NULL,
    monto           INTEGER NOT NULL,
    forma_pago      VARCHAR(20) NOT NULL CHECK (forma_pago IN ('efectivo','transferencia')),
    notas           TEXT,
    sync_estado     VARCHAR(20) DEFAULT 'pendiente',
    timestamp_local TIMESTAMPTZ NOT NULL,
    timestamp_sync  TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 16. DONACIONES
-- ============================================

CREATE TABLE donaciones (
    id              SERIAL PRIMARY KEY,
    fecha_recepcion DATE NOT NULL,
    fuente          VARCHAR(200),
    lugar_recepcion VARCHAR(20) DEFAULT 'casa' CHECK (lugar_recepcion IN ('casa','puesto')),
    recibido_por_id INTEGER NOT NULL REFERENCES usuarios(id),
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE items_donacion (
    id              SERIAL PRIMARY KEY,
    donacion_id     INTEGER NOT NULL REFERENCES donaciones(id) ON DELETE CASCADE,
    descripcion     VARCHAR(200) NOT NULL,
    categoria_id    INTEGER REFERENCES categorias_producto(id),
    estado          VARCHAR(30) DEFAULT 'por_clasificar' CHECK (estado IN (
        'por_clasificar','apto_venta','descarte','recuperar',
        'vendido','vendido_sin_clasificar'
    )),
    precio_min      INTEGER,
    precio_max      INTEGER,
    ubicacion_bodega VARCHAR(100),
    clasificado_por_id INTEGER REFERENCES usuarios(id),
    fecha_clasificacion DATE,
    vendido_en_evento_id INTEGER REFERENCES eventos_feria(id),
    alerta_pendiente BOOLEAN DEFAULT FALSE,
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 17. SYNC Y AUDITORÍA
-- ============================================

CREATE TABLE sync_log (
    id              SERIAL PRIMARY KEY,
    dispositivo_id  INTEGER NOT NULL REFERENCES dispositivos(id),
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id),
    tabla_afectada  VARCHAR(50) NOT NULL,
    registro_id     INTEGER NOT NULL,
    operacion       VARCHAR(20) NOT NULL CHECK (operacion IN ('insert','update','delete')),
    timestamp_local TIMESTAMPTZ NOT NULL,
    timestamp_servidor TIMESTAMPTZ DEFAULT NOW(),
    estado          VARCHAR(20) DEFAULT 'ok' CHECK (estado IN ('ok','duplicado','conflicto')),
    detalle         TEXT
);

CREATE TABLE reclasificacion_log (
    id              SERIAL PRIMARY KEY,
    producto_id     INTEGER REFERENCES productos(id),
    venta_id        INTEGER REFERENCES journal_ventas(id),
    campo_afectado  VARCHAR(50) NOT NULL,
    valor_anterior  TEXT,
    valor_nuevo     TEXT,
    motivo          TEXT,
    nota_original   TEXT,
    operador        VARCHAR(100),
    confirmado      BOOLEAN DEFAULT FALSE,
    fecha_cambio    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- 18. OFERTAS CRUZADAS (Keysign Labs)
-- ============================================

CREATE TABLE ofertas_cruzadas (
    id              SERIAL PRIMARY KEY,
    proyecto_origen VARCHAR(50) NOT NULL,
    proyecto_destino VARCHAR(50) NOT NULL,
    tipo_oferta     VARCHAR(30) NOT NULL CHECK (tipo_oferta IN (
        'descuento_porcentaje','descuento_fijo','producto_gratis',
        'trueque','acceso_prioritario','experiencia'
    )),
    condicion_trigger TEXT,
    beneficio       JSONB,
    vigencia_desde  DATE NOT NULL,
    vigencia_hasta  DATE,
    activa          BOOLEAN DEFAULT TRUE,
    limite_usos     INTEGER,
    usos_actuales   INTEGER DEFAULT 0
);

-- ============================================
-- SEED DATA: CATÁLOGOS RE-VISTETE
-- ============================================

INSERT INTO segmentos_edad (codigo, nombre, rango_anios) VALUES
('adulto', 'Adulto', '18+'),
('adolescente', 'Adolescente', '13-17'),
('nino', 'Niño', '3-12'),
('nina', 'Niña', '3-12'),
('bebe', 'Bebé', '0-24m');

INSERT INTO generos (codigo, nombre) VALUES
('hombre', 'Hombre'),
('mujer', 'Mujer'),
('unisex', 'Unisex');

INSERT INTO categorias_ropa (codigo, nombre, grupo, descripcion) VALUES
-- Ropa Base
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

-- Accesorios Textiles
('gorras', 'Gorras (jockey)', 'accesorios_textiles', 'Snapback, trucker, curva'),
('gorros', 'Gorros', 'accesorios_textiles', 'Lana, beanie, con pompón'),
('sombreros', 'Sombreros', 'accesorios_textiles', 'Panamá, vaquero, playa'),
('panuelos', 'Pañuelos / Bandanas', 'accesorios_textiles', 'Seda, algodón, estampado'),
('chales', 'Chales / Pashminas', 'accesorios_textiles', 'Tejido, ligero, ceremonial'),
('bufandas', 'Bufandas', 'accesorios_textiles', 'Lana, seda, infinito'),
('ponchos', 'Ponchos', 'accesorios_textiles', 'Tejido, lana, étnico'),
('guantes', 'Guantes', 'accesorios_textiles', 'Cuero, lana, táctil'),

-- Accesorios Cuero
('cinturones', 'Cinturones', 'accesorios_cuero', 'Casual, formal, reversible'),
('carteras', 'Carteras', 'accesorios_cuero', 'Billetera, clutch, sobre'),
('bolsos', 'Bolsos', 'accesorios_cuero', 'Tote, crossbody, mochila urbana'),
('mochilas', 'Mochilas', 'accesorios_cuero', 'Escolar, trekking, urbana'),

-- Calzado
('zapatillas', 'Zapatillas', 'calzado', 'Urbana, deportiva, running'),
('zapato_vestir', 'Zapato de vestir', 'calzado', 'Oxford, mocasín, tacón'),
('botas', 'Botas', 'calzado', 'Chelsea, trekking, lluvia'),
('bototos', 'Bototos', 'calzado', 'Trabajo, seguridad, moto'),
('pantuflas', 'Pantuflas', 'calzado', 'Casa, térmica, antideslizante'),
('chalas', 'Chalas / Sandalias', 'calzado', 'Playa, urbana, ortopédica'),

-- Joyería / Bijoutería
('aros', 'Aros', 'joyeria_bijouteria', 'Colgante, botón, argolla'),
('cadenas', 'Cadenas', 'joyeria_bijouteria', 'Gargantilla, larga, medallón'),
('collares', 'Collares', 'joyeria_bijouteria', 'Piedra, metal, artesanal'),
('pulseras', 'Pulseras', 'joyeria_bijouteria', 'Cadena, cuero, tejida'),
('anillos', 'Anillos', 'joyeria_bijouteria', 'Ajustable, talla fija, sello'),
('llaveros', 'Llaveros', 'joyeria_bijouteria', 'Metálico, cuero, artesanal'),
('prendedores', 'Prendedores / Broches', 'joyeria_bijouteria', 'Vintage, artesanal, temático'),
('bijouteria_artesana', 'Bijoutería artesana', 'joyeria_bijouteria', 'Piezas únicas, autoría local'),

-- Juguetes
('juguetes_bateria', 'Juguetes a batería', 'juguetes', 'Con control, robot, vehículo'),
('peluches', 'Peluches', 'juguetes', 'Pequeño, mediano, grande'),
('juegos_didacticos', 'Juegos didácticos', 'juguetes', 'Madera, plástico, magnético'),
('juguetes_madera', 'Juguetes de madera', 'juguetes', 'Rompecabezas, construcción'),
('munecos_accion', 'Muñecos de acción', 'juguetes', 'Licencia, articulado, vintage'),
('autos_juguete', 'Autos', 'juguetes', 'Die-cast, a control, pista'),
('otros_juguetes', 'Otros juguetes', 'juguetes', 'Categoría residual'),

-- Hogar / Cultura
('libros', 'Libros', 'hogar_cultura', 'Ficción, no ficción, infantil, académico'),
('revistas', 'Revistas', 'hogar_cultura', 'Moda, diseño, hobbies, vintage'),
('decoracion', 'Decoración', 'hogar_cultura', 'Cuadros, espejos, objetos'),
('lamparas', 'Lámparas', 'hogar_cultura', 'Mesa, pie, pared, vintage'),
('artesania_hogar', 'Artesanía', 'hogar_cultura', 'Cerámica, tejido, madera'),
('loza', 'Loza / Vajilla', 'hogar_cultura', 'Platos, tazas, juegos'),
('servicio', 'Servicio', 'hogar_cultura', 'Otros artículos de hogar'),

-- Bebé
('piluchos', 'Piluchos / Bodies', 'bebe', 'Manga corta, larga, sin mangas'),
('panties_bebe', 'Panties (bebé)', 'bebe', 'Cubrepañal, estampado'),
('enteritos', 'Enteritos', 'bebe', 'Mameluco, pijama enterizo'),
('pechera', 'Pechera / Babero', 'bebe', 'Tela, plástico, diseño');

-- Niveles de calidad
INSERT INTO niveles_calidad (codigo, nombre, canal_asignado, descripcion, criterios) VALUES
('marca', 'Como nueva de marca', 'online', 'Etiqueta original o sin uso aparente', '{"fotos": "profesional", "medidas": "exactas", "defectos": "ninguno"}'),
('boutique', 'Como nueva de boutique', 'online', 'Sin etiqueta pero sin uso', '{"fotos": "profesional", "medidas": "exactas", "defectos": "ninguno"}'),
('intervenida', 'Ropa intervenida', 'online', 'Reparada/alterada profesionalmente', '{"fotos": "profesional", "medidas": "exactas", "nota": "describir_intervencion"}'),
('primera_sel', 'Primera selección', 'feria', '+2 temporadas sin vender online', '{"precio": "reducido", "transparencia": "temporadas_en_inventario"}'),
('sin_marca', 'Sin marca, buen estado', 'feria', 'Detalles menores permitidos', '{"precio": "accesible", "nota": "detalles_menores"}'),
('donacion', 'Ropa donación', 'feria', 'Estado digno, funcional', '{"precio": "simbólico", "programa": "dignidad"}'),
('digna', 'Digna de portar', 'feria', 'Con detalles, sin hoyos', '{"precio": "accesible", "transparencia": "defectos_descritos"}'),
('retazo', 'Retazo de género', 'retazo', 'No viable para venta', '{"destino": "artesania_patchwork_relleno"}');

-- Temporadas
INSERT INTO temporadas (codigo, nombre, meses_inicio, meses_fin) VALUES
('primavera', 'Primavera', 9, 11),
('verano', 'Verano', 12, 2),
('otono', 'Otoño', 3, 5),
('invierno', 'Invierno', 6, 8),
('atemporal', 'Atemporal', NULL, NULL);

-- ============================================
-- SEED DATA: FERIAAPP/TOQUÍ (originales)
-- ============================================

INSERT INTO canales_venta (id, nombre, tipo, descripcion, activo, fecha_inicio, fecha_cierre, created_at) VALUES
(1,'Feria Dominical','feria_dominical','Puesto principal, todos los domingos',true,'2022-01-01',NULL,'2026-05-11 14:59:01'),
(2,'Feria Miércoles','feria_cerrada','Puesto miércoles, cerrado por decisión operativa',false,'2020-01-01','2023-12-31','2026-05-11 14:59:01'),
(3,'Feria Chic','feria_chic','Feria curada, moda seleccionada, cada 2 meses aprox',true,NULL,NULL,'2026-05-11 14:59:01'),
(4,'Feria Artesanal','feria_artesanal','Solo artesanía, cada 3 meses aprox',true,NULL,NULL,'2026-05-11 14:59:01'),
(5,'Feria Navideña','feria_navidena','Diciembre, formato libre curado',true,NULL,NULL,'2026-05-11 14:59:01'),
(6,'Venta Directa','presencial_directo','Venta presencial fuera del puesto: casa, trabajo, conocidos',true,NULL,NULL,'2026-05-15 22:12:55'),
(7,'Venta Online','online','Venta por WhatsApp, Instagram o delivery',true,NULL,NULL,'2026-05-15 22:12:55');

INSERT INTO categorias_producto (id, nombre, sector_puesto, tipo_origen, activo) VALUES
(1,'Alimentos Orgánicos','alimentos','propio',true),
(2,'Alimentos Comerciales','alimentos','reventa',true),
(3,'Moda','mujeres','donacion',true),
(4,'Artesanía','artesania','propio',true),
(5,'Antigüedades','fondo','donacion',true),
(6,'Otros','fondo','donacion',true),
(7,'Juguetes reciclados','infantil','donacion',true);

INSERT INTO subcategorias_producto (id, categoria_id, nombre, activo) VALUES
(1,1,'Frutas',true),(2,1,'Hortalizas',true),(3,1,'Hierbas',true),(4,1,'Huevos',true),(5,1,'Mermeladas',true),
(6,2,'Aceite de Oliva',true),(7,2,'Quesos',true),
(8,3,'Mujer',true),(9,3,'Hombre',true),(10,3,'Niños',true),
(11,4,'Aros',true),(12,4,'Pins',true),(13,4,'Carpintería',true),
(14,5,'Varios',true),
(15,6,'Libros',true),(16,6,'CDs',true),(17,6,'Vinilos',true),(18,6,'Casettes',true),(19,6,'Revistas',true),(20,6,'Varios',true),
(21,7,'Coleccionables',true),(22,7,'Bebés',true),(23,7,'Varios',true);

INSERT INTO categoria_canal (categoria_id, canal_id) VALUES
(1,1),(2,1),(3,1),(4,1),(5,1),(6,1),(7,1),
(1,2),(2,2),(3,2),(4,2),(5,2),(6,2),
(3,3),(4,3),(5,3),(7,3),
(4,4),(7,4),
(1,5),(2,5),(3,5),(4,5),(5,5),(6,5),(7,5),
(7,6),(7,7);

-- Productos originales (57 items)
INSERT INTO productos (id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id, unidad_medida, precio_fijo, precio_min, precio_max, tiene_rango, activo, notas, created_at) VALUES
(1,'Huevos Azules',1,4,'unidad',500,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(2,'Huevos Café Libre Pastoreo',1,4,'unidad',400,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(3,'Hierba Fresca',1,3,'atado',1000,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(4,'Hierba Secada',1,3,'atado',1500,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(5,'Laurel Secado',1,3,'atado',1500,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(6,'Mermelada Casera',1,5,'unidad',3000,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(7,'Tomate Cherry',1,2,'kg',2000,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(8,'Tomate Rosado',1,2,'kg',1500,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(9,'Tomate Pera',1,2,'kg',1500,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(10,'Cebolla Orgánica',1,2,'kg',1200,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(11,'Ajo Orgánico',1,2,'atado',1500,NULL,NULL,false,true,NULL,'2026-05-11 23:37:32'),
(12,'Aceite Oliva EVOO 500ml',2,6,'unidad',NULL,6000,7000,true,true,NULL,'2026-05-11 23:37:32'),
(13,'Aceite Oliva EVOO 1lt',2,6,'unidad',NULL,11000,12000,true,true,NULL,'2026-05-11 23:37:32'),
(14,'Queso Gauda',2,7,'kg',NULL,8000,10000,true,true,NULL,'2026-05-11 23:37:32'),
(15,'Queso Crema',2,7,'unidad',NULL,4000,5000,true,true,NULL,'2026-05-11 23:37:32'),
(16,'Blusa',3,8,'unidad',NULL,1000,5000,true,true,NULL,'2026-05-11 23:37:32'),
(17,'Polera Mujer',3,8,'unidad',NULL,1000,5000,true,true,NULL,'2026-05-11 23:37:32'),
(18,'Pantalón Mujer',3,8,'unidad',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(19,'Chaleco Mujer',3,8,'unidad',NULL,1000,6000,true,true,NULL,'2026-05-11 23:37:32'),
(20,'Poleron Mujer',3,8,'unidad',NULL,1000,6000,true,true,NULL,'2026-05-11 23:37:32'),
(21,'Chaqueta Mujer',3,8,'unidad',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(22,'Parca Mujer',3,8,'unidad',NULL,2000,10000,true,true,NULL,'2026-05-11 23:37:32'),
(23,'Ropa Deportiva Mujer',3,8,'unidad',NULL,1000,5000,true,true,NULL,'2026-05-11 23:37:32'),
(24,'Zapatos Mujer',3,8,'par',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(25,'Zapatillas Mujer',3,8,'par',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(26,'Botas Mujer',3,8,'par',NULL,2000,10000,true,true,NULL,'2026-05-11 23:37:32'),
(27,'Chal/Poncho',3,8,'unidad',NULL,1000,6000,true,true,NULL,'2026-05-11 23:37:32'),
(28,'Pañuelo/Bufanda',3,8,'unidad',NULL,500,3000,true,true,NULL,'2026-05-11 23:37:32'),
(29,'Ropa Íntima Mujer',3,8,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(30,'Camisa',3,9,'unidad',NULL,1000,6000,true,true,NULL,'2026-05-11 23:37:32'),
(31,'Polera Hombre',3,9,'unidad',NULL,1000,5000,true,true,NULL,'2026-05-11 23:37:32'),
(32,'Pantalón Hombre',3,9,'unidad',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(33,'Chaleco Hombre',3,9,'unidad',NULL,1000,6000,true,true,NULL,'2026-05-11 23:37:32'),
(34,'Poleron Hombre',3,9,'unidad',NULL,1000,6000,true,true,NULL,'2026-05-11 23:37:32'),
(35,'Chaqueta Hombre',3,9,'unidad',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(36,'Parca Hombre',3,9,'unidad',NULL,2000,10000,true,true,NULL,'2026-05-11 23:37:32'),
(37,'Ropa Deportiva Hombre',3,9,'unidad',NULL,1000,5000,true,true,NULL,'2026-05-11 23:37:32'),
(38,'Zapatos Hombre',3,9,'par',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(39,'Zapatillas Hombre',3,9,'par',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(40,'Botas Hombre',3,9,'par',NULL,2000,10000,true,true,NULL,'2026-05-11 23:37:32'),
(41,'Ropa Íntima Hombre',3,9,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(42,'Ropa Niños',3,10,'unidad',NULL,500,4000,true,true,NULL,'2026-05-11 23:37:32'),
(43,'Zapatos Niños',3,10,'par',NULL,500,4000,true,true,NULL,'2026-05-11 23:37:32'),
(44,'Ropa Deportiva Niños',3,10,'unidad',NULL,500,3000,true,true,NULL,'2026-05-11 23:37:32'),
(45,'Aros',4,11,'par',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(46,'Pins',4,12,'unidad',NULL,500,3000,true,true,NULL,'2026-05-11 23:37:32'),
(47,'Artesanía Madera',4,13,'unidad',NULL,3000,30000,true,true,NULL,'2026-05-11 23:37:32'),
(48,'Novela',6,15,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(49,'Diccionario',6,15,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(50,'Filosofía',6,15,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(51,'Historia',6,15,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(52,'Ciencia',6,15,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(53,'CD',6,16,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(54,'Vinilo',6,17,'unidad',NULL,1000,8000,true,true,NULL,'2026-05-11 23:37:32'),
(55,'Casette',6,18,'unidad',NULL,500,2000,true,true,NULL,'2026-05-11 23:37:32'),
(56,'Revista',6,19,'unidad',NULL,500,1000,true,true,NULL,'2026-05-11 23:37:32'),
(57,'Varios',6,20,'unidad',NULL,500,5000,true,true,NULL,'2026-05-11 23:37:32');

-- Usuarios
INSERT INTO usuarios (id, nombre, rol, password_hash, activo, created_at) VALUES
(1,'Claudio','propietario','$2y$10$t9ILnTUyV0Zi7MwRMzNYVuFzMoDYNZEkY4OwT8jP85vGChFEzFuOG',true,'2026-05-11 14:59:01'),
(2,'Nancy','esposa','$2y$10$9Pt59kldAzGNgDAE.2TDLOE5O.ueYDtOTg/6jqKplODZMYT/S/vy6',true,'2026-05-11 14:59:01');

-- Dispositivos
INSERT INTO dispositivos (id, usuario_id, nombre, tipo, ultimo_sync, activo, created_at) VALUES
(1,1,'Móvil Compartido','movil',NULL,true,'2026-05-11 22:39:31'),
(2,1,'Desktop Servidor','desktop','2026-06-02 00:33:42',true,'2026-05-11 14:59:02');

-- Reset sequences
SELECT setval('canales_venta_id_seq', 7, true);
SELECT setval('categorias_producto_id_seq', 7, true);
SELECT setval('subcategorias_producto_id_seq', 23, true);
SELECT setval('productos_id_seq', 57, true);
SELECT setval('usuarios_id_seq', 2, true);
SELECT setval('dispositivos_id_seq', 2, true);
SELECT setval('segmentos_edad_id_seq', 5, true);
SELECT setval('generos_id_seq', 3, true);
SELECT setval('categorias_ropa_id_seq', 50, true);
SELECT setval('niveles_calidad_id_seq', 8, true);
SELECT setval('temporadas_id_seq', 5, true);
