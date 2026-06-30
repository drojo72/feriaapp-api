# DICCIONARIO DE DATOS - FERIAAPP v2.1

> ⚠️ **NOTA IMPORTANTE:** Este archivo es un **resumen de snapshot** de v2.1.
>
> **Diccionario Canonical Modular:** Pendiente — se organizará en archivos Markdown por tabla.
>
> El diccionario canonical estará organizado de forma **modular** con un archivo Markdown por tabla, facilitando:
> - ✅ Edición específica sin cargar documentos masivos
> - ✅ Versionado granular por tabla
> - ✅ Links cruzados entre tablas relacionadas
> - ✅ Mantenimiento incremental

**Versión:** 2.1 (Migración PostgreSQL + Schema extendido)
**Fecha:** 2026-06-25
**Base de Datos:** feriaapp_db
**Motor:** PostgreSQL 16 (Neon)
**Charset:** UTF-8
**Sistema:** FeriaApp — Gestión unificada de Granja Toquí, Re-Vistete, Feria Dominical y ventas online/directas

---

## 📊 RESUMEN EJECUTIVO

### Estadísticas Generales

| Métrica | Valor |
|---------|-------|
| **Total de tablas** | 30 |
| **Total de vistas** | 2 |
| **Total de campos** | ~270 |
| **Total de índices** | 65 |
| **Total de Foreign Keys** | ~35 |
| **Total de registros** | ~85 |
| **Tamaño total** | ~1.2 MB |
| **Tablas pobladas** | 14 |
| **Tablas con estructura solamente** | 12 |
| **Functions** | 5 (negocio) + 45 (pgcrypto/uuid-ossp) |
| **Triggers** | 4 |

### Distribución por Módulos

| Módulo | Tablas | Estado | Descripción |
|--------|--------|--------|-------------|
| **🧑‍🌾 Usuarios & Dispositivos** | 3 | ✅ Activo | Autenticación, usuarios, dispositivos móviles/desktop |
| **🏪 Canales de Venta** | 1 | ✅ Poblado | Feria, online, directo, marketplace |
| **📦 Productos & Catálogo** | 9 | ✅ Poblado | Categorías, subcategorías, productos, precios, calidad |
| **💰 Ventas & Transacciones** | 4 | ✅ Activo | Eventos, journal de ventas, líneas, rebajas |
| **💸 Egresos & Insumos** | 2 | 🟡 Estructura | Compras, gastos operacionales |
| **🤝 Clientes & Deudas** | 2 | 🟡 Estructura | Clientes frecuentes, deudas diferidas |
| **🏷️ Etiquetas & Tracking** | 2 | 🟡 Estructura | Códigos QR/barras/RFID, flujo de prendas |
| **🔄 Sincronización & Seguridad** | 3 | ✅ Operativo | Sync log, refresh tokens, reclasificación |
| **🎁 Donaciones** | 2 | 🟡 Estructura | Recepción y clasificación de donaciones |
| **🎯 Cross-selling** | 1 | 🟡 Estructura | Ofertas cruzadas entre proyectos Keysign Labs |
| **🔗 Relaciones** | 1 | ✅ Poblado | Categoría-canal (tabla pivote) |

---

## 🧑‍🌾 MÓDULO: USUARIOS & DISPOSITIVOS

### Tablas (3):

#### 1. **usuarios** — ✅ Activo (2 usuarios)
Tabla principal de usuarios del sistema. Roles familiares para operación de feria/granja.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK autoincremental |
| `uuid` | uuid | YES | gen_random_uuid() | UUID global único |
| `nombre` | varchar(100) | NO | — | Nombre del usuario |
| `rol` | varchar(20) | NO | — | Rol: propietario, esposa, hija_mayor, hija_menor, externo |
| `password_hash` | varchar(255) | NO | — | Hash BCrypt de contraseña |
| `activo` | boolean | YES | true | Estado activo/inactivo |
| `created_at` | timestamptz | YES | now() | Fecha de creación |

**CHECK:** `rol` ∈ {propietario, esposa, hija_mayor, hija_menor, externo}

**Índices:**
- PRIMARY KEY (`id`)
- UNIQUE (`uuid`)

**Registros actuales:**
- ID 1: Claudio (propietario)
- ID 2: Nancy (esposa)

---

#### 2. **dispositivos** — ✅ Activo (2 dispositivos)
Dispositivos autorizados para registrar transacciones (móvil compartido, desktop servidor).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK autoincremental |
| `uuid` | uuid | YES | gen_random_uuid() | UUID del dispositivo |
| `usuario_id` | integer | NO | — | FK → usuarios.id (propietario) |
| `nombre` | varchar(100) | NO | — | Nombre descriptivo |
| `tipo` | varchar(20) | NO | — | movil / desktop |
| `platform` | varchar(20) | YES | — | Plataforma (android, ios, linux, etc.) |
| `public_key` | text | YES | — | Clave pública para verificación |
| `ultimo_sync` | timestamptz | YES | — | Última sincronización |
| `confianza` | integer | YES | 0 | Nivel de confianza (0-100) |
| `revocado` | boolean | YES | false | Dispositivo revocado |
| `created_at` | timestamptz | YES | now() | Fecha de registro |

**CHECK:** `tipo` ∈ {movil, desktop}

**FK:** `usuario_id` → `usuarios(id)` ON DELETE CASCADE

**Índices:**
- PRIMARY KEY (`id`)
- UNIQUE (`uuid`)

**Registros actuales:**
- ID 1: Móvil Compartido (usuario 1)
- ID 2: Desktop Servidor (usuario 1)

---

#### 3. **refresh_tokens** — ✅ Operativo (0 tokens activos)
Tokens de refresco para autenticación JWT. Sistema de revocación automática.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `dispositivo_id` | integer | NO | — | FK → dispositivos.id |
| `token_hash` | varchar(255) | NO | — | Hash SHA-256 del token |
| `expira_en` | timestamptz | NO | — | Fecha de expiración |
| `usado_en` | timestamptz | YES | — | Fecha de primer uso |
| `revocado` | boolean | YES | false | Estado de revocación |
| `ip_origen` | inet | YES | — | IP de origen |
| `user_agent` | text | YES | — | User agent del navegador |
| `created_at` | timestamptz | YES | now() | Fecha de creación |

