"""
FeriaApp API v2.1 — Modelos Pydantic: Ventas y Líneas
"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class LineaVentaIn(BaseModel):
    """Línea de venta individual dentro de una venta."""
    producto_id: Optional[int] = None
    item_donacion_id: Optional[int] = None
    cantidad: float = 1.0
    precio_unitario_standard: Optional[int] = None
    precio_unitario_final: int
    notas: Optional[str] = None


class VentaIn(BaseModel):
    """Registrar venta completa con líneas."""
    evento_feria_id: int
    forma_pago: str  # efectivo, transferencia, diferido, debito, credito, trueque
    lineas: List[LineaVentaIn]
    perfil_cliente: Optional[str] = "sin_definir"
    cliente_frecuente_id: Optional[int] = None
    venta_directa_sin_bodega: bool = False
    garantia_devolucion: bool = False
    notas: Optional[str] = None


class VentaOut(BaseModel):
    id: int
    uuid: Optional[str] = None
    evento_feria_id: int
    usuario_id: int
    dispositivo_id: int
    timestamp_local: Optional[datetime] = None
    forma_pago: str
    estado_pago: str
    total_venta: int
    precio_standard_total: Optional[int] = None
    precio_final_total: int
    diferencia_rebaja: Optional[int] = None
    porcentaje_rebaja: Optional[float] = None
    tipo_rebaja: Optional[str] = None
    motivo_rebaja: Optional[str] = None
    sync_estado: str
    notas: Optional[str] = None
    created_at: Optional[datetime] = None


class ModificacionVentaIn(BaseModel):
    """Admin modifica venta existente. Requiere nota explicativa."""
    lineas: Optional[List[LineaVentaIn]] = None
    forma_pago: Optional[str] = None
    total_venta: Optional[int] = None
    precio_final_total: Optional[int] = None
    nota_modificacion: str  # Obligatorio: explicar por qué se modifica


class VentaResumenEvento(BaseModel):
    """Resumen de ventas agrupado por producto o forma de pago."""
    producto_id: Optional[int] = None
    nombre_producto: Optional[str] = None
    cantidad_vendida: float
    total_recaudado: int
    forma_pago: Optional[str] = None
