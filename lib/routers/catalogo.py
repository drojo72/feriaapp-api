"""
FeriaApp API v2.1 — Router: Catálogo (listados públicos de catálogos)
Frugal: solo lectura, filtros básicos. Sin response_model para evitar serialización forzada.
"""
from typing import Optional, List
from fastapi import APIRouter, Depends

from lib.core.database import get_db

router = APIRouter(prefix="/catalogo", tags=["Catálogo"])


@router.get("/productos")
async def listar_productos(
    categoria_id: Optional[int] = None,
    estado: Optional[str] = None,
    conn=Depends(get_db)
):
    """Listar productos activos con filtros opcionales por categoría y estado."""
    query = """
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, subcategoria_revistete_id,
               genero_id, segmento_edad_id, talla, talla_numerica,
               precio_online, precio_feria, precio_standard, precio_final,
               estado, condicion, marca, nivel_calidad_id, temporada_id,
               temporadas_en_inventario, descripcion_defectos,
               notas, created_at, updated_at
        FROM productos
        WHERE activo = TRUE
    """
    params = []
    if categoria_id:
        query += " AND categoria_feriaapp_id = $" + str(len(params) + 1)
        params.append(categoria_id)
    if estado:
        query += " AND estado = $" + str(len(params) + 1)
        params.append(estado)
    query += " ORDER BY nombre"

    rows = await conn.fetch(query, *params)
    # Serializar manualmente, excluyendo campos problemáticos (fotos, medidas)
    result = []
    for r in rows:
        d = dict(r)
        # Asegurar que precios sean int o null
        for key in ['precio_online', 'precio_feria', 'precio_standard', 'precio_final']:
            if d.get(key) is not None:
                d[key] = int(d[key])
        result.append(d)
    return result


@router.get("/productos/{producto_id}")
async def obtener_producto(producto_id: int, conn=Depends(get_db)):
    """Obtener detalle de un producto por ID."""
    row = await conn.fetchrow("""
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, subcategoria_revistete_id,
               genero_id, segmento_edad_id, talla, talla_numerica,
               precio_online, precio_feria, precio_standard, precio_final,
               estado, condicion, marca, nivel_calidad_id, temporada_id,
               temporadas_en_inventario, descripcion_defectos,
               notas, created_at, updated_at
        FROM productos WHERE id = $1 AND activo = TRUE
    """, producto_id)
    if not row:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    d = dict(row)
    for key in ['precio_online', 'precio_feria', 'precio_standard', 'precio_final']:
        if d.get(key) is not None:
            d[key] = int(d[key])
    return d


@router.get("/categorias")
async def listar_categorias(conn=Depends(get_db)):
    """Categorías FeriaApp (originales)."""
    rows = await conn.fetch(
        "SELECT id, nombre, sector_puesto, tipo_origen FROM categorias_producto WHERE activo = TRUE ORDER BY nombre"
    )
    return [dict(r) for r in rows]


@router.get("/categorias-revistete")
async def listar_categorias_revistete(conn=Depends(get_db)):
    """Categorías Re-Vistete (moda circular)."""
    rows = await conn.fetch(
        "SELECT id, codigo, nombre, grupo FROM categorias_ropa WHERE activo = TRUE ORDER BY grupo, nombre"
    )
    return [dict(r) for r in rows]


@router.get("/generos")
async def listar_generos(conn=Depends(get_db)):
    rows = await conn.fetch("SELECT id, codigo, nombre FROM generos WHERE activo = TRUE")
    return [dict(r) for r in rows]


@router.get("/segmentos-edad")
async def listar_segmentos_edad(conn=Depends(get_db)):
    rows = await conn.fetch("SELECT id, codigo, nombre, rango_anios FROM segmentos_edad WHERE activo = TRUE")
    return [dict(r) for r in rows]


@router.get("/niveles-calidad")
async def listar_niveles_calidad(conn=Depends(get_db)):
    rows = await conn.fetch(
        "SELECT id, codigo, nombre, canal_asignado, descripcion FROM niveles_calidad WHERE activo = TRUE"
    )
    return [dict(r) for r in rows]
