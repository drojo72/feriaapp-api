"""
FeriaApp API v2.1 — Seguridad: JWT, bcrypt, dependencias de auth
Frugal: HS256, bcrypt nativo (compatible PHP $2y$), sin overhead.
"""
from datetime import datetime, timedelta
from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
import bcrypt

from lib.core.config import settings
from lib.core.database import get_db

# Esquema OAuth2 para Bearer token
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")


# ============================================
# BCRYPT (compatible con hashes PHP $2y$)
# ============================================

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verificar contraseña con bcrypt. Compatible con PHP ($2y$) y Python ($2b$)."""
    try:
        # Si es hash PHP, convertir a $2b$ para Python
        if hashed_password.startswith("$2y$"):
            hash_to_check = hashed_password.replace("$2y$", "$2b$", 1)
        else:
            hash_to_check = hashed_password

        plain = plain_password.encode('utf-8')
        hashed = hash_to_check.encode('utf-8')

        return bcrypt.checkpw(plain, hashed)

    except ValueError as e:
        # Si falla, intentar con el hash original sin conversión
        if "$2y$" in hashed_password:
            try:
                return bcrypt.checkpw(
                    plain_password.encode('utf-8'),
                    hashed_password.encode('utf-8')
                )
            except:
                pass
        print(f"⚠️ Error verificando contraseña: {e}")
        return False
    except Exception as e:
        print(f"⚠️ Error inesperado: {e}")
        return False


def hash_password(password: str) -> str:
    """Generar hash bcrypt para nueva contraseña."""
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')


# ============================================
# UTILIDADES JWT
# ============================================

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """Generar access token JWT con expiración."""
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=settings.access_token_expire_minutes))
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)


def create_refresh_token(data: dict) -> str:
    """Generar refresh token JWT con expiración extendida."""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=settings.refresh_token_expire_days)
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, settings.secret_key, algorithm=settings.algorithm)


async def get_current_user(token: str = Depends(oauth2_scheme), conn=Depends(get_db)):
    """Dependencia FastAPI: valida access token y retorna usuario activo.
    
    Lanza 401 si token inválido, expirado, o usuario inactivo.
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Credenciales inválidas",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.secret_key, algorithms=[settings.algorithm])
        user_id: str = payload.get("sub")
        token_type: str = payload.get("type")
        if user_id is None or token_type != "access":
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = await conn.fetchrow(
        "SELECT id, nombre, rol, activo FROM usuarios WHERE id = $1", int(user_id)
    )
    if user is None or not user["activo"]:
        raise credentials_exception
    return dict(user)


async def require_admin(current_user=Depends(get_current_user)):
    """Dependencia: solo administrador (propietario). 
    
    Excepción: Claudio (id=1) siempre es admin.
    """
    if current_user["rol"] != "propietario" and current_user["id"] != 1:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Requiere permisos de administrador"
        )
    return current_user
