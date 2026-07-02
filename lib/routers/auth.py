"""
FeriaApp API v2.1 — Router: Auth (JSON puro)
"""

from fastapi import APIRouter, Depends, HTTPException, Body
from pydantic import BaseModel

from lib.core.database import get_db
from lib.core.security import (
    verify_password, create_access_token, create_refresh_token,
    get_current_user
)
from lib.core.config import settings
from lib.models.auth import Token, TokenRefresh, UsuarioOut, LoginRequest   # ← importante

router = APIRouter(prefix="/auth", tags=["Auth"])

class LoginRequest(BaseModel):
    email: str
    password: str

@router.post("/login", response_model=Token)
async def login(login_data: LoginRequest 0 Body(...), conn=Depends(get_db)):
    """Login con JSON"""
    user = await conn.fetchrow(
        """
        SELECT id, nombre, password_hash, activo
        FROM usuarios
        WHERE (email = $1 OR nombre = $1)
        """,
        login_data.email
    )

    if not user or not verify_password(login_data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Usuario o contraseña incorrectos")

    if not user["activo"]:
        raise HTTPException(status_code=403, detail="Usuario desactivado")

    access_token = create_access_token({"sub": str(user["id"]), "name": user["nombre"]})
    refresh_token = create_refresh_token({"sub": str(user["id"])})

    return Token(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.access_token_expire_minutes * 60
    )


# Mantén igual el resto (/refresh y /me) ...
@router.post("/refresh", response_model=Token)
async def refresh_token(token_data: TokenRefresh, conn=Depends(get_db)):
    from jose import jwt, JWTError
    try:
        payload = jwt.decode(token_data.refresh_token, settings.secret_key, algorithms=[settings.algorithm])
        user_id = payload.get("sub")
        if user_id is None or payload.get("type") != "refresh":
            raise HTTPException(status_code=401, detail="Refresh token inválido")
    except JWTError:
        raise HTTPException(status_code=401, detail="Refresh token inválido")

    user = await conn.fetchrow("SELECT id, nombre, activo FROM usuarios WHERE id = $1", int(user_id))
    if not user or not user["activo"]:
        raise HTTPException(status_code=401, detail="Usuario inválido")

    access_token = create_access_token({"sub": str(user["id"]), "name": user["nombre"]})
    refresh_token = create_refresh_token({"sub": str(user["id"])})

    return Token(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.access_token_expire_minutes * 60
    )


@router.get("/me", response_model=UsuarioOut)
async def me(current_user=Depends(get_current_user)):
    return current_user
