"""
FeriaApp API v2.1 — Router: Sync (batch offline que realmente aplica cambios)
Frugal: insert/update/delete reales con log de auditoría.
"""
from typing import List
from fastapi import APIRouter, Depends, HTTPException

from lib.core.database import get_db
from lib.core.security import get_current_user

router = APIRouter(prefix="/sync", tags=["Sync"])


@router.post("/batch")
async def sync_batch(
    batch: List[dict],
    conn=Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Recibir batch de operaciones offline y aplicarlas realmente.

    Cada operación debe tener: {tabla, operacion, datos, timestamp_local, dispositivo_id}
    """
    results = []
    async with conn.transaction():
        for op in batch:
            tabla = op.get("tabla")
            operacion = op.get("operacion")  # insert, update, delete
            datos = op.get("datos", {})
            timestamp_local = op.get("timestamp_local")
            dispositivo_id = op.get("dispositivo_id", 1)
            registro_id = datos.get("id", 0)

            try:
                if operacion == "insert":
                    campos = list(datos.keys())
                    valores = list(datos.values())
                    placeholders = ", ".join([f"${i+1}" for i in range(len(valores))])
                    query = f"INSERT INTO {tabla} ({', '.join(campos)}) VALUES ({placeholders}) RETURNING id"
                    new_id = await conn.fetchval(query, *valores)
                    registro_id = new_id

                elif operacion == "update":
                    pk = datos.pop("id", None)
                    if pk is None:
                        raise ValueError("Update requiere campo 'id'")
                    campos = list(datos.keys())
                    valores = list(datos.values())
                    sets = ", ".join([f"{c} = ${i+1}" for i, c in enumerate(campos)])
                    query = f"UPDATE {tabla} SET {sets} WHERE id = ${len(valores) + 1}"
                    await conn.execute(query, *valores, pk)

                elif operacion == "delete":
                    pk = datos.get("id")
                    if pk is None:
                        raise ValueError("Delete requiere campo 'id'")
                    await conn.execute(f"DELETE FROM {tabla} WHERE id = $1", pk)

                else:
                    raise ValueError(f"Operación no soportada: {operacion}")

                await conn.execute("""
                    INSERT INTO sync_log (dispositivo_id, usuario_id, tabla_afectada,
                        registro_id, operacion, timestamp_local, estado, detalle)
                    VALUES ($1, $2, $3, $4, $5, $6, 'ok', 'Aplicado exitosamente')
                """, dispositivo_id, current_user["id"], tabla, registro_id, operacion, timestamp_local)

                results.append({"status": "ok", "tabla": tabla, "operacion": operacion, "id": registro_id})

            except Exception as e:
                await conn.execute("""
                    INSERT INTO sync_log (dispositivo_id, usuario_id, tabla_afectada,
                        registro_id, operacion, timestamp_local, estado, detalle)
                    VALUES ($1, $2, $3, $4, $5, $6, 'error', $7)
                """, dispositivo_id, current_user["id"], tabla, registro_id, operacion, timestamp_local, str(e))
                results.append({"status": "error", "tabla": tabla, "error": str(e)})

    return {"procesados": len(batch), "exitosos": sum(1 for r in results if r["status"] == "ok"), "resultados": results}
