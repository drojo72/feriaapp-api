"""
FeriaApp API v2.1 — Modelos Pydantic: Eventos
"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class EventoCreate(BaseModel):
    canal_venta_id: int
    fecha: str  # ISO date YYYY-MM-DD
    lugar: str


class EventoOut(BaseModel):
    id: int
    canal_venta_id: int
    fecha: str
    lugar: str
    vendedor_principal_id: int
    estado: str
    total_calculado: int
    total_confirmado: Optional[int] = None
    diferencia: Optional[int] = None
    revisado_por_id: Optional[int] = None
    fecha_revision: Optional[datetime] = None
    fecha_cierre: Optional[datetime] = None
    notas: Optional[str] = None
    created_at: Optional[datetime] = None


class EventoResumen(BaseModel):
    """Resumen de evento con totales por producto y forma de pago."""
    evento_id: int
    fecha: str
    lugar: str
    estado: str
    total_ventas: int
    total_recaudado: int
    total_efectivo: int
    total_transferencia: int
    total_diferido: int
    total_rebajas: int
    productos_vendidos: List[dict]
    formas_pago: List[dict]


class EventoCierreIn(BaseModel):
    total_confirmado: int
    notas: Optional[str] = None


class EventoReaperturaIn(BaseModel):
    nota_reapertura: str  # Obligatorio: por qué se reabre