**FK:** `dispositivo_id` → `dispositivos(id)` ON DELETE CASCADE

**Trigger:** `trg_revocar_tokens_anteriores` (AFTER INSERT) — revoca tokens previos del mismo dispositivo

**Índices:**
- PRIMARY KEY (`id`)

---

## 🏪 MÓDULO: CANALES DE VENTA

### Tablas (1):

#### 4. **canales_venta** — ✅ Poblado (7 canales)
Canales donde se realizan ventas. Cubre ferias, online, presencial y marketplace.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `nombre` | varchar(100) | NO | — | Nombre del canal |
| `tipo` | varchar(30) | NO | — | Tipo de canal |
| `descripcion` | text | YES | — | Descripción detallada |
| `activo` | boolean | YES | true | Canal activo |
| `fecha_inicio` | date | YES | — | Fecha de apertura |
| `fecha_cierre` | date | YES | — | Fecha de cierre (si aplica) |
| `created_at` | timestamptz | YES | now() | Fecha de creación |

**CHECK:** `tipo` ∈ {feria_dominical, feria_chic, feria_artesanal, feria_navidena, feria_cerrada, instagram, marketplace, presencial_stgo, presencial_directo, online}

**Índices:**
- PRIMARY KEY (`id`)

**Canales actuales:**
- feria_dominical, feria_chic, feria_artesanal, feria_navidena, feria_cerrada
- instagram, marketplace
- presencial_stgo, presencial_directo, online

---

## 📦 MÓDULO: PRODUCTOS & CATÁLOGO

### Tablas (9):

#### 5. **categorias_producto** — ✅ Poblado (~8 categorías)
Categorías principales de productos por sector de puesto y origen.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `nombre` | varchar(100) | NO | — | Nombre de categoría |
| `sector_puesto` | varchar(20) | NO | — | Sector físico del puesto |
| `tipo_origen` | varchar(20) | NO | — | Origen del producto |
| `activo` | boolean | YES | true | Activo |

**CHECK:** `sector_puesto` ∈ {infantil, alimentos, hombres, mujeres, accesorios, fondo, artesania, sin_sector}
**CHECK:** `tipo_origen` ∈ {propio, vecino, reventa, donacion, huerta}

**Índices:** PRIMARY KEY (`id`)

---

#### 6. **subcategorias_producto** — ✅ Poblado (~10 subcategorías)
Subcategorías dentro de cada categoría principal.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `categoria_id` | integer | NO | — | FK → categorias_producto.id |
| `nombre` | varchar(100) | NO | — | Nombre de subcategoría |
| `activo` | boolean | YES | true | Activo |

**FK:** `categoria_id` → `categorias_producto(id)` ON DELETE CASCADE
**Índices:** PRIMARY KEY (`id`)

---

#### 7. **categorias_ropa** — ✅ Poblado (61 categorías)
Sistema de categorización específico para Re-Vistete (ropa reciclada/artesanal).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `codigo` | varchar(30) | NO | — | Código único (ej: BLUSA_MUJER) |
| `nombre` | varchar(100) | NO | — | Nombre descriptivo |
| `grupo` | varchar(50) | NO | — | Grupo funcional |
| `descripcion` | text | YES | — | Descripción |
| `activo` | boolean | YES | true | Activo |

**CHECK:** `grupo` ∈ {ropa_base, accesorios_textiles, accesorios_cuero, calzado, joyeria_bijouteria, juguetes, hogar_cultura, bebe}

**Índices:**
- PRIMARY KEY (`id`)
- UNIQUE (`codigo`)
- INDEX (`activo`)
- INDEX (`grupo`)

---

#### 8. **subcategorias_ropa** — ✅ Poblado (0 registros — pendiente migración)
Subcategorías de ropa para clasificación fina.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `categoria_id` | integer | NO | — | FK → categorias_ropa.id |
| `codigo` | varchar(30) | NO | — | Código único |
| `nombre` | varchar(100) | NO | — | Nombre |
| `especificaciones` | text | YES | — | Especificaciones técnicas |
| `activo` | boolean | YES | true | Activo |

**FK:** `categoria_id` → `categorias_ropa(id)` ON DELETE CASCADE
**Índices:** PRIMARY KEY (`id`), UNIQUE (`codigo`), INDEX (`activo`), INDEX (`categoria_id`)

---

#### 9. **generos** — ✅ Poblado (3 géneros)
Clasificación por género para productos de vestuario.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `codigo` | varchar(20) | NO | — | Código: hombre, mujer, unisex, nino, nina, bebe |
| `nombre` | varchar(50) | NO | — | Nombre descriptivo |
| `activo` | boolean | YES | true | Activo |

**Índices:** PRIMARY KEY (`id`), UNIQUE (`codigo`)

---

#### 10. **segmentos_edad** — ✅ Poblado (5 segmentos)
Segmentos de edad para clasificación de productos.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `codigo` | varchar(20) | NO | — | Código único |
| `nombre` | varchar(50) | NO | — | Nombre (ej: Adulto, Niño, Bebé) |
| `rango_anios` | varchar(30) | YES | — | Rango de edad en años |
| `activo` | boolean | YES | true | Activo |

**Índices:** PRIMARY KEY (`id`), UNIQUE (`codigo`)

---

#### 11. **niveles_calidad** — ✅ Poblado (8 niveles)
Niveles de calidad que determinan canal de venta asignado.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `codigo` | varchar(30) | NO | — | Código único |
| `nombre` | varchar(100) | NO | — | Nombre (ej: Primera Selección, Como Nueva) |
| `canal_asignado` | varchar(20) | NO | — | Canal recomendado: online, feria, retazo |
| `descripcion` | text | YES | — | Descripción |
| `criterios` | text | YES | — | Criterios de evaluación |
| `activo` | boolean | YES | true | Activo |

**CHECK:** `canal_asignado` ∈ {online, feria, retazo}

**Índices:** PRIMARY KEY (`id`), UNIQUE (`codigo`), INDEX (`canal_asignado`)

---

