"""
FeriaApp API v2.1 — Router: Productos (CRUD bodega e ingreso)
OPTIMIZADO: Usa índices compuestos y paginación
"""
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query

from lib.core.database import get_db
from lib.core.security import get_current_user

# ✅ Import explícito de modelos
from lib.models.productos import ProductoOut, ProductoCreate, ProductoUpdate, MovimientoPrendaIn

router = APIRouter(prefix="/productos", tags=["Productos"])


@router.get("/bodega", response_model=List[ProductoOut])
async def listar_bodega(
    estado: Optional[str] = None,
    categoria_revistete_id: Optional[int] = None,
    categoria_feriaapp_id: Optional[int] = None,
    genero_id: Optional[int] = None,
    nivel_calidad_id: Optional[int] = None,
    search: Optional[str] = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Listar productos en bodega - OPTIMIZADO: índices compuestos + paginación"""
    query = """
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, subcategoria_revistete_id,
               genero_id, segmento_edad_id, talla, talla_numerica,
               precio_online, precio_feria, precio_standard, precio_final,
               estado, condicion, marca, nivel_calidad_id, temporada_id,
               temporadas_en_inventario, descripcion_defectos, fotos,
               notas, created_at, updated_at
        FROM productos
        WHERE activo = TRUE
    """
    params = []

    if estado:
        query += " AND estado = $" + str(len(params) + 1)
        params.append(estado)

    if categoria_revistete_id:
        query += " AND categoria_revistete_id = $" + str(len(params) + 1)
        params.append(categoria_revistete_id)

    if categoria_feriaapp_id:
        query += " AND categoria_feriaapp_id = $" + str(len(params) + 1)
        params.append(categoria_feriaapp_id)

    if genero_id:
        query += " AND genero_id = $" + str(len(params) + 1)
        params.append(genero_id)

    if nivel_calidad_id:
        query += " AND nivel_calidad_id = $" + str(len(params) + 1)
        params.append(nivel_calidad_id)

    if search:
        search_term = f"%{search}%"
        query += " AND nombre ILIKE $" + str(len(params) + 1)
        params.append(search_term)

    query += " ORDER BY updated_at DESC LIMIT $" + str(len(params) + 1) + " OFFSET $" + str(len(params) + 2)
    params.extend([limit, offset])

    rows = await conn.fetch(query, *params)

    result = []
    for r in rows:
        d = dict(r)
        for key in ['precio_online', 'precio_feria', 'precio_standard', 'precio_final']:
            if d.get(key) is not None:
                d[key] = int(d[key])
        result.append(d)

    return result


@router.get("/bodega/count")
async def contar_bodega(
    estado: Optional[str] = None,
    categoria_revistete_id: Optional[int] = None,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Contar productos en bodega para paginación"""
    query = "SELECT COUNT(*) FROM productos WHERE activo = TRUE"
    params = []

    if estado:
        query += " AND estado = $" + str(len(params) + 1)
        params.append(estado)

    if categoria_revistete_id:
        query += " AND categoria_revistete_id = $" + str(len(params) + 1)
        params.append(categoria_revistete_id)

    total = await conn.fetchval(query, *params)
    return {"total": total}


@router.get("/bodega/disponibles", response_model=List[ProductoOut])
async def listar_disponibles(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Listar productos disponibles para venta (más rápido usando índice compuesto)"""
    rows = await conn.fetch("""
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, subcategoria_revistete_id,
               genero_id, segmento_edad_id, talla, talla_numerica,
               precio_online, precio_feria, precio_standard, precio_final,
               estado, condicion, marca, nivel_calidad_id, temporada_id,
               temporadas_en_inventario, descripcion_defectos, fotos,
               notas, created_at, updated_at
        FROM productos
        WHERE activo = TRUE AND estado = 'disponible'
        ORDER BY updated_at DESC
        LIMIT $1 OFFSET $2
    """, limit, offset)

    result = []
    for r in rows:
        d = dict(r)
        for key in ['precio_online', 'precio_feria', 'precio_standard', 'precio_final']:
            if d.get(key) is not None:
                d[key] = int(d[key])
        result.append(d)

    return result


@router.get("/bodega/{producto_id}", response_model=ProductoOut)
async def obtener_producto_bodega(
    producto_id: int,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Obtener producto por ID"""
    row = await conn.fetchrow("""
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, subcategoria_revistete_id,
               genero_id, segmento_edad_id, talla, talla_numerica,
               precio_online, precio_feria, precio_standard, precio_final,
               estado, condicion, marca, nivel_calidad_id, temporada_id,
               temporadas_en_inventario, descripcion_defectos, fotos,
               notas, created_at, updated_at
        FROM productos
        WHERE id = $1 AND activo = TRUE
    """, producto_id)

    if not row:
        raise HTTPException(status_code=404, detail="Producto no encontrado")

    d = dict(row)
    for key in ['precio_online', 'precio_feria', 'precio_standard', 'precio_final']:
        if d.get(key) is not None:
            d[key] = int(d[key])
    return d


@router.get("/bodega/categoria/{categoria_id}", response_model=List[ProductoOut])
async def listar_por_categoria(
    categoria_id: int,
    estado: Optional[str] = None,
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Listar productos por categoría Re-Vistete - Usa índice compuesto"""
    query = """
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, subcategoria_revistete_id,
               genero_id, segmento_edad_id, talla, talla_numerica,
               precio_online, precio_feria, precio_standard, precio_final,
               estado, condicion, marca, nivel_calidad_id, temporada_id,
               temporadas_en_inventario, descripcion_defectos, fotos,
               notas, created_at, updated_at
        FROM productos
        WHERE activo = TRUE AND categoria_revistete_id = $1
    """
    params = [categoria_id]

    if estado:
        query += " AND estado = $" + str(len(params) + 1)
        params.append(estado)

    query += " ORDER BY updated_at DESC LIMIT $" + str(len(params) + 1) + " OFFSET $" + str(len(params) + 2)
    params.extend([limit, offset])

    rows = await conn.fetch(query, *params)
    result = []
    for r in rows:
        d = dict(r)
        for key in ['precio_online', 'precio_feria', 'precio_standard', 'precio_final']:
            if d.get(key) is not None:
                d[key] = int(d[key])
        result.append(d)

    return result


@router.post("/bodega", response_model=ProductoOut, status_code=201)
async def crear_producto(
    producto: ProductoCreate,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Ingresar nuevo producto a bodega. Registra evaluador (usuario actual)."""
    row = await conn.fetchrow("""
        INSERT INTO productos (
            nombre, categoria_feriaapp_id, categoria_revistete_id,
            subcategoria_revistete_id, genero_id, segmento_edad_id,
            talla, talla_numerica, medidas,
            precio_online, precio_feria, precio_standard, precio_final,
            condicion, marca, nivel_calidad_id, temporada_id,
            descripcion_defectos, fotos, notas,
            evaluado_por_id, estado
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, 'disponible')
        RETURNING id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
                  categoria_revistete_id, subcategoria_revistete_id,
                  genero_id, segmento_edad_id, talla, talla_numerica,
                  precio_online, precio_feria, precio_standard, precio_final,
                  estado, condicion, marca, nivel_calidad_id, temporada_id,
                  temporadas_en_inventario, descripcion_defectos, fotos,
                  notas, created_at, updated_at
    """,
        producto.nombre,
        producto.categoria_feriaapp_id,
        producto.categoria_revistete_id,
        producto.subcategoria_revistete_id,
        producto.genero_id,
        producto.segmento_edad_id,
        producto.talla,
        producto.talla_numerica,
        producto.medidas,
        producto.precio_online,
        producto.precio_feria,
        producto.precio_standard,
        producto.precio_final,
        producto.condicion,
        producto.marca,
        producto.nivel_calidad_id,
        producto.temporada_id,
        producto.descripcion_defectos,
        producto.fotos,
        producto.notas,
        current_user["id"]
    )
    return dict(row)


@router.put("/bodega/{producto_id}", response_model=ProductoOut)
async def actualizar_producto(
    producto_id: int,
    producto: ProductoUpdate,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Actualizar producto existente. Solo campos enviados se modifican."""
    existing = await conn.fetchrow(
        "SELECT id FROM productos WHERE id = $1 AND activo = TRUE",
        producto_id
    )
    if not existing:
        raise HTTPException(status_code=404, detail="Producto no encontrado")

    updates = []
    params = []
    fields = {
        "nombre": producto.nombre,
        "categoria_feriaapp_id": producto.categoria_feriaapp_id,
        "categoria_revistete_id": producto.categoria_revistete_id,
        "subcategoria_revistete_id": producto.subcategoria_revistete_id,
        "genero_id": producto.genero_id,
        "segmento_edad_id": producto.segmento_edad_id,
        "talla": producto.talla,
        "talla_numerica": producto.talla_numerica,
        "medidas": producto.medidas,
        "precio_online": producto.precio_online,
        "precio_feria": producto.precio_feria,
        "precio_standard": producto.precio_standard,
        "precio_final": producto.precio_final,
        "condicion": producto.condicion,
        "estado": producto.estado,
        "marca": producto.marca,
        "nivel_calidad_id": producto.nivel_calidad_id,
        "temporada_id": producto.temporada_id,
        "descripcion_defectos": producto.descripcion_defectos,
        "fotos": producto.fotos,
        "notas": producto.notas,
    }

    for field, value in fields.items():
        if value is not None:
            updates.append(f"{field} = ${len(params) + 1}")
            params.append(value)

    if not updates:
        raise HTTPException(status_code=400, detail="No se enviaron campos para actualizar")

    params.append(producto_id)
    query = f"""
        UPDATE productos
        SET {', '.join(updates)}
        WHERE id = ${len(params)}
        RETURNING id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
                  categoria_revistete_id, subcategoria_revistete_id,
                  genero_id, segmento_edad_id, talla, talla_numerica,
                  precio_online, precio_feria, precio_standard, precio_final,
                  estado, condicion, marca, nivel_calidad_id, temporada_id,
                  temporadas_en_inventario, descripcion_defectos, fotos,
                  notas, created_at, updated_at
    """
    row = await conn.fetchrow(query, *params)
    return dict(row)


@router.patch("/bodega/{producto_id}/estado")
async def cambiar_estado_producto(
    producto_id: int,
    estado: str,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Cambiar estado de un producto rápidamente"""
    estados_validos = ['disponible', 'vendido', 'reservado', 'donado', 'retazo', 'en_evaluacion']
    if estado not in estados_validos:
        raise HTTPException(
            status_code=400,
            detail=f"Estado inválido. Opciones: {', '.join(estados_validos)}"
        )

    result = await conn.execute(
        "UPDATE productos SET estado = $1 WHERE id = $2 AND activo = TRUE",
        estado, producto_id
    )

    if result == "UPDATE 0":
        raise HTTPException(status_code=404, detail="Producto no encontrado")

    return {"message": "Estado actualizado", "producto_id": producto_id, "estado": estado}


@router.delete("/bodega/{producto_id}")
async def eliminar_producto(
    producto_id: int,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Soft-delete: marca activo = FALSE. No borra físicamente."""
    result = await conn.execute(
        "UPDATE productos SET activo = FALSE, estado = 'en_evaluacion' WHERE id = $1",
        producto_id
    )
    if result == "UPDATE 0":
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return {"message": "Producto eliminado (soft-delete)", "producto_id": producto_id}


@router.get("/flujos")
async def listar_flujos_productos(
    tipo: Optional[str] = Query(None, description="boutique, feria, donacion, retazo"),
    estado: Optional[str] = Query(None, description="disponible, vendido, reservado, donado, retazo"),
    search: Optional[str] = Query(None, description="Buscar por nombre de producto"),
    fecha_desde: Optional[str] = Query(None, description="Fecha inicio (YYYY-MM-DD)"),
    fecha_hasta: Optional[str] = Query(None, description="Fecha fin (YYYY-MM-DD)"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Listar flujos de productos (movimientos entre canales)"""
    query = """
        SELECT
            fp.id,
            fp.producto_id,
            p.nombre as producto_nombre,
            p.sku,
            fp.canal_origen,
            fp.canal_destino as tipo,
            fp.nivel_calidad_origen_id,
            fp.nivel_calidad_destino_id,
            fp.motivo,
            fp.evaluado_por_id,
            u.nombre as evaluado_por,
            fp.fecha_movimiento,
            fp.notas,
            p.estado,
            p.historia_origen,
            p.historia_ubicacion,
            p.historia_motivo,
            nc_origen.nombre as calidad_origen,
            nc_destino.nombre as calidad_destino
        FROM flujo_prenda fp
        JOIN productos p ON fp.producto_id = p.id
        LEFT JOIN usuarios u ON fp.evaluado_por_id = u.id
        LEFT JOIN niveles_calidad nc_origen ON fp.nivel_calidad_origen_id = nc_origen.id
        LEFT JOIN niveles_calidad nc_destino ON fp.nivel_calidad_destino_id = nc_destino.id
        WHERE 1=1
    """
    params = []

    if tipo:
        query += " AND fp.canal_destino = $" + str(len(params) + 1)
        params.append(tipo)

    if estado:
        query += " AND p.estado = $" + str(len(params) + 1)
        params.append(estado)

    if search:
        query += " AND (p.nombre ILIKE $" + str(len(params) + 1) + " OR p.sku ILIKE $" + str(len(params) + 2) + ")"
        search_term = f"%{search}%"
        params.extend([search_term, search_term])

    if fecha_desde:
        query += " AND fp.fecha_movimiento >= $" + str(len(params) + 1) + "::date"
        params.append(fecha_desde)

    if fecha_hasta:
        query += " AND fp.fecha_movimiento <= $" + str(len(params) + 1) + "::date"
        params.append(fecha_hasta)

    count_query = query.replace(
        "SELECT \n            fp.id,\n            fp.producto_id,\n            p.nombre as producto_nombre,\n            p.sku,\n            fp.canal_origen,\n            fp.canal_destino as tipo,\n            fp.nivel_calidad_origen_id,\n            fp.nivel_calidad_destino_id,\n            fp.motivo,\n            fp.evaluado_por_id,\n            u.nombre as evaluado_por,\n            fp.fecha_movimiento,\n            fp.notas,\n            p.estado,\n            p.historia_origen,\n            p.historia_ubicacion,\n            p.historia_motivo,\n            nc_origen.nombre as calidad_origen,\n            nc_destino.nombre as calidad_destino",
        "SELECT COUNT(*) as total"
    )

    total = await conn.fetchval(count_query, *params)

    query += " ORDER BY fp.fecha_movimiento DESC LIMIT $" + str(len(params) + 1) + " OFFSET $" + str(len(params) + 2)
    params.extend([limit, offset])

    rows = await conn.fetch(query, *params)

    return {
        "items": [dict(r) for r in rows],
        "total": total,
        "limit": limit,
        "offset": offset
    }


@router.get("/flujos/estadisticas")
async def estadisticas_flujos(
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Estadísticas de flujos de productos"""
    por_tipo = await conn.fetch("""
        SELECT
            canal_destino as tipo,
            COUNT(*) as total
        FROM flujo_prenda
        GROUP BY canal_destino
        ORDER BY total DESC
    """)

    por_mes = await conn.fetch("""
        SELECT
            TO_CHAR(fecha_movimiento, 'YYYY-MM') as mes,
            COUNT(*) as total
        FROM flujo_prenda
        WHERE fecha_movimiento >= NOW() - INTERVAL '12 months'
        GROUP BY TO_CHAR(fecha_movimiento, 'YYYY-MM')
        ORDER BY mes DESC
    """)

    ultimos = await conn.fetch("""
        SELECT
            fp.id,
            p.nombre as producto_nombre,
            fp.canal_destino as tipo,
            fp.fecha_movimiento,
            u.nombre as evaluado_por
        FROM flujo_prenda fp
        JOIN productos p ON fp.producto_id = p.id
        LEFT JOIN usuarios u ON fp.evaluado_por_id = u.id
        ORDER BY fp.fecha_movimiento DESC
        LIMIT 10
    """)

    return {
        "por_tipo": [dict(r) for r in por_tipo],
        "por_mes": [dict(r) for r in por_mes],
        "ultimos_movimientos": [dict(r) for r in ultimos],
        "total_movimientos": sum(r['total'] for r in por_tipo)
    }


@router.post("/{producto_id}/mover")
async def mover_producto(
    producto_id: int,
    movimiento: MovimientoPrendaIn,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Mover un producto entre canales (boutique → feria → donacion → retazo)"""
    producto = await conn.fetchrow(
        "SELECT id, nombre, estado, nivel_calidad_id FROM productos WHERE id = $1 AND activo = TRUE",
        producto_id
    )
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")

    canales_validos = ['boutique', 'feria', 'donacion', 'retazo']
    if movimiento.canal_destino not in canales_validos:
        raise HTTPException(
            status_code=400,
            detail=f"Canal destino inválido. Opciones: {', '.join(canales_validos)}"
        )

    nivel_calidad_map = {
        'boutique': 1,
        'feria': 2,
        'retazo': 3
    }
    nuevo_nivel_calidad = nivel_calidad_map.get(movimiento.canal_destino)

    estado_map = {
        'boutique': 'disponible',
        'feria': 'disponible',
        'donacion': 'donado',
        'retazo': 'retazo'
    }
    nuevo_estado = estado_map.get(movimiento.canal_destino, 'disponible')

    async with conn.transaction():
        await conn.execute("""
            INSERT INTO flujo_prenda (
                producto_id,
                canal_origen,
                canal_destino,
                nivel_calidad_origen_id,
                nivel_calidad_destino_id,
                motivo,
                evaluado_por_id,
                notas
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        """,
            producto_id,
            movimiento.canal_origen or producto['estado'],
            movimiento.canal_destino,
            producto['nivel_calidad_id'],
            nuevo_nivel_calidad,
            movimiento.motivo,
            current_user["id"],
            movimiento.notas
        )

        await conn.execute("""
            UPDATE productos SET
                estado = $1,
                nivel_calidad_id = $2,
                updated_at = NOW()
            WHERE id = $3
        """, nuevo_estado, nuevo_nivel_calidad, producto_id)

    return {
        "message": f"Producto movido a {movimiento.canal_destino} exitosamente",
        "producto_id": producto_id,
        "producto_nombre": producto['nombre'],
        "canal_destino": movimiento.canal_destino,
        "nuevo_estado": nuevo_estado,
        "motivo": movimiento.motivo,
        "registrado_en_historial": True
    }
