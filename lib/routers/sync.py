"""
FeriaApp API v2.1 — Router: Sync (batch offline que realmente aplica cambios)
OPTIMIZADO: Soporta campos redundantes, mejor logging y manejo de conflictos
"""
from typing import List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException

from lib.core.database import get_db
from lib.core.security import get_current_user

router = APIRouter(prefix="/sync", tags=["Sync"])


@router.post("/batch")
async def sync_batch(
    batch: List[Dict[str, Any]],
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """
    Recibir batch de operaciones offline y aplicarlas realmente.

    Cada operación debe tener:
    {
        "tabla": "productos",
        "operacion": "insert|update|delete",
        "datos": {...},
        "timestamp_local": "2026-06-18T14:00:00",
        "dispositivo_id": 1
    }

    OPTIMIZADO: Manejo de campos redundantes para eventos_feria y journal_ventas
    """
    results = []
    conflictos = []

    async with conn.transaction():
        for idx, op in enumerate(batch):
            tabla = op.get("tabla")
            operacion = op.get("operacion")
            datos = op.get("datos", {})
            timestamp_local = op.get("timestamp_local")
            dispositivo_id = op.get("dispositivo_id", 1)
            registro_id = datos.get("id", 0)

            try:
                # Validar tabla permitida
                tablas_permitidas = [
                    'productos', 'eventos_feria', 'journal_ventas',
                    'lineas_venta', 'clientes_frecuentes', 'etiquetas',
                    'items_donacion', 'flujo_prenda'
                ]
                if tabla not in tablas_permitidas:
                    raise ValueError(f"Tabla no permitida: {tabla}")

                if operacion == "insert":
                    # Remover id si viene (dejamos que la DB lo genere)
                    datos.pop("id", None)

                    # Para eventos_feria y journal_ventas, los campos redundantes
                    # se llenarán automáticamente por triggers
                    campos = list(datos.keys())
                    valores = list(datos.values())
                    placeholders = ", ".join([f"${i+1}" for i in range(len(valores))])
                    query = f"""
                        INSERT INTO {tabla} ({', '.join(campos)})
                        VALUES ({placeholders})
                        RETURNING id
                    """
                    new_id = await conn.fetchval(query, *valores)
                    registro_id = new_id

                elif operacion == "update":
                    pk = datos.pop("id", None)
                    if pk is None:
                        raise ValueError("Update requiere campo 'id'")

                    # Si es eventos_feria o journal_ventas, actualizar campos redundantes
                    # Los triggers lo harán automáticamente
                    campos = list(datos.keys())
                    valores = list(datos.values())
                    sets = ", ".join([f"{c} = ${i+1}" for i, c in enumerate(campos)])
                    query = f"""
                        UPDATE {tabla}
                        SET {sets}
                        WHERE id = ${len(valores) + 1}
                    """
                    await conn.execute(query, *valores, pk)
                    registro_id = pk

                elif operacion == "delete":
                    pk = datos.get("id")
                    if pk is None:
                        raise ValueError("Delete requiere campo 'id'")

                    # Para eventos_feria, también limpiar ventas relacionadas o notificar
                    if tabla == "eventos_feria":
                        # Verificar que no tenga ventas
                        ventas_count = await conn.fetchval(
                            "SELECT COUNT(*) FROM journal_ventas WHERE evento_feria_id = $1",
                            pk
                        )
                        if ventas_count > 0:
                            raise ValueError(
                                f"No se puede eliminar evento con {ventas_count} ventas asociadas"
                            )

                    await conn.execute(f"DELETE FROM {tabla} WHERE id = $1", pk)

                else:
                    raise ValueError(f"Operación no soportada: {operacion}")

                # Registrar éxito en sync_log
                await conn.execute("""
                    INSERT INTO sync_log (
                        dispositivo_id, usuario_id, tabla_afectada,
                        registro_id, operacion, timestamp_local, estado, detalle
                    ) VALUES ($1, $2, $3, $4, $5, $6, 'ok', 'Aplicado exitosamente')
                """, dispositivo_id, current_user["id"], tabla, registro_id,
                    operacion, timestamp_local)

                results.append({
                    "status": "ok",
                    "tabla": tabla,
                    "operacion": operacion,
                    "id": registro_id
                })

            except Exception as e:
                error_msg = str(e)
                # Registrar error en sync_log
                await conn.execute("""
                    INSERT INTO sync_log (
                        dispositivo_id, usuario_id, tabla_afectada,
                        registro_id, operacion, timestamp_local, estado, detalle
                    ) VALUES ($1, $2, $3, $4, $5, $6, 'error', $7)
                """, dispositivo_id, current_user["id"], tabla, registro_id,
                    operacion, timestamp_local, error_msg)

                # Guardar conflicto para respuesta
                conflictos.append({
                    "index": idx,
                    "tabla": tabla,
                    "operacion": operacion,
                    "error": error_msg,
                    "datos": datos
                })

                results.append({
                    "status": "error",
                    "tabla": tabla,
                    "operacion": operacion,
                    "error": error_msg
                })

    return {
        "procesados": len(batch),
        "exitosos": sum(1 for r in results if r["status"] == "ok"),
        "errores": len(conflictos),
        "resultados": results,
        "conflictos": conflictos if conflictos else None
    }


@router.get("/pendientes")
async def sync_pendientes(
    dispositivo_id: Optional[int] = None,
    limit: int = 100,
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """
    Obtener operaciones pendientes de sincronización para un dispositivo
    """
    query = """
        SELECT id, dispositivo_id, tabla_afectada, registro_id,
               operacion, timestamp_local, estado, detalle, created_at
        FROM sync_log
        WHERE estado = 'error' OR estado = 'pendiente'
    """
    params = []

    if dispositivo_id:
        query += " AND dispositivo_id = $" + str(len(params) + 1)
        params.append(dispositivo_id)

    query += " ORDER BY created_at DESC LIMIT $" + str(len(params) + 1)
    params.append(limit)

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]


@router.post("/conflictos/resolver")
async def resolver_conflicto(
    sync_log_id: int,
    accion: str,  # 'ignorar', 'sobrescribir', 'cancelar'
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """
    Resolver conflictos de sincronización manualmente

    Acciones:
    - 'ignorar': Marcar como resuelto y continuar
    - 'sobrescribir': Forzar la operación
    - 'cancelar': Revertir cambios
    """
    if accion not in ['ignorar', 'sobrescribir', 'cancelar']:
        raise HTTPException(
            status_code=400,
            detail="Acción inválida. Opciones: ignorar, sobrescribir, cancelar"
        )

    # Obtener log de conflicto
    log = await conn.fetchrow(
        "SELECT * FROM sync_log WHERE id = $1", sync_log_id
    )
    if not log:
        raise HTTPException(status_code=404, detail="Log de sincronización no encontrado")

    if log["estado"] != "error":
        raise HTTPException(status_code=400, detail="Este log no tiene errores")

    if accion == "ignorar":
        await conn.execute("""
            UPDATE sync_log
            SET estado = 'resuelto',
                detalle = CONCAT(detalle, ' | Ignorado por admin: ', CURRENT_TIMESTAMP)
            WHERE id = $1
        """, sync_log_id)

    elif accion == "sobrescribir":
        # Reintentar la operación
        # Aquí iría lógica para reintentar
        await conn.execute("""
            UPDATE sync_log
            SET estado = 'pendiente',
                detalle = CONCAT(detalle, ' | Reintentando por admin: ', CURRENT_TIMESTAMP)
            WHERE id = $1
        """, sync_log_id)

    elif accion == "cancelar":
        await conn.execute("""
            UPDATE sync_log
            SET estado = 'cancelado',
                detalle = CONCAT(detalle, ' | Cancelado por admin: ', CURRENT_TIMESTAMP)
            WHERE id = $1
        """, sync_log_id)

    return {
        "message": f"Conflicto {accion} exitosamente",
        "sync_log_id": sync_log_id,
        "accion": accion
    }


@router.get("/estadisticas")
async def sync_estadisticas(
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """
    Estadísticas de sincronización
    """
    stats = await conn.fetchrow("""
        SELECT
            COUNT(*) as total,
            COUNT(CASE WHEN estado = 'ok' THEN 1 END) as exitosos,
            COUNT(CASE WHEN estado = 'error' THEN 1 END) as errores,
            COUNT(CASE WHEN estado = 'pendiente' THEN 1 END) as pendientes,
            COUNT(CASE WHEN estado = 'resuelto' THEN 1 END) as resueltos,
            COUNT(CASE WHEN estado = 'cancelado' THEN 1 END) as cancelados
        FROM sync_log
    """)

    # Por tabla
    por_tabla = await conn.fetch("""
        SELECT
            tabla_afectada,
            COUNT(*) as total,
            COUNT(CASE WHEN estado = 'ok' THEN 1 END) as exitosos,
            COUNT(CASE WHEN estado = 'error' THEN 1 END) as errores
        FROM sync_log
        GROUP BY tabla_afectada
        ORDER BY total DESC
    """)

    return {
        "totales": dict(stats),
        "por_tabla": [dict(r) for r in por_tabla]
    }