#### 12. **temporadas** — ✅ Poblado (5 temporadas)
Temporadas para rotación de inventario y pricing.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `codigo` | varchar(20) | NO | — | Código único (PRI, VER, OTO, INV, TOD) |
| `nombre` | varchar(50) | NO | — | Nombre (Primavera, Verano, etc.) |
| `meses_inicio` | integer | YES | — | Mes de inicio (1-12) |
| `meses_fin` | integer | YES | — | Mes de fin (1-12) |
| `activo` | boolean | YES | true | Activo |

**Índices:** PRIMARY KEY (`id`), UNIQUE (`codigo`)

---

#### 13. **productos** — ✅ Poblado (57 productos)
Catálogo maestro de productos. Soporta múltiples precios por canal.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `uuid` | uuid | YES | gen_random_uuid() | UUID único |
| `nombre` | varchar(150) | NO | — | Nombre del producto |
| `categoria_feriaapp_id` | integer | NO | — | FK → categorias_producto |
| `subcategoria_feriaapp_id` | integer | YES | — | FK → subcategorias_producto |
| `unidad_medida` | varchar(30) | NO | — | Unidad: unidad, kg, litro, metro, etc. |
| `precio_fijo` | integer | YES | — | Precio fijo (si aplica) |
| `precio_min` | integer | YES | — | Precio mínimo (para rangos) |
| `precio_max` | integer | YES | — | Precio máximo (para rangos) |
| `tiene_rango` | boolean | YES | false | Usa rango de precios |
| `genero` | varchar(20) | YES | — | Género (legacy, usar genero_id) |
| `segmento_edad` | varchar[] | YES | {} | Array de segmentos (legacy) |
| `canal_default` | varchar(20) | YES | 'feria' | Canal por defecto |
| `condicion` | varchar(30) | YES | — | Estado físico: como_nueva_marca, como_nueva_boutique, intervenida, primera_seleccion, sin_marca, donacion, digna_portar, retazo |
| `estado` | varchar(20) | YES | 'disponible' | Estado: disponible, reservado, vendido, retazo, donado, en_evaluacion |
| `etiqueta_id` | varchar(50) | YES | — | Código de etiqueta física |
| `fotos` | jsonb | YES | [] | Array de URLs de fotos |
| `activo` | boolean | YES | true | Activo |
| `notas` | text | YES | — | Notas generales |
| `created_at` | timestamptz | YES | now() | Creación |
| `updated_at` | timestamptz | YES | now() | Última actualización (trigger) |
| `codigo_barras` | varchar(50) | YES | — | Código de barras |
| `categoria_revistete_id` | integer | YES | — | FK → categorias_ropa |
| `subcategoria_revistete_id` | integer | YES | — | FK → subcategorias_ropa |
| `genero_id` | integer | YES | — | FK → generos |
| `segmento_edad_id` | integer | YES | — | FK → segmentos_edad |
| `talla` | varchar(20) | YES | — | Talla alfabética (S, M, L, XL) |
| `talla_numerica` | integer | YES | — | Talla numérica |
| `medidas` | jsonb | YES | — | Medidas en JSON (pecho, cintura, largo) |
| `precio_online` | integer | YES | — | Precio para canal online |
| `precio_feria` | integer | YES | — | Precio para canal feria |
| `precio_standard` | integer | YES | — | Precio base estándar |
| `precio_final` | integer | YES | — | Precio final calculado |
| `nivel_calidad_id` | integer | YES | — | FK → niveles_calidad |
| `temporada_id` | integer | YES | — | FK → temporadas |
| `temporadas_en_inventario` | integer | YES | 0 | Contador de temporadas transcurridas |
| `descripcion_defectos` | text | YES | — | Descripción de defectos/detalles |
| `marca` | varchar(100) | YES | — | Marca del producto |
| `evaluado_por_id` | integer | YES | — | FK → usuarios (quién evaluó) |
| `fecha_evaluacion` | timestamptz | YES | — | Fecha de evaluación de calidad |

**CHECK:** `condicion` ∈ {como_nueva_marca, como_nueva_boutique, intervenida, primera_seleccion, sin_marca, donacion, digna_portar, retazo}
**CHECK:** `estado` ∈ {disponible, reservado, vendido, retazo, donado, en_evaluacion}
**CHECK:** `genero` ∈ {hombre, mujer, unisex, nino, nina, bebe}

**FKs:**
- `categoria_feriaapp_id` → `categorias_producto(id)`
- `subcategoria_feriaapp_id` → `subcategorias_producto(id)`
- `categoria_revistete_id` → `categorias_ropa(id)`
- `subcategoria_revistete_id` → `subcategorias_ropa(id)`
- `genero_id` → `generos(id)`
- `segmento_edad_id` → `segmentos_edad(id)`
- `nivel_calidad_id` → `niveles_calidad(id)`
- `temporada_id` → `temporadas(id)`
- `evaluado_por_id` → `usuarios(id)`

**Triggers:**
- `trg_productos_updated_at` (BEFORE UPDATE) — actualiza `updated_at`
- `trg_temporada_inventario` (BEFORE UPDATE) — incrementa `temporadas_en_inventario` si cambia `temporada_id`

**Índices:**
- PRIMARY KEY (`id`)
- UNIQUE (`uuid`), UNIQUE (`codigo_barras`), UNIQUE (`etiqueta_id`)
- INDEX (`categoria_feriaapp_id`), INDEX (`categoria_revistete_id`)
- INDEX (`codigo_barras`), INDEX (`condicion`), INDEX (`estado`)
- INDEX (`etiqueta_id`), INDEX (`genero_id`), INDEX (`nivel_calidad_id`)
- INDEX (`segmento_edad_id`)

**Function relacionada:** `calcular_precio_sugerido(producto_id, canal)` — calcula precio según canal y temporadas en inventario

---

#### 14. **precios_standard** — ✅ Poblado (0 registros — pendiente migración)
Historial de precios estándar por producto y canal con vigencia.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `producto_id` | integer | NO | — | FK → productos.id |
| `canal` | varchar(20) | NO | — | online / feria / retazo |
| `precio_standard` | integer | NO | — | Precio estándar en CLP |
| `moneda` | varchar(3) | YES | 'CLP' | Moneda |
| `vigente_desde` | date | NO | — | Fecha inicio vigencia |
| `vigente_hasta` | date | YES | — | Fecha fin vigencia (NULL = indefinido) |

