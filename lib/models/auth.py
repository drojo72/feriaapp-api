"""Modelos Pydantic para Auth"""
from pydantic import BaseModel
from typing import Optional

class LoginRequest(BaseModel):
    email: str
    password: str

class Token(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int
    token_type: str = "bearer"

class TokenRefresh(BaseModel):
    refresh_token: str

class UsuarioOut(BaseModel):
    id: int
    nombre: str
    # agrega otros campos que necesites (email, etc.)
    activo: bool = True
