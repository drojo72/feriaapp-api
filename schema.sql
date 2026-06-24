-- ============================================
-- FERIAAPP v2 - PostgreSQL Schema
-- Migrado desde MySQL 8.0.46
-- ============================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================
-- 1. CANALES Y CATEGORÍAS
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
-- 2. USUARIOS Y DISPOSITIVOS (Auth v2)
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

-- Trigger: revocar tokens anteriores al crear uno nuevo
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
-- 3. PRODUCTOS (con nueva segmentación)
-- ============================================

CREATE TABLE productos (
    id              SERIAL PRIMARY KEY,
    uuid            UUID DEFAULT uuid_generate_v4() UNIQUE,
    nombre          VARCHAR(150) NOT NULL,
    categoria_id    INTEGER NOT NULL REFERENCES categorias_producto(id),
    subcategoria_id INTEGER REFERENCES subcategorias_producto(id),
    unidad_medida   VARCHAR(30) NOT NULL,

    -- Precios
    precio_fijo     INTEGER,
    precio_min      INTEGER,
    precio_max      INTEGER,
    tiene_rango     BOOLEAN DEFAULT FALSE,

    -- Nueva segmentación (nullable mientras migramos)
    genero          VARCHAR(20) CHECK (genero IN ('hombre','mujer','unisex','niño','niña','bebe')),
    segmento_edad   VARCHAR(20)[] DEFAULT '{}',
    canal_default   VARCHAR(20) DEFAULT 'feria',
    condicion       VARCHAR(30) CHECK (condicion IN (
        'como_nueva_marca','como_nueva_boutique','intervenida',
        'primera_seleccion','sin_marca','donacion','digna_portar','retazo'
    )),

    -- Stock y etiquetas
    estado          VARCHAR(20) DEFAULT 'disponible' CHECK (estado IN (
        'disponible','reservado','vendido','retazo','donado'
    )),
    etiqueta_id     VARCHAR(50) UNIQUE,
    fotos           JSONB DEFAULT '[]',

    activo          BOOLEAN DEFAULT TRUE,
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_productos_estado ON productos(estado);
CREATE INDEX idx_productos_etiqueta ON productos(etiqueta_id);
CREATE INDEX idx_productos_categoria ON productos(categoria_id);
CREATE INDEX idx_productos_condicion ON productos(condicion);

-- ============================================
-- 4. CLIENTES Y DEUDAS
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
-- 5. EVENTOS Y VENTAS
-- ============================================

CREATE TABLE eventos_feria (
    id              SERIAL PRIMARY KEY,
    canal_venta_id  INTEGER NOT NULL REFERENCES canales_venta(id),
    fecha           DATE NOT NULL,
    lugar           VARCHAR(150),
    vendedor_principal_id INTEGER NOT NULL REFERENCES usuarios(id),
    estado          VARCHAR(20) DEFAULT 'planificado' CHECK (estado IN ('planificado','activo','cerrado')),
    total_calculado INTEGER DEFAULT 0,
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE journal_ventas (
    id              SERIAL PRIMARY KEY,
    uuid            UUID DEFAULT uuid_generate_v4() UNIQUE,
    evento_feria_id INTEGER NOT NULL REFERENCES eventos_feria(id),
    usuario_id      INTEGER NOT NULL REFERENCES usuarios(id),
    dispositivo_id  INTEGER NOT NULL REFERENCES dispositivos(id),

    timestamp_local TIMESTAMPTZ NOT NULL,
    timestamp_sync  TIMESTAMPTZ,

    perfil_cliente  VARCHAR(20) DEFAULT 'sin_definir',
    producto_ancla_id INTEGER REFERENCES productos(id),

    forma_pago      VARCHAR(20) NOT NULL CHECK (forma_pago IN (
        'efectivo','transferencia','diferido','debito','credito','trueque'
    )),
    estado_pago     VARCHAR(20) DEFAULT 'pagado' CHECK (estado_pago IN ('pagado','mora','pendiente','trueque')),
    cliente_frecuente_id INTEGER REFERENCES clientes_frecuentes(id),

    venta_directa_sin_bodega BOOLEAN DEFAULT FALSE,
    garantia_devolucion     BOOLEAN DEFAULT FALSE,

    total_venta     INTEGER NOT NULL DEFAULT 0,

    sync_estado     VARCHAR(20) DEFAULT 'pendiente' CHECK (sync_estado IN ('pendiente','sincronizado','conflicto')),
    notas           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE lineas_venta (
    id              SERIAL PRIMARY KEY,
    venta_id        INTEGER NOT NULL REFERENCES journal_ventas(id) ON DELETE CASCADE,
    producto_id     INTEGER REFERENCES productos(id),
    item_donacion_id INTEGER,
    cantidad        NUMERIC(8,2) NOT NULL DEFAULT 1.00,
    precio_unitario INTEGER NOT NULL,
    subtotal        INTEGER NOT NULL,
    notas           TEXT
);

-- ============================================
-- 6. EGRESOS E INSUMOS (Granja Toquí)
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
-- 7. DONACIONES
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
-- 8. SYNC Y AUDITORÍA
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
-- 9. PRECIOS STANDARD POR CANAL
-- ============================================

CREATE TABLE precios_standard (
    id              SERIAL PRIMARY KEY,
    producto_id     INTEGER NOT NULL REFERENCES productos(id),
    canal           VARCHAR(20) NOT NULL CHECK (canal IN ('online','feria','retazo')),
    precio_standard INTEGER NOT NULL,
    moneda          VARCHAR(3) DEFAULT 'CLP',
    vigente_desde   DATE NOT NULL,
    vigente_hasta   DATE,
    UNIQUE (producto_id, canal, vigente_desde)
);

-- ============================================
-- 10. OFERTAS CRUZADAS (Keysign Labs)
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
-- SEED DATA (migrado desde MySQL)
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

INSERT INTO productos (id, nombre, categoria_id, subcategoria_id, unidad_medida, precio_fijo, precio_min, precio_max, tiene_rango, activo, notas, created_at) VALUES
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

INSERT INTO usuarios (id, nombre, rol, password_hash, activo, created_at) VALUES
(1,'Claudio','propietario','$2y$10$t9ILnTUyV0Zi7MwRMzNYVuFzMoDYNZEkY4OwT8jP85vGChFEzFuOG',true,'2026-05-11 14:59:01'),
(2,'Nancy','esposa','$2y$10$9Pt59kldAzGNgDAE.2TDLOE5O.ueYDtOTg/6jqKplODZMYT/S/vy6',true,'2026-05-11 14:59:01');

INSERT INTO dispositivos (id, usuario_id, nombre, tipo, ultimo_sync, activo, created_at) VALUES
(1,1,'Móvil Compartido','movil',NULL,true,'2026-05-11 22:39:31'),
(2,1,'Desktop Servidor','desktop','2026-06-02 00:33:42',true,'2026-05-11 14:59:02');

SELECT setval('canales_venta_id_seq', 7, true);
SELECT setval('categorias_producto_id_seq', 7, true);
SELECT setval('subcategorias_producto_id_seq', 23, true);
SELECT setval('productos_id_seq', 57, true);
SELECT setval('usuarios_id_seq', 2, true);
SELECT setval('dispositivos_id_seq', 2, true);