**CHECK:** `canal` ∈ {online, feria, retazo}

**FK:** `producto_id` → `productos(id)`
**Índices:** PRIMARY KEY (`id`), UNIQUE (`producto_id`, `canal`, `vigente_desde`), INDEX (`producto_id`), INDEX (`vigente_desde`, `vigente_hasta`)

---

#### 15. **categoria_canal** — ✅ Poblado (tabla pivote)
Relación muchos-a-muchos entre categorías de producto y canales de venta.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `categoria_id` | integer | NO | — | FK → categorias_producto.id |
| `canal_id` | integer | NO | — | FK → canales_venta.id |

**PK compuesta:** (`categoria_id`, `canal_id`)
**FKs:**
- `categoria_id` → `categorias_producto(id)` ON DELETE CASCADE
- `canal_id` → `canales_venta(id)` ON DELETE CASCADE

---

## 💰 MÓDULO: VENTAS & TRANSACCIONES

### Tablas (4):

#### 16. **eventos_feria** — ✅ Activo (3 eventos reconstruidos)
Eventos de venta (días de feria, ventas online, ventas directas).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `canal_venta_id` | integer | NO | — | FK → canales_venta.id |
| `fecha` | date | NO | — | Fecha del evento |
| `lugar` | varchar(150) | YES | — | Lugar físico o plataforma |
| `vendedor_principal_id` | integer | NO | — | FK → usuarios.id |
| `estado` | varchar(20) | YES | 'activo' | planificado / activo / cerrado |
| `total_calculado` | integer | YES | 0 | Total calculado del sistema |
| `notas` | text | YES | — | Notas del evento |
| `created_at` | timestamptz | YES | now() | Creación |
| `total_confirmado` | integer | YES | — | Total confirmado manualmente |
| `diferencia` | integer | YES | — | Diferencia calculado vs confirmado |
| `revisado_por_id` | integer | YES | — | FK → usuarios.id (quién cerró) |
| `fecha_revision` | timestamptz | YES | — | Fecha de revisión/cierre |
| `fecha_cierre` | timestamptz | YES | — | Fecha de cierre oficial |

**CHECK:** `estado` ∈ {planificado, activo, cerrado}

**FKs:**
- `canal_venta_id` → `canales_venta(id)`
- `vendedor_principal_id` → `usuarios(id)`
- `revisado_por_id` → `usuarios(id)`

**Trigger:** `trg_validar_cierre_evento` (BEFORE UPDATE) — valida que cierre tenga revisado_por_id y total_confirmado

**Índices:** PRIMARY KEY (`id`)

---

#### 17. **journal_ventas** — ✅ Activo (3 ventas reconstruidas)
Registro maestro de cada venta individual. Journal inmutable.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `uuid` | uuid | YES | gen_random_uuid() | UUID único de venta |
| `evento_feria_id` | integer | NO | — | FK → eventos_feria.id |
| `usuario_id` | integer | NO | — | FK → usuarios.id (quién registró) |
| `dispositivo_id` | integer | NO | — | FK → dispositivos.id |
| `timestamp_local` | timestamptz | NO | — | Timestamp en dispositivo |
| `timestamp_sync` | timestamptz | YES | — | Timestamp de sincronización |
| `perfil_cliente` | varchar(20) | YES | 'sin_definir' | Perfil del cliente |
| `producto_ancla_id` | integer | YES | — | FK → productos.id (producto principal) |
| `forma_pago` | varchar(20) | NO | — | efectivo / transferencia / diferido / debito / credito / trueque |
| `estado_pago` | varchar(20) | YES | 'pagado' | pagado / mora / pendiente / trueque |
| `cliente_frecuente_id` | integer | YES | — | FK → clientes_frecuentes.id |
| `venta_directa_sin_bodega` | boolean | YES | false | Venta directa sin control de stock |
| `garantia_devolucion` | boolean | YES | false | Tiene garantía de devolución |
| `total_venta` | integer | NO | 0 | Total final de la venta |
| `sync_estado` | varchar(20) | YES | 'pendiente' | pendiente / sincronizado / conflicto |
| `notas` | text | YES | — | Notas de la venta |
| `created_at` | timestamptz | YES | now() | Creación |
| `precio_standard_total` | integer | YES | — | Suma de precios estándar |
| `precio_final_total` | integer | NO | 0 | Suma de precios finales |
| `diferencia_rebaja` | integer | YES | — | Total rebajado (negativo) |
| `porcentaje_rebaja` | numeric(5,2) | YES | — | Porcentaje de rebaja promedio |
| `tipo_rebaja` | varchar(30) | YES | — | Tipo de rebaja aplicada |
| `motivo_rebaja` | text | YES | — | Motivo detallado de rebaja |
| `aprobado_por_id` | integer | YES | — | FK → usuarios.id (quién aprobó rebaja) |

**CHECKs:**
- `forma_pago` ∈ {efectivo, transferencia, diferido, debito, credito, trueque}
- `estado_pago` ∈ {pagado, mora, pendiente, trueque}
- `sync_estado` ∈ {pendiente, sincronizado, conflicto}
- `tipo_rebaja` ∈ {ninguna, rebaja_cliente_frecuente, compra_masiva, prenda_especial, promocion_temporal, error_correccion, mora_negociada, trueque_valor_menor, otro}
- `perfil_cliente` ∈ {clase_media, obrero, sin_definir}

**FKs:**
- `evento_feria_id` → `eventos_feria(id)`
- `usuario_id` → `usuarios(id)`
- `dispositivo_id` → `dispositivos(id)`
- `producto_ancla_id` → `productos(id)`
- `cliente_frecuente_id` → `clientes_frecuentes(id)`
- `aprobado_por_id` → `usuarios(id)`

**Índices:** PRIMARY KEY (`id`), UNIQUE (`uuid`)

---

#### 18. **lineas_venta** — ✅ Activo (3 líneas reconstruidas)
Líneas individuales de cada venta (un producto por línea).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `venta_id` | integer | NO | — | FK → journal_ventas.id |
| `producto_id` | integer | YES | — | FK → productos.id |
| `item_donacion_id` | integer | YES | — | FK → items_donacion.id (si es donación) |
| `cantidad` | numeric(8,2) | NO | 1.00 | Cantidad vendida |
| `precio_unitario_final` | integer | NO | — | Precio unitario final |
| `subtotal` | integer | NO | — | Subtotal (cantidad × precio) |
| `notas` | text | YES | — | Notas de la línea |
| `precio_unitario_standard` | integer | YES | — | Precio estándar original |

