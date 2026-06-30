"""
FeriaApp API v2.1 — Router: Productos (CRUD bodega e ingreso)
Frugal: crear, editar, listar bodega. Auth requerido.
"""
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException

from lib.core.database import get_db
from lib.core.security import get_current_user
from lib.models.productos import ProductoOut, ProductoCreate, ProductoUpdate

router = APIRouter(prefix="/productos", tags=["Productos"])


@router.get("/bodega", response_model=List[ProductoOut])
async def listar_bodega(
    estado: Optional[str] = None,
    categoria_revistete_id: Optional[int] = None,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Listar productos en bodega (inventario). Filtros por estado y categoría Re-Vistete."""
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
    query += " ORDER BY updated_at DESC"

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]


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
            descripcion, descripcion_defectos, fotos, notas,
            evaluado_por_id, estado
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, 'disponible')
        RETURNING id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
                  categoria_revistete_id, subcategoria_revistete_id,
                  genero_id, segmento_edad_id, talla, talla_numerica,
                  precio_online, precio_feria, precio_standard, precio_final,
                  estado, condicion, marca, nivel_calidad_id, temporada_id,
                  temporadas_en_inventario, descripcion_defectos, fotos,
                  notas, created_at, updated_at
    """,
        producto.nombre, producto.categoria_feriaapp_id, producto.categoria_revistete_id,
        producto.subcategoria_revistete_id, producto.genero_id, producto.segmento_edad_id,
        producto.talla, producto.talla_numerica, producto.medidas,
        producto.precio_online, producto.precio_feria, producto.precio_standard, producto.precio_final,
        producto.condicion, producto.marca, producto.nivel_calidad_id, producto.temporada_id,
        producto.descripcion, producto.descripcion_defectos, producto.fotos, producto.notas,
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
    existing = await conn.fetchrow("SELECT id FROM productos WHERE id = $1 AND activo = TRUE", producto_id)
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
        "descripcion": producto.descripcion,
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
    query = f"UPDATE productos SET {', '.join(updates)} WHERE id = ${len(params)} RETURNING *"
    row = await conn.fetchrow(query, *params)
    return dict(row)


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
