"""
FeriaApp API v2.1 — Router: Auditoría
Consulta el historial de cambios con justificación
"""
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query

from lib.core.database import get_db
from lib.core.security import get_current_user, require_admin

router = APIRouter(prefix="/auditoria", tags=["Auditoría"])


@router.get("/")
async def listar_auditoria(
    tipo: Optional[str] = Query(None, description="Filtrar por tipo: reabrir, modificar, stock, producto"),
    search: Optional[str] = Query(None, description="Buscar en motivo, operador, detalle"),
    fecha_desde: Optional[str] = Query(None, description="Fecha inicio (YYYY-MM-DD)"),
    fecha_hasta: Optional[str] = Query(None, description="Fecha fin (YYYY-MM-DD)"),
    limit: int = Query(100, ge=1, le=500),
    offset: int = Query(0, ge=0),
    conn=Depends(get_db),
    current_user=Depends(require_admin)
):
    """
    Listar registros de auditoría con justificación.
    Solo accesible para administradores.
    """
    query = """
        SELECT
            rl.id,
            rl.venta_id,
            rl.campo_afectado,
            rl.valor_anterior,
            rl.valor_nuevo,
            rl.motivo as justificacion,
            rl.nota_original,
            rl.operador as usuario_nombre,
            rl.confirmado,
            rl.fecha_cambio as created_at,
            CASE
                WHEN rl.campo_afectado = 'evento_reabierto' THEN 'reabrir'
                WHEN rl.campo_afectado LIKE 'venta_%' THEN 'modificar'
                WHEN rl.campo_afectado = 'stock' OR rl.campo_afectado LIKE 'stock_%' THEN 'stock'
                WHEN rl.campo_afectado LIKE 'producto_%' THEN 'producto'
                ELSE 'otro'
            END as tipo,
            CASE
                WHEN rl.campo_afectado = 'evento_reabierto' THEN 'Reapertura de evento'
                WHEN rl.campo_afectado LIKE 'venta_%' THEN 'Modificación de venta'
                WHEN rl.campo_afectado = 'stock' OR rl.campo_afectado LIKE 'stock_%' THEN 'Ajuste de stock'
                WHEN rl.campo_afectado LIKE 'producto_%' THEN 'Cambio de producto'
                ELSE rl.campo_afectado
            END as detalle
        FROM reclasificacion_log rl
        WHERE 1=1
    """
    params = []

    if tipo:
        tipo_map = {
            'reabrir': "rl.campo_afectado = 'evento_reabierto'",
            'modificar': "rl.campo_afectado LIKE 'venta_%'",
            'stock': "rl.campo_afectado = 'stock' OR rl.campo_afectado LIKE 'stock_%'",
            'producto': "rl.campo_afectado LIKE 'producto_%'"
        }
        if tipo in tipo_map:
            query += " AND " + tipo_map[tipo]
        else:
            query += " AND rl.campo_afectado = $" + str(len(params) + 1)
            params.append(tipo)

    if search:
        query += " AND (rl.motivo ILIKE $" + str(len(params) + 1) + " OR rl.operador ILIKE $" + str(len(params) + 2) + " OR rl.campo_afectado ILIKE $" + str(len(params) + 3) + ")"
        search_term = f"%{search}%"
        params.extend([search_term, search_term, search_term])

    if fecha_desde:
        query += " AND rl.fecha_cambio >= $" + str(len(params) + 1) + "::date"
        params.append(fecha_desde)

    if fecha_hasta:
        query += " AND rl.fecha_cambio <= $" + str(len(params) + 1) + "::date"
        params.append(fecha_hasta)

    count_query = query.replace(
        "SELECT \n            rl.id,\n            rl.venta_id,\n            rl.campo_afectado,\n            rl.valor_anterior,\n            rl.valor_nuevo,\n            rl.motivo as justificacion,\n            rl.nota_original,\n            rl.operador as usuario_nombre,\n            rl.confirmado,\n            rl.fecha_cambio as created_at,\n            CASE \n                WHEN rl.campo_afectado = 'evento_reabierto' THEN 'reabrir'\n                WHEN rl.campo_afectado LIKE 'venta_%' THEN 'modificar'\n                WHEN rl.campo_afectado = 'stock' OR rl.campo_afectado LIKE 'stock_%' THEN 'stock'\n                WHEN rl.campo_afectado LIKE 'producto_%' THEN 'producto'\n                ELSE 'otro'\n            END as tipo,\n            CASE \n                WHEN rl.campo_afectado = 'evento_reabierto' THEN 'Reapertura de evento'\n                WHEN rl.campo_afectado LIKE 'venta_%' THEN 'Modificación de venta'\n                WHEN rl.campo_afectado = 'stock' OR rl.campo_afectado LIKE 'stock_%' THEN 'Ajuste de stock'\n                WHEN rl.campo_afectado LIKE 'producto_%' THEN 'Cambio de producto'\n                ELSE rl.campo_afectado\n            END as detalle",
        "SELECT COUNT(*) as total"
    )

    total = await conn.fetchval(count_query, *params)

    query += " ORDER BY rl.fecha_cambio DESC LIMIT $" + str(len(params) + 1) + " OFFSET $" + str(len(params) + 2)
    params.extend([limit, offset])

    rows = await conn.fetch(query, *params)

    return {
        "items": [dict(r) for r in rows],
        "total": total,
        "limit": limit,
        "offset": offset
    }


@router.get("/resumen")
async def resumen_auditoria(
    conn=Depends(get_db),
    current_user=Depends(require_admin)
):
    """Estadísticas de auditoría"""
    tipos = await conn.fetch("""
        SELECT
            CASE
                WHEN campo_afectado = 'evento_reabierto' THEN 'reabrir'
                WHEN campo_afectado LIKE 'venta_%' THEN 'modificar'
                WHEN campo_afectado = 'stock' OR campo_afectado LIKE 'stock_%' THEN 'stock'
                WHEN campo_afectado LIKE 'producto_%' THEN 'producto'
                ELSE 'otro'
            END as tipo,
            COUNT(*) as total
        FROM reclasificacion_log
        GROUP BY tipo
        ORDER BY total DESC
    """)

    usuarios = await conn.fetch("""
        SELECT
            operador as usuario,
            COUNT(*) as total
        FROM reclasificacion_log
        WHERE operador IS NOT NULL
        GROUP BY operador
        ORDER BY total DESC
        LIMIT 10
    """)

    ultimos_dias = await conn.fetch("""
        SELECT
            DATE(fecha_cambio) as fecha,
            COUNT(*) as total
        FROM reclasificacion_log
        WHERE fecha_cambio >= NOW() - INTERVAL '7 days'
        GROUP BY DATE(fecha_cambio)
        ORDER BY fecha DESC
    """)

    return {
        "por_tipo": [dict(r) for r in tipos],
        "por_usuario": [dict(r) for r in usuarios],
        "ultimos_7_dias": [dict(r) for r in ultimos_dias],
        "total_general": sum(r['total'] for r in tipos)
    }