**FKs:**
- `venta_id` → `journal_ventas(id)` ON DELETE CASCADE
- `producto_id` → `productos(id)`
- `item_donacion_id` → `items_donacion(id)`

**Índices:** PRIMARY KEY (`id`)

---

#### 19. **venta_rebajas** — ✅ Activo (1 rebaja reconstruida)
Registro de rebajas aplicadas a ventas.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `venta_id` | integer | NO | — | FK → journal_ventas.id |
| `linea_venta_id` | integer | YES | — | FK → lineas_venta.id |
| `precio_standard` | integer | NO | — | Precio antes de rebaja |
| `precio_final` | integer | NO | — | Precio después de rebaja |
| `diferencia` | integer | YES | GENERATED | precio_final - precio_standard (automático) |
| `tipo_rebaja` | varchar(30) | YES | 'ninguna' | Tipo de rebaja |
| `porcentaje_rebaja` | numeric(5,2) | YES | GENERATED | % de rebaja (automático) |
| `nota_rebaja` | text | YES | — | Nota explicativa |
| `aprobado_por_id` | integer | YES | — | FK → usuarios.id |
| `fecha_registro` | timestamptz | YES | now() | Fecha de registro |

**CHECK:** `tipo_rebaja` ∈ {ninguna, rebaja_cliente_frecuente, compra_masiva, prenda_especial, promocion_temporal, error_correccion, mora_negociada, trueque_valor_menor, otro}

**FKs:**
- `venta_id` → `journal_ventas(id)` ON DELETE CASCADE
- `linea_venta_id` → `lineas_venta(id)`
- `aprobado_por_id` → `usuarios(id)`

**Índices:** PRIMARY KEY (`id`), INDEX (`venta_id`), INDEX (`linea_venta_id`)

---

## 💸 MÓDULO: EGRESOS & INSUMOS

### Tablas (2):

#### 20. **journal_egresos** — 🟡 Estructura (0 registros)
Registro de egresos/gastos operacionales.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `fecha` | date | NO | — | Fecha del egreso |
| `usuario_id` | integer | NO | — | FK → usuarios.id |
| `dispositivo_id` | integer | NO | — | FK → dispositivos.id |
| `tipo` | varchar(20) | NO | — | compra_reventa / compra_vecinos / otro |
| `proveedor` | varchar(150) | YES | — | Nombre del proveedor |
| `producto_id` | integer | YES | — | FK → productos.id |
| `descripcion` | text | YES | — | Descripción |
| `cantidad` | numeric(8,2) | YES | — | Cantidad |
| `precio_unitario` | integer | YES | — | Precio unitario |
| `total` | integer | NO | — | Total del egreso |
| `forma_pago` | varchar(20) | NO | — | efectivo / transferencia |
| `notas` | text | YES | — | Notas |
| `sync_estado` | varchar(20) | YES | 'pendiente' | Estado de sync |
| `timestamp_local` | timestamptz | NO | — | Timestamp local |
| `timestamp_sync` | timestamptz | YES | — | Timestamp de sync |
| `created_at` | timestamptz | YES | now() | Creación |

**CHECK:** `tipo` ∈ {compra_reventa, compra_vecinos, otro}
**CHECK:** `forma_pago` ∈ {efectivo, transferencia}

**FKs:** `usuario_id` → `usuarios(id)`, `dispositivo_id` → `dispositivos(id)`, `producto_id` → `productos(id)`
**Índices:** PRIMARY KEY (`id`)

---

#### 21. **journal_insumos** — 🟡 Estructura (0 registros)
Registro de compras de insumos para Granja Toquí.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `fecha` | date | NO | — | Fecha |
| `usuario_id` | integer | NO | — | FK → usuarios.id |
| `dispositivo_id` | integer | NO | — | FK → dispositivos.id |
| `tipo` | varchar(30) | NO | — | alimento_gallinas / reposicion_gallinas / infraestructura / plantines_semillas / otro |
| `descripcion` | text | NO | — | Descripción |
| `monto` | integer | NO | — | Monto en CLP |
| `forma_pago` | varchar(20) | NO | — | efectivo / transferencia |
| `notas` | text | YES | — | Notas |
| `sync_estado` | varchar(20) | YES | 'pendiente' | Estado de sync |
| `timestamp_local` | timestamptz | NO | — | Timestamp local |
| `timestamp_sync` | timestamptz | YES | — | Timestamp de sync |
| `created_at` | timestamptz | YES | now() | Creación |

**CHECK:** `tipo` ∈ {alimento_gallinas, reposicion_gallinas, infraestructura, plantines_semillas, otro}
**CHECK:** `forma_pago` ∈ {efectivo, transferencia}

**FKs:** `usuario_id` → `usuarios(id)`, `dispositivo_id` → `dispositivos(id)`
**Índices:** PRIMARY KEY (`id`)

---

## 🤝 MÓDULO: CLIENTES & DEUDAS

### Tablas (2):

#### 22. **clientes_frecuentes** — 🟡 Estructura (0 registros)
Clientes recurrentes para seguimiento y rebajas automáticas.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `nombre` | varchar(100) | NO | — | Nombre del cliente |
| `contacto` | varchar(100) | YES | — | Teléfono/email |
| `perfil` | varchar(20) | YES | 'sin_definir' | clase_media / obrero / sin_definir |
| `producto_preferido_id` | integer | YES | — | FK → productos.id |
| `activo` | boolean | YES | true | Activo |
| `notas` | text | YES | — | Notas |
| `created_at` | timestamptz | YES | now() | Creación |

**CHECK:** `perfil` ∈ {clase_media, obrero, sin_definir}
**FK:** `producto_preferido_id` → `productos(id)`
**Índices:** PRIMARY KEY (`id`)

---

