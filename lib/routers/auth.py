"""
FeriaApp API v2.1 — Router: Auth (login, refresh, me)
Frugal: solo JWT con refresh rotation.
"""
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import OAuth2PasswordRequestForm

from lib.core.database import get_db
from lib.core.security import (
    verify_password, hash_password, create_access_token, create_refresh_token,
    get_current_user
)
from lib.core.config import settings
from lib.models.auth import Token, TokenRefresh, UsuarioOut

router = APIRouter(prefix="/auth", tags=["Auth"])


@router.post("/login", response_model=Token)
async def login(form_data: OAuth2PasswordRequestForm = Depends(), conn=Depends(get_db)):
    """Login con nombre de usuario y contraseña. Retorna access + refresh tokens."""
    user = await conn.fetchrow(
        "SELECT id, nombre, password_hash, activo FROM usuarios WHERE nombre = $1",
        form_data.username
    )
    
    if not user:
        raise HTTPException(status_code=401, detail="Usuario o contraseña incorrectos")
    
    if not verify_password(form_data.password, user["password_hash"]):
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


@router.post("/refresh", response_model=Token)
async def refresh_token(token_data: TokenRefresh, conn=Depends(get_db)):
    """Refrescar access token con refresh token válido."""
    from jose import jwt, JWTError
    try:
        payload = jwt.decode(token_data.refresh_token, settings.secret_key, algorithms=[settings.algorithm])
        user_id = payload.get("sub")
        token_type = payload.get("type")
        if user_id is None or token_type != "refresh":
            raise HTTPException(status_code=401, detail="Refresh token inválido")
    except JWTError:
        raise HTTPException(status_code=401, detail="Refresh token expirado o inválido")

    user = await conn.fetchrow("SELECT id, nombre, activo FROM usuarios WHERE id = $1", int(user_id))
    if not user or not user["activo"]:
        raise HTTPException(status_code=401, detail="Usuario no encontrado o inactivo")

    access_token = create_access_token({"sub": str(user["id"]), "name": user["nombre"]})
    refresh_token = create_refresh_token({"sub": str(user["id"])})

    return Token(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.access_token_expire_minutes * 60
    )


@router.get("/me", response_model=UsuarioOut)
async def me(current_user=Depends(get_current_user)):
    """Usuario autenticado actual."""
    return current_user
