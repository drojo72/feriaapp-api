"""
FeriaApp API v2.1 — Router: Eventos (CRUD, cierre, reapertura, resumen)
Frugal: eventos siempre abiertos hasta cierre manual. Solo admin reabre.
"""
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException

from lib.core.database import get_db
from lib.core.security import get_current_user, require_admin
from lib.models.eventos import EventoCreate, EventoOut, EventoCierreIn, EventoReaperturaIn

router = APIRouter(prefix="/eventos", tags=["Eventos"])


@router.get("/", response_model=List[dict])
async def listar_eventos(
    estado: Optional[str] = None,
    tipo_canal: Optional[str] = None,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Listar eventos. Filtros por estado y tipo de canal."""
    query = """
        SELECT ef.id, ef.fecha, ef.lugar, ef.estado, ef.total_calculado,
               ef.total_confirmado, ef.diferencia,
               cv.nombre as canal_venta, cv.tipo as tipo_canal,
               u.nombre as vendedor_principal
        FROM eventos_feria ef
        JOIN canales_venta cv ON ef.canal_venta_id = cv.id
        JOIN usuarios u ON ef.vendedor_principal_id = u.id
        WHERE 1=1
    """
    params = []
    if estado:
        query += " AND ef.estado = $" + str(len(params) + 1)
        params.append(estado)
    if tipo_canal:
        query += " AND cv.tipo = $" + str(len(params) + 1)
        params.append(tipo_canal)
    query += " ORDER BY ef.fecha DESC"

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]


@router.post("/", response_model=dict, status_code=201)
async def crear_evento(
    evento: EventoCreate,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Crear nuevo evento de feria. Siempre inicia como 'activo'."""
    from datetime import datetime
    
    # Verificar que el canal de venta existe
    canal = await conn.fetchrow(
        "SELECT id FROM canales_venta WHERE id = $1", evento.canal_venta_id
    )
    if not canal:
        raise HTTPException(
            status_code=400, 
            detail=f"Canal de venta id={evento.canal_venta_id} no existe"
        )

    # Parsear fecha string a date object
    try:
        fecha_parsed = datetime.strptime(evento.fecha, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(
            status_code=400,
            detail="Formato de fecha inválido. Use YYYY-MM-DD"
        )

    try:
        evento_id = await conn.fetchval("""
            INSERT INTO eventos_feria (canal_venta_id, fecha, lugar, vendedor_principal_id, estado, total_calculado)
            VALUES ($1, $2, $3, $4, 'activo', 0)
            RETURNING id
        """, evento.canal_venta_id, fecha_parsed, evento.lugar, current_user["id"])
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error al crear evento: {str(e)}")

    return {"id": evento_id, "estado": "activo", "message": "Evento creado. Requiere cierre manual."}


@router.get("/{evento_id}")
async def obtener_evento(
    evento_id: int,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Obtener evento con detalle de ventas."""
    evento = await conn.fetchrow("""
        SELECT ef.*, cv.nombre as canal_venta, cv.tipo as tipo_canal,
               u.nombre as vendedor_principal
        FROM eventos_feria ef
        JOIN canales_venta cv ON ef.canal_venta_id = cv.id
        JOIN usuarios u ON ef.vendedor_principal_id = u.id
        WHERE ef.id = $1
    """, evento_id)
    if not evento:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    return dict(evento)


@router.get("/{evento_id}/resumen")
async def resumen_evento(
    evento_id: int,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Resumen de evento: totales por producto y por forma de pago."""
    evento = await conn.fetchrow(
        "SELECT id, estado, fecha_cierre FROM eventos_feria WHERE id = $1", evento_id
    )
    if not evento:
        raise HTTPException(status_code=404, detail="Evento no encontrado")

    formas_pago = await conn.fetch("""
        SELECT forma_pago, COUNT(*) as cantidad_ventas, SUM(total_venta) as total
        FROM journal_ventas
        WHERE evento_feria_id = $1
        GROUP BY forma_pago
    """, evento_id)

    productos = await conn.fetch("""
        SELECT p.id, p.nombre, SUM(lv.cantidad) as cantidad_vendida,
               SUM(lv.subtotal) as total_recaudado
        FROM lineas_venta lv
        JOIN journal_ventas jv ON lv.venta_id = jv.id
        LEFT JOIN productos p ON lv.producto_id = p.id
        WHERE jv.evento_feria_id = $1
        GROUP BY p.id, p.nombre
        ORDER BY total_recaudado DESC
    """, evento_id)

    totales = await conn.fetchrow("""
        SELECT COUNT(*) as total_ventas, SUM(total_venta) as total_recaudado,
               SUM(COALESCE(diferencia_rebaja, 0)) as total_rebajas
        FROM journal_ventas
        WHERE evento_feria_id = $1
    """, evento_id)

    return {
        "evento": dict(evento),
        "totales": dict(totales) if totales else {},
        "formas_pago": [dict(r) for r in formas_pago],
        "productos": [dict(r) for r in productos]
    }


@router.post("/{evento_id}/cerrar")
async def cerrar_evento(
    evento_id: int,
    cierre: EventoCierreIn,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Cerrar evento. Requiere total_confirmado (revisión manual).

    Una vez cerrado, no se permiten más ventas ni modificaciones desde app móvil.
    """
    evento = await conn.fetchrow(
        "SELECT id, estado, total_calculado FROM eventos_feria WHERE id = $1", evento_id
    )
    if not evento:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    if evento["estado"] == "cerrado":
        raise HTTPException(status_code=400, detail="Evento ya está cerrado")

    diferencia = cierre.total_confirmado - evento["total_calculado"]

    await conn.execute("""
        UPDATE eventos_feria SET
            estado = 'cerrado',
            total_confirmado = $1,
            diferencia = $2,
            revisado_por_id = $3,
            fecha_revision = NOW(),
            fecha_cierre = NOW(),
            notas = COALESCE(notas, '') || ' | Cierre: ' || $4
        WHERE id = $5
    """, cierre.total_confirmado, diferencia, current_user["id"], cierre.notas or "", evento_id)

    return {
        "message": "Evento cerrado exitosamente",
        "evento_id": evento_id,
        "total_confirmado": cierre.total_confirmado,
        "total_calculado": evento["total_calculado"],
        "diferencia": diferencia
    }


@router.post("/{evento_id}/reabrir")
async def reabrir_evento(
    evento_id: int,
    reapertura: EventoReaperturaIn,
    conn=Depends(get_db),
    current_user=Depends(require_admin)
):
    """[ADMIN ONLY] Reabrir evento cerrado. Requiere nota explicativa.

    Solo Claudio (propietario) puede reabrir. Registra log de modificación.
    """
    evento = await conn.fetchrow(
        "SELECT id, estado, total_confirmado, fecha_cierre FROM eventos_feria WHERE id = $1", evento_id
    )
    if not evento:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    if evento["estado"] != "cerrado":
        raise HTTPException(status_code=400, detail="Solo se pueden reabrir eventos cerrados")

    async with conn.transaction():
        await conn.execute("""
            INSERT INTO reclasificacion_log (
                venta_id, campo_afectado, valor_anterior, valor_nuevo,
                motivo, nota_original, operador, confirmado
            ) VALUES (NULL, 'evento_reabierto', $1, 'activo', $2, $3, $4, TRUE)
        """,
            evento["estado"],
            reapertura.nota_reapertura,
            f"Evento {evento_id} cerrado el {evento['fecha_cierre']}",
            current_user["nombre"]
        )

        await conn.execute("""
            UPDATE eventos_feria SET
                estado = 'activo',
                total_confirmado = NULL,
                diferencia = NULL,
                fecha_cierre = NULL,
                notas = COALESCE(notas, '') || ' | Reapertura: ' || $1
            WHERE id = $2
        """, reapertura.nota_reapertura, evento_id)

    return {
        "message": "Evento reabierto por administrador",
        "evento_id": evento_id,
        "nota": reapertura.nota_reapertura
    }