#### 23. **deudas_diferidas** — 🟡 Estructura (0 registros)
Registro de ventas a crédito/diferido.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `cliente_id` | integer | NO | — | FK → clientes_frecuentes.id |
| `venta_id` | integer | YES | — | FK → journal_ventas.id |
| `monto` | integer | NO | — | Monto adeudado |
| `fecha_venta` | date | NO | — | Fecha original de venta |
| `fecha_saldado` | date | YES | — | Fecha de pago completo |
| `estado` | varchar(20) | YES | 'pendiente' | pendiente / saldado |
| `notas` | text | YES | — | Notas |

**CHECK:** `estado` ∈ {pendiente, saldado}
**FKs:** `cliente_id` → `clientes_frecuentes(id)`, `venta_id` → `journal_ventas(id)`
**Índices:** PRIMARY KEY (`id`)

---

## 🏷️ MÓDULO: ETIQUETAS & TRACKING

### Tablas (2):

#### 24. **etiquetas** — 🟡 Estructura (0 registros)
Etiquetas físicas (QR, código de barras, RFID) para tracking de productos.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `producto_id` | integer | NO | — | FK → productos.id |
| `tipo_codigo` | varchar(20) | NO | — | qr / barcode / rfid |
| `codigo` | varchar(100) | NO | — | Código único |
| `formato_data` | text | YES | — | Datos codificados |
| `impresa` | boolean | YES | false | ¿Ya impresa? |
| `fecha_impresion` | timestamptz | YES | — | Fecha de impresión |
| `estado` | varchar(20) | YES | 'activa' | activa / perdida / danada / retirada |
| `ultima_lectura` | timestamptz | YES | — | Última vez escaneada |
| `ubicacion_actual` | varchar(100) | YES | 'bodega' | bodega / puesto / vendido / perdido |

**CHECK:** `tipo_codigo` ∈ {qr, barcode, rfid}
**CHECK:** `estado` ∈ {activa, perdida, danada, retirada}
**FK:** `producto_id` → `productos(id)` ON DELETE CASCADE
**Índices:** PRIMARY KEY (`id`), UNIQUE (`codigo`), INDEX (`codigo`)

---

#### 25. **flujo_prenda** — 🟡 Estructura (0 registros)
Registro de movimiento de prendas entre canales (online → feria → retazo).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `producto_id` | integer | NO | — | FK → productos.id |
| `canal_origen` | varchar(20) | NO | — | Canal origen |
| `canal_destino` | varchar(20) | NO | — | Canal destino |
| `nivel_calidad_origen_id` | integer | YES | — | FK → niveles_calidad.id |
| `nivel_calidad_destino_id` | integer | YES | — | FK → niveles_calidad.id |
| `motivo` | text | YES | — | Motivo del movimiento |
| `evaluado_por_id` | integer | YES | — | FK → usuarios.id |
| `fecha_movimiento` | timestamptz | YES | now() | Fecha del movimiento |
| `notas` | text | YES | — | Notas |

**FKs:**
- `producto_id` → `productos(id)` ON DELETE CASCADE
- `nivel_calidad_origen_id` → `niveles_calidad(id)`
- `nivel_calidad_destino_id` → `niveles_calidad(id)`
- `evaluado_por_id` → `usuarios(id)`

**Índices:** PRIMARY KEY (`id`), INDEX (`fecha_movimiento`), INDEX (`producto_id`)

**Function relacionada:** `mover_prenda_canal(producto_id, canal_origen, canal_destino, motivo, usuario_id)` — ejecuta movimiento y actualiza estado del producto

---

## 🎁 MÓDULO: DONACIONES

### Tablas (2):

#### 26. **donaciones** — 🟡 Estructura (0 registros)
Registro de recepción de donaciones de ropa/artículos.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `fecha_recepcion` | date | NO | — | Fecha de recepción |
| `fuente` | varchar(200) | YES | — | Quién donó |
| `lugar_recepcion` | varchar(20) | YES | 'casa' | casa / puesto |
| `recibido_por_id` | integer | NO | — | FK → usuarios.id |
| `notas` | text | YES | — | Notas |
| `created_at` | timestamptz | YES | now() | Creación |

**CHECK:** `lugar_recepcion` ∈ {casa, puesto}
**FK:** `recibido_por_id` → `usuarios(id)`
**Índices:** PRIMARY KEY (`id`)

---

#### 27. **items_donacion** — 🟡 Estructura (0 registros)
Ítems individuales dentro de una donación.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `donacion_id` | integer | NO | — | FK → donaciones.id |
| `descripcion` | varchar(200) | NO | — | Descripción del ítem |
| `categoria_id` | integer | YES | — | FK → categorias_producto.id |
| `estado` | varchar(30) | YES | 'por_clasificar' | por_clasificar / apto_venta / descarte / recuperar / vendido / vendido_sin_clasificar |
| `precio_min` | integer | YES | — | Precio mínimo estimado |
| `precio_max` | integer | YES | — | Precio máximo estimado |
| `ubicacion_bodega` | varchar(100) | YES | — | Ubicación física |
| `clasificado_por_id` | integer | YES | — | FK → usuarios.id |
| `fecha_clasificacion` | date | YES | — | Fecha de clasificación |
| `vendido_en_evento_id` | integer | YES | — | FK → eventos_feria.id |
| `alerta_pendiente` | boolean | YES | false | Requiere atención |
| `notas` | text | YES | — | Notas |
| `created_at` | timestamptz | YES | now() | Creación |

**CHECK:** `estado` ∈ {por_clasificar, apto_venta, descarte, recuperar, vendido, vendido_sin_clasificar}
**FKs:**
- `donacion_id` → `donaciones(id)` ON DELETE CASCADE
- `categoria_id` → `categorias_producto(id)`
- `clasificado_por_id` → `usuarios(id)`
- `vendido_en_evento_id` → `eventos_feria(id)`
**Índices:** PRIMARY KEY (`id`)

---

## 🎯 MÓDULO: CROSS-SELLING

### Tablas (1):

