"""
FeriaApp API v2.1 — Router: Catálogo (listados públicos)
OPTIMIZADO: Usa v_productos_completos para catálogo público
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException

from lib.core.database import get_db

router = APIRouter(prefix="/catalogo", tags=["Catálogo"])


@router.get("/productos")
async def listar_productos(
    categoria_id: Optional[int] = None,
    estado: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
    conn=Depends(get_db)
):
    """
    Listar productos para catálogo público - Usa vista pre-join
    """
    query = """
        SELECT id, nombre,
               categoria_feriaapp, subcategoria_feriaapp,
               categoria_revistete, subcategoria_revistete,
               genero, segmento_edad, talla, talla_numerica,
               precio_online, precio_feria, precio_standard, precio_final,
               estado, condicion, marca,
               nivel_calidad, canal_recomendado,
               temporada, temporadas_en_inventario,
               descripcion_defectos, fotos, notas,
               created_at, updated_at
        FROM v_productos_completos
        WHERE 1=1
    """
    params = []

    if categoria_id:
        query += " AND categoria_feriaapp_id = $" + str(len(params) + 1)
        params.append(categoria_id)

    if estado:
        query += " AND estado = $" + str(len(params) + 1)
        params.append(estado)

    query += " ORDER BY nombre LIMIT $" + str(len(params) + 1) + " OFFSET $" + str(len(params) + 2)
    params.extend([limit, offset])

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]


@router.get("/productos/{producto_id}")
async def obtener_producto(producto_id: int, conn=Depends(get_db)):
    """
    Obtener detalle de producto - Usa vista pre-join
    """
    row = await conn.fetchrow("""
        SELECT * FROM v_productos_completos WHERE id = $1
    """, producto_id)

    if not row:
        raise HTTPException(status_code=404, detail="Producto no encontrado")

    return dict(row)

