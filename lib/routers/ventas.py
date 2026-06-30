"""
FeriaApp API v2.1 — Router: Ventas (transacción completa con líneas)
Frugal: una sola transacción para venta + líneas + rebajas.
Auth requerido.
"""
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException

from lib.core.database import get_db
from lib.core.security import get_current_user, require_admin
from lib.models.ventas import VentaIn, VentaOut, ModificacionVentaIn, VentaResumenEvento

router = APIRouter(prefix="/ventas", tags=["Ventas"])


@router.post("/", response_model=dict, status_code=201)
async def crear_venta(
    venta: VentaIn,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Registrar venta completa con líneas de venta.

    Transacción atómica: si falla una línea, rollback completo.
    Calcula totales automáticamente desde líneas.
    """
    evento = await conn.fetchrow(
        "SELECT id, estado FROM eventos_feria WHERE id = $1", venta.evento_feria_id
    )
    if not evento:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    if evento["estado"] == "cerrado":
        raise HTTPException(status_code=400, detail="No se pueden crear ventas en evento cerrado")
    if evento["estado"] != "activo":
        raise HTTPException(status_code=400, detail="Evento no está activo")

    total_standard = 0
    total_final = 0
    for linea in venta.lineas:
        precio_std = linea.precio_unitario_standard or linea.precio_unitario_final
        total_standard += precio_std * linea.cantidad
        total_final += linea.precio_unitario_final * linea.cantidad

    diferencia = total_final - total_standard
    porcentaje_rebaja = 0.0
    tipo_rebaja = "ninguna"
    if total_standard > 0 and diferencia < 0:
        porcentaje_rebaja = round((abs(diferencia) / total_standard) * 100, 2)
        tipo_rebaja = "rebaja_automatica"

    async with conn.transaction():
        venta_id = await conn.fetchval("""
            INSERT INTO journal_ventas (
                evento_feria_id, usuario_id, dispositivo_id,
                timestamp_local, forma_pago,
                perfil_cliente, cliente_frecuente_id,
                venta_directa_sin_bodega, garantia_devolucion,
                precio_standard_total, precio_final_total,
                diferencia_rebaja, porcentaje_rebaja, tipo_rebaja,
                total_venta, sync_estado, notas
            ) VALUES ($1, $2, $3, NOW(), $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, 'sincronizado', $15)
            RETURNING id
        """,
            venta.evento_feria_id, current_user["id"], 1,
            venta.forma_pago, venta.perfil_cliente, venta.cliente_frecuente_id,
            venta.venta_directa_sin_bodega, venta.garantia_devolucion,
            total_standard, total_final, diferencia, porcentaje_rebaja, tipo_rebaja,
            total_final, venta.notas
        )

        for linea in venta.lineas:
            subtotal = linea.precio_unitario_final * linea.cantidad
            await conn.execute("""
                INSERT INTO lineas_venta (
                    venta_id, producto_id, item_donacion_id,
                    cantidad, precio_unitario_standard, precio_unitario_final, subtotal, notas
                ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            """,
                venta_id, linea.producto_id, linea.item_donacion_id,
                linea.cantidad, linea.precio_unitario_standard, linea.precio_unitario_final,
                subtotal, linea.notas
            )

            if linea.producto_id:
                await conn.execute(
                    "UPDATE productos SET estado = 'vendido' WHERE id = $1",
                    linea.producto_id
                )

        await conn.execute("""
            UPDATE eventos_feria
            SET total_calculado = total_calculado + $1
            WHERE id = $2
        """, total_final, venta.evento_feria_id)

    return {
        "id": venta_id,
        "message": "Venta registrada exitosamente",
        "total_venta": total_final,
        "total_standard": total_standard,
        "diferencia_rebaja": diferencia,
        "cantidad_lineas": len(venta.lineas)
    }


@router.get("/", response_model=List[dict])
async def listar_ventas(
    evento_id: Optional[int] = None,
    fecha_desde: Optional[str] = None,
    fecha_hasta: Optional[str] = None,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Listar ventas con filtros. Máximo 100 registros."""
    query = """
        SELECT jv.id, jv.timestamp_local, jv.total_venta, jv.forma_pago,
               jv.estado_pago, jv.sync_estado, jv.notas,
               ef.fecha as fecha_evento, ef.lugar, ef.estado as estado_evento,
               u.nombre as vendedor
        FROM journal_ventas jv
        JOIN eventos_feria ef ON jv.evento_feria_id = ef.id
        JOIN usuarios u ON jv.usuario_id = u.id
        WHERE 1=1
    """
    params = []
    if evento_id:
        query += " AND jv.evento_feria_id = $" + str(len(params) + 1)
        params.append(evento_id)
    if fecha_desde:
        query += " AND jv.timestamp_local >= $" + str(len(params) + 1)
        params.append(fecha_desde)
    if fecha_hasta:
        query += " AND jv.timestamp_local <= $" + str(len(params) + 1)
        params.append(fecha_hasta)
    query += " ORDER BY jv.timestamp_local DESC LIMIT 100"

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]


@router.get("/{venta_id}")
async def obtener_venta(
    venta_id: int,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Obtener venta con sus líneas de detalle."""
    venta = await conn.fetchrow("""
        SELECT jv.*, ef.fecha as fecha_evento, ef.lugar, ef.estado as estado_evento
        FROM journal_ventas jv
        JOIN eventos_feria ef ON jv.evento_feria_id = ef.id
        WHERE jv.id = $1
    """, venta_id)
    if not venta:
        raise HTTPException(status_code=404, detail="Venta no encontrada")

    lineas = await conn.fetch("""
        SELECT lv.*, p.nombre as nombre_producto
        FROM lineas_venta lv
        LEFT JOIN productos p ON lv.producto_id = p.id
        WHERE lv.venta_id = $1
    """, venta_id)

    return {
        "venta": dict(venta),
        "lineas": [dict(l) for l in lineas]
    }


@router.post("/{venta_id}/modificar")
async def modificar_venta(
    venta_id: int,
    mod: ModificacionVentaIn,
    conn=Depends(get_db),
    current_user=Depends(require_admin)
):
    """[ADMIN ONLY] Modificar venta existente. Requiere nota explicativa.

    Registra en reclasificacion_log todo cambio.
    """
    venta = await conn.fetchrow(
        "SELECT * FROM journal_ventas WHERE id = $1", venta_id
    )
    if not venta:
        raise HTTPException(status_code=404, detail="Venta no encontrada")

    async with conn.transaction():
        await conn.execute("""
            INSERT INTO reclasificacion_log (
                venta_id, campo_afectado, valor_anterior, valor_nuevo,
                motivo, nota_original, operador, confirmado
            ) VALUES ($1, 'venta_modificada', $2, $3, $4, $5, $6, TRUE)
        """,
            venta_id,
            str(dict(venta)),
            "modificado_por_admin",
            mod.nota_modificacion,
            venta["notas"] or "",
            current_user["nombre"]
        )

        if mod.forma_pago:
            await conn.execute(
                "UPDATE journal_ventas SET forma_pago = $1 WHERE id = $2",
                mod.forma_pago, venta_id
            )
        if mod.total_venta is not None:
            await conn.execute(
                "UPDATE journal_ventas SET total_venta = $1, precio_final_total = $1 WHERE id = $2",
                mod.total_venta, venta_id
            )

        if mod.lineas:
            await conn.execute("DELETE FROM lineas_venta WHERE venta_id = $1", venta_id)
            total_final = 0
            for linea in mod.lineas:
                subtotal = linea.precio_unitario_final * linea.cantidad
                total_final += subtotal
                await conn.execute("""
                    INSERT INTO lineas_venta (
                        venta_id, producto_id, item_donacion_id,
                        cantidad, precio_unitario_standard, precio_unitario_final, subtotal, notas
                    ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
                """,
                    venta_id, linea.producto_id, linea.item_donacion_id,
                    linea.cantidad, linea.precio_unitario_standard, linea.precio_unitario_final,
                    subtotal, linea.notas
                )
            await conn.execute(
                "UPDATE journal_ventas SET total_venta = $1, precio_final_total = $1 WHERE id = $2",
                total_final, venta_id
            )

    return {"message": "Venta modificada por administrador", "venta_id": venta_id, "nota": mod.nota_modificacion}