#### 28. **ofertas_cruzadas** — 🟡 Estructura (0 registros)
Ofertas cruzadas entre proyectos de Keysign Labs (Re-Vistete → Granja Toquí, etc.).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `proyecto_origen` | varchar(50) | NO | — | Proyecto que ofrece |
| `proyecto_destino` | varchar(50) | NO | — | Proyecto destino |
| `tipo_oferta` | varchar(30) | NO | — | descuento_porcentaje / descuento_fijo / producto_gratis / trueque / acceso_prioritario / experiencia |
| `condicion_trigger` | text | YES | — | Condición para activar oferta |
| `beneficio` | jsonb | YES | — | JSON con detalle del beneficio |
| `vigencia_desde` | date | NO | — | Inicio de vigencia |
| `vigencia_hasta` | date | YES | — | Fin de vigencia |
| `activa` | boolean | YES | true | Oferta activa |
| `limite_usos` | integer | YES | — | Máximo de usos |
| `usos_actuales` | integer | YES | 0 | Usos realizados |

**CHECK:** `tipo_oferta` ∈ {descuento_porcentaje, descuento_fijo, producto_gratis, trueque, acceso_prioritario, experiencia}
**Índices:** PRIMARY KEY (`id`)

---

## 🔄 MÓDULO: SINCRONIZACIÓN & AUDITORÍA

### Tablas (3):

#### 29. **sync_log** — ✅ Operativo (0 registros)
Log de sincronización entre dispositivos móviles y servidor.

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `dispositivo_id` | integer | NO | — | FK → dispositivos.id |
| `usuario_id` | integer | NO | — | FK → usuarios.id |
| `tabla_afectada` | varchar(50) | NO | — | Tabla sincronizada |
| `registro_id` | integer | NO | — | ID del registro |
| `operacion` | varchar(20) | NO | — | insert / update / delete |
| `timestamp_local` | timestamptz | NO | — | Timestamp en dispositivo |
| `timestamp_servidor` | timestamptz | YES | now() | Timestamp en servidor |
| `estado` | varchar(20) | YES | 'ok' | ok / duplicado / conflicto |
| `detalle` | text | YES | — | Detalle del resultado |

**CHECK:** `operacion` ∈ {insert, update, delete}
**CHECK:** `estado` ∈ {ok, duplicado, conflicto}
**FKs:** `dispositivo_id` → `dispositivos(id)`, `usuario_id` → `usuarios(id)`
**Índices:** PRIMARY KEY (`id`)

---

#### 30. **reclasificacion_log** — ✅ Operativo (0 registros)
Log de cambios manuales de clasificación (para auditoría y ML).

| Campo | Tipo | Nullable | Default | Descripción |
|-------|------|----------|---------|-------------|
| `id` | integer | NO | nextval | PK |
| `venta_id` | integer | YES | — | FK → journal_ventas.id |
| `campo_afectado` | varchar(50) | NO | — | Campo modificado |
| `valor_anterior` | text | YES | — | Valor antes del cambio |
| `valor_nuevo` | text | YES | — | Valor después del cambio |
| `motivo` | text | YES | — | Motivo del cambio |
| `nota_original` | text | YES | — | Nota original de la venta |
| `operador` | varchar(100) | YES | — | Quién realizó el cambio |
| `confirmado` | boolean | YES | false | Cambio confirmado |
| `fecha_cambio` | timestamptz | YES | now() | Fecha del cambio |

**FK:** `venta_id` → `journal_ventas(id)`
**Índices:** PRIMARY KEY (`id`)

---

## 👁️ VISTAS

### 31. **v_productos_disponibles** — Vista
Productos actualmente disponibles para venta con información enriquecida.

**Campos:** id, uuid, nombre, etiqueta_id, codigo_barras, marca, talla, condicion, estado, precio_online, precio_feria, precio_standard, precio_final, temporadas_en_inventario, descripcion_defectos, fotos, created_at, updated_at, genero, segmento_edad, categoria_revistete, subcategoria_revistete, categoria_feriaapp, subcategoria_feriaapp, nivel_calidad, canal_recomendado, temporada

---

### 32. **v_rebajas_por_evento** — Vista
Resumen de rebajas agregadas por evento de feria.

**Campos:** evento_id, fecha, lugar, estado, total_ventas, total_standard, total_final, total_rebajas, rebaja_promedio_pct

---

## 🔧 FUNCTIONS DE NEGOCIO

| Function | Argumentos | Retorno | Descripción |
|----------|-----------|---------|-------------|
| `calcular_precio_sugerido` | producto_id integer, canal varchar | integer | Calcula precio según canal y temporadas en inventario. Feria: descuento 10% cada 2 temporadas. Retazo: 20% del estándar. |
| `mover_prenda_canal` | producto_id, canal_origen, canal_destino, motivo, usuario_id | void | Mueve prenda entre canales, registra en flujo_prenda, actualiza estado |
| `reconstruir_ventas_historicas` | — | TABLE(res_tipo, res_total) | PL/pgSQL para reconstrucción de ventas desde memoria/cuaderno |
| `validar_cierre_evento` | — | trigger | Valida que evento cerrado tenga revisado_por_id y total_confirmado |
| `incrementar_temporada_inventario` | — | trigger | Incrementa temporadas_en_inventario al cambiar temporada_id |
| `update_productos_updated_at` | — | trigger | Actualiza updated_at en productos |
| `revocar_tokens_anteriores` | — | trigger | Revoca tokens previos al crear nuevo token |

---

## 🔄 CAMBIOS DESTACADOS v2.1

### ✅ Implementado

1. **Migración PostgreSQL completa desde MySQL:**
   - Motor: MySQL 8.0 → PostgreSQL 16 (Neon)
   - Charset: utf8mb4 → UTF-8
   - Sequences en lugar de AUTO_INCREMENT
   - UUID nativo con uuid-ossp
   - JSONB para datos flexibles

2. **Schema extendido para Re-Vistete:**
   - Tablas: categorias_ropa, subcategorias_ropa, generos, segmentos_edad, niveles_calidad, temporadas
   - Campos en productos: talla, medidas, precio_online, precio_feria, nivel_calidad_id, temporada_id
   - Function: calcular_precio_sugerido() con lógica de depreciación por temporada

3. **Sistema de rebajas granular:**
   - journal_ventas: tipo_rebaja, motivo_rebaja, porcentaje_rebaja
   - venta_rebajas: registro independiente con línea_venta_id
   - CHECK constraints para tipos de rebaja validados

