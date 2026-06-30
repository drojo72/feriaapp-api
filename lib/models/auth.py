"""
FeriaApp API v2.1 — Modelos Pydantic: Auth
"""
from pydantic import BaseModel
from typing import Optional


class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class TokenRefresh(BaseModel):
    refresh_token: str


class UsuarioOut(BaseModel):
    id: int
    nombre: str
    rol: str
    activo: bool


class UsuarioLogin(BaseModel):
    nombre: str
    password: str
