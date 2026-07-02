"""
FeriaApp API v2.1 — Modelos Pydantic: Productos y Bodega
"""
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, date


class ProductoOut(BaseModel):
    id: int
    nombre: str
    categoria_feriaapp_id: Optional[int] = None
    subcategoria_feriaapp_id: Optional[int] = None
    categoria_revistete_id: Optional[int] = None
    subcategoria_revistete_id: Optional[int] = None
    genero_id: Optional[int] = None
    segmento_edad_id: Optional[int] = None
    talla: Optional[str] = None
    talla_numerica: Optional[int] = None
    precio_online: Optional[int] = None
    precio_feria: Optional[int] = None
    precio_standard: Optional[int] = None
    precio_final: Optional[int] = None
    estado: str = "disponible"
    condicion: Optional[str] = None
    marca: Optional[str] = None
    nivel_calidad_id: Optional[int] = None
    temporada_id: Optional[int] = None
    temporadas_en_inventario: int = 0
    descripcion_defectos: Optional[str] = None
    fotos: Optional[list] = None
    notas: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    historia_origen: Optional[str] = None
    historia_ubicacion: Optional[str] = None
    historia_motivo: Optional[str] = None
    historia_tags: Optional[List[str]] = None
    qr_code: Optional[str] = None
    fecha_recepcion: Optional[date] = None
    clasificado_por_id: Optional[int] = None


class ProductoCreate(BaseModel):
    nombre: str
    categoria_feriaapp_id: Optional[int] = None
    categoria_revistete_id: Optional[int] = None
    subcategoria_revistete_id: Optional[int] = None
    genero_id: Optional[int] = None
    segmento_edad_id: Optional[int] = None
    talla: Optional[str] = None
    talla_numerica: Optional[int] = None
    medidas: Optional[dict] = None
    precio_online: Optional[int] = None
    precio_feria: Optional[int] = None
    precio_standard: Optional[int] = None
    precio_final: Optional[int] = None
    condicion: Optional[str] = None
    marca: Optional[str] = None
    nivel_calidad_id: Optional[int] = None
    temporada_id: Optional[int] = None
    descripcion: Optional[str] = None
    descripcion_defectos: Optional[str] = None
    fotos: Optional[list] = None
    notas: Optional[str] = None
    historia_origen: Optional[str] = None
    historia_ubicacion: Optional[str] = None
    historia_motivo: Optional[str] = None
    historia_tags: Optional[List[str]] = None
    fecha_recepcion: Optional[date] = None


class ProductoUpdate(BaseModel):
    nombre: Optional[str] = None
    categoria_feriaapp_id: Optional[int] = None
    categoria_revistete_id: Optional[int] = None
    subcategoria_revistete_id: Optional[int] = None
    genero_id: Optional[int] = None
    segmento_edad_id: Optional[int] = None
    talla: Optional[str] = None
    talla_numerica: Optional[int] = None
    medidas: Optional[dict] = None
    precio_online: Optional[int] = None
    precio_feria: Optional[int] = None
    precio_standard: Optional[int] = None
    precio_final: Optional[int] = None
    condicion: Optional[str] = None
    estado: Optional[str] = None
    marca: Optional[str] = None
    nivel_calidad_id: Optional[int] = None
    temporada_id: Optional[int] = None
    descripcion: Optional[str] = None
    descripcion_defectos: Optional[str] = None
    fotos: Optional[list] = None
    notas: Optional[str] = None
    historia_origen: Optional[str] = None
    historia_ubicacion: Optional[str] = None
    historia_motivo: Optional[str] = None
    historia_tags: Optional[List[str]] = None


class MovimientoPrendaIn(BaseModel):
    canal_origen: Optional[str] = None
    canal_destino: str
    motivo: str
    notas: Optional[str] = None