4. **Cross-selling entre proyectos:**
   - Tabla ofertas_cruzadas para promociones Re-Vistete ↔ Granja Toquí

5. **Tracking de donaciones:**
   - donaciones + items_donacion con estados de clasificación

6. **Auditoría y sync:**
   - sync_log para sincronización offline-first
   - reclasificacion_log para ML y control de calidad

7. **Reconstrucción de datos históricos:**
   - Function PL/pgSQL para migrar ventas desde cuaderno/memoria
   - 3 ventas reconstruidas (Calefón, Alero PVC, Chaqueta Mujer)

### 🔄 Próximos Pasos

1. **Poblar datos históricos:**
   - Migrar ventas del cuaderno de feria dominical (Nancy)
   - Importar productos con fotos y etiquetas

2. **Activar módulos pendientes:**
   - clientes_frecuentes + deudas_diferidas
   - etiquetas + flujo_prenda
   - donaciones + items_donacion

3. **Implementar APIs:**
   - FastAPI para backend
   - Endpoints para ventas, productos, reportes

4. **Dashboard y reportes:**
   - v_rebajas_por_evento como base
   - KPIs por canal, producto, temporada

---

## 📚 CONVENCIONES Y NOMENCLATURA

### Nomenclatura de Tablas
```
snake_case plural
Ejemplos: productos, eventos_feria, journal_ventas
```

### Nomenclatura de Campos
```
snake_case singular
Ejemplos: venta_id, precio_final, created_at
```

### Prefijos Comunes

| Prefijo | Significado | Ejemplo |
|---------|-------------|---------|
| `id` | Primary Key | id, venta_id |
| `uuid` | UUID global | uuid (productos, usuarios) |
| `is_` / `tiene_` | Boolean | activo, tiene_rango |
| `_id` | Foreign Key | categoria_id, usuario_id |
| `_at` | Timestamp | created_at, updated_at |
| `_total` | Suma/Total | total_venta, precio_final_total |
| `journal_` | Tabla inmutable | journal_ventas, journal_egresos |
| `v_` | Vista | v_productos_disponibles |

### Tipos de Datos Comunes

| Tipo PostgreSQL | Uso | Ejemplo |
|-----------------|-----|---------|
| `integer` | IDs, montos CLP | id, precio |
| `uuid` | Identificadores globales | uuid |
| `varchar(N)` | Textos cortos | nombre, codigo |
| `text` | Textos largos | notas, descripcion |
| `jsonb` | Datos estructurados | fotos, medidas, beneficio |
| `numeric(8,2)` | Cantidades decimales | cantidad |
| `numeric(5,2)` | Porcentajes | porcentaje_rebaja |
| `timestamptz` | Fechas/horas | created_at, timestamp_local |
| `date` | Fechas sin hora | fecha, vigente_desde |
| `boolean` | Flags | activo, venta_directa_sin_bodega |
| `varchar[]` | Arrays | segmento_edad |

---

## 🔐 SEGURIDAD Y PRIVACIDAD

### Datos Sensibles

**Tablas con información personal:**
- `usuarios`: password_hash
- `refresh_tokens`: token_hash, ip_origen, user_agent
- `journal_ventas`: timestamp_local (patrones de comportamiento)

**Protección implementada:**
- Password hashing con BCrypt (implícito en password_hash)
- Tokens con hash SHA-256
- Revocación automática de tokens anteriores
- IP logging para auditoría

### Permisos de BD

**Usuario en producción:** Configurado via variables de entorno
**Host:** Neon PostgreSQL (cloud)
**Privilegios:** SELECT, INSERT, UPDATE, DELETE en schema public

---

## 📊 ESTADÍSTICAS DETALLADAS POR TABLA

| Tabla | Registros | Tamaño | Estado |
|-------|-----------|--------|--------|
| productos | 57 | 264 kB | ✅ Poblado |
| categorias_ropa | 61 | 80 kB | ✅ Poblado |
| canales_venta | 7 | 32 kB | ✅ Poblado |
| segmentos_edad | 5 | 40 kB | ✅ Poblado |
| generos | 3 | 40 kB | ✅ Poblado |
| niveles_calidad | 8 | 64 kB | ✅ Poblado |
| temporadas | 5 | 40 kB | ✅ Poblado |
| usuarios | 2 | 40 kB | ✅ Activo |
| dispositivos | 2 | 48 kB | ✅ Activo |
| eventos_feria | 3 | 32 kB | ✅ Activo |
| journal_ventas | 3 | 48 kB | ✅ Activo |
| lineas_venta | 3 | 32 kB | ✅ Activo |
| venta_rebajas | 1 | 64 kB | ✅ Activo |
| categorias_producto | ~8 | 24 kB | ✅ Poblado |
| subcategorias_producto | ~10 | 24 kB | ✅ Poblado |
| categoria_canal | ~15 | 24 kB | ✅ Poblado |
| precios_standard | 0 | 32 kB | 🟡 Pendiente |
| clientes_frecuentes | 0 | 16 kB | 🟡 Estructura |
| deudas_diferidas | 0 | 16 kB | 🟡 Estructura |
| journal_egresos | 0 | 16 kB | 🟡 Estructura |
| journal_insumos | 0 | 16 kB | 🟡 Estructura |
| etiquetas | 0 | 32 kB | 🟡 Estructura |
| flujo_prenda | 0 | 32 kB | 🟡 Estructura |
| donaciones | 0 | 16 kB | 🟡 Estructura |
| items_donacion | 0 | 16 kB | 🟡 Estructura |
| ofertas_cruzadas | 0 | 16 kB | 🟡 Estructura |
| sync_log | 0 | 16 kB | ✅ Operativo |
| reclasificacion_log | 0 | 16 kB | ✅ Operativo |
| refresh_tokens | 0 | 16 kB | ✅ Operativo |
| **TOTAL** | **~85** | **~1.2 MB** | **30 tablas + 2 vistas** |

---

**Documento generado:** 2026-06-25
**Generado por:** Kimi K2.6 / Keysign Labs
**Sistema en producción:** FeriaApp v2.1 (PostgreSQL/Neon)
**Próxima actualización:** Al aplicar nuevas migraciones o cambios de schema
**Versión del documento:** 1.0 (Snapshot inicial post-migración)
