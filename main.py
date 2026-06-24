"""
FeriaApp API v2.1
FastAPI + PostgreSQL (Neon) + JWT Auth
"""

from fastapi import FastAPI, Depends, HTTPException, status, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime, timedelta
from jose import JWTError, jwt
from passlib.context import CryptContext
import asyncpg
import os
import logging

# Configuración logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuración
SECRET_KEY = os.getenv("SECRET_KEY", "dev-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", 15))
REFRESH_TOKEN_EXPIRE_DAYS = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", 90))
DATABASE_URL = os.getenv("DATABASE_URL")
ENVIRONMENT = os.getenv("ENVIRONMENT", "development")

# App
app = FastAPI(
    title="FeriaApp API",
    description="API para FeriaApp v2.1 - Feria Dominical + Re-Vistete + Granja Toqui",
    version="2.1.0"
)

# CORS
origins = [
    "http://localhost:3000",
    "http://localhost:4321",
    "https://feriaapp.pages.dev",
    "https://keysign-labs.eu.org",
]
if ENVIRONMENT == "development":
    origins.extend(["http://localhost:5173", "http://127.0.0.1:5173"])

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
    allow_headers=["Authorization", "Content-Type", "X-Requested-With"],
    max_age=3600,
)

# Seguridad
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")

# Pool de conexiones PostgreSQL
pool: Optional[asyncpg.Pool] = None

async def get_db():
    """Obtener conexión del pool"""
    if pool is None:
        raise HTTPException(status_code=503, detail="Database not connected")
    async with pool.acquire() as conn:
        yield conn

@app.on_event("startup")
async def startup():
    global pool
    try:
        pool = await asyncpg.create_pool(
            DATABASE_URL,
            min_size=2,
            max_size=10,
            command_timeout=60,
            ssl="require" if "neon.tech" in DATABASE_URL else None
        )
        logger.info("✅ PostgreSQL pool connected")
    except Exception as e:
        logger.error(f"❌ Database connection failed: {e}")
        raise

@app.on_event("shutdown")
async def shutdown():
    global pool
    if pool:
        await pool.close()
        logger.info("🔌 PostgreSQL pool closed")

# ============================================
# MODELOS Pydantic
# ============================================

class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int

class TokenRefresh(BaseModel):
    refresh_token: str

class UsuarioLogin(BaseModel):
    nombre: str
    password: str

class ProductoOut(BaseModel):
    id: int
    nombre: str
    categoria_feriaapp_id: Optional[int]
    subcategoria_feriaapp_id: Optional[int]
    categoria_revistete_id: Optional[int]
    genero_id: Optional[int]
    segmento_edad_id: Optional[int]
    talla: Optional[str]
    precio_online: Optional[int]
    precio_feria: Optional[int]
    precio_standard: Optional[int]
    estado: str
    condicion: Optional[str]
    marca: Optional[str]
    fotos: Optional[list]
    created_at: Optional[datetime]

class VentaIn(BaseModel):
    evento_feria_id: int
    forma_pago: str
    total_venta: int
    notas: Optional[str] = None

class SyncBatch(BaseModel):
    tabla: str
    operacion: str
    datos: dict
    timestamp_local: datetime
    dispositivo_id: int

class HealthCheck(BaseModel):
    status: str
    version: str
    database: str
    timestamp: datetime

# ============================================
# UTILIDADES JWT
# ============================================

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def create_refresh_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def get_current_user(token: str = Depends(oauth2_scheme), conn=Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Credenciales inválidas",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        token_type: str = payload.get("type")
        if user_id is None or token_type != "access":
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = await conn.fetchrow("SELECT id, nombre, rol, activo FROM usuarios WHERE id = $1", int(user_id))
    if user is None or not user["activo"]:
        raise credentials_exception
    return dict(user)

# ============================================
# ENDPOINTS
# ============================================

@app.get("/", tags=["Root"])
async def root():
    return {
        "message": "FeriaApp API v2.1",
        "docs": "/docs",
        "health": "/health"
    }

@app.api_route("/health", methods=["GET", "HEAD"], response_model=HealthCheck, tags=["Health"])
async def health_check(request: Request, conn=Depends(get_db)):
    try:
        db_status = await conn.fetchval("SELECT 1")
        return HealthCheck(
            status="healthy",
            version="2.1.0",
            database="connected" if db_status else "error",
            timestamp=datetime.utcnow()
        )
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database error: {str(e)}")

# --- AUTH ---

@app.post("/auth/login", response_model=Token, tags=["Auth"])
async def login(form_data: OAuth2PasswordRequestForm = Depends(), conn=Depends(get_db)):
    """Login con nombre de usuario y contraseña"""
    user = await conn.fetchrow(
        "SELECT id, nombre, password_hash, activo FROM usuarios WHERE nombre = $1",
        form_data.username
    )
    if not user or not pwd_context.verify(form_data.password, user["password_hash"]):
        raise HTTPException(status_code=401, detail="Usuario o contraseña incorrectos")
    if not user["activo"]:
        raise HTTPException(status_code=403, detail="Usuario desactivado")

    access_token = create_access_token({"sub": str(user["id"]), "name": user["nombre"]})
    refresh_token = create_refresh_token({"sub": str(user["id"])})

    return Token(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=ACCESS_TOKEN_EXPIRE_MINUTES * 60
    )

@app.post("/auth/refresh", response_model=Token, tags=["Auth"])
async def refresh_token(token_data: TokenRefresh, conn=Depends(get_db)):
    """Refrescar access token con refresh token"""
    try:
        payload = jwt.decode(token_data.refresh_token, SECRET_KEY, algorithms=[ALGORITHM])
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
        expires_in=ACCESS_TOKEN_EXPIRE_MINUTES * 60
    )

@app.get("/auth/me", tags=["Auth"])
async def me(current_user=Depends(get_current_user)):
    return current_user

# --- CATÁLOGO ---

@app.get("/catalogo/productos", response_model=List[ProductoOut], tags=["Catálogo"])
async def listar_productos(
    categoria_id: Optional[int] = None,
    estado: Optional[str] = None,
    conn=Depends(get_db)
):
    """Listar productos con filtros opcionales"""
    query = """
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, genero_id, segmento_edad_id,
               talla, precio_online, precio_feria, precio_standard,
               estado, condicion, marca, fotos, created_at
        FROM productos
        WHERE activo = TRUE
    """
    params = []
    if categoria_id:
        query += " AND categoria_feriaapp_id = $" + str(len(params) + 1)
        params.append(categoria_id)
    if estado:
        query += " AND estado = $" + str(len(params) + 1)
        params.append(estado)
    query += " ORDER BY nombre"

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]

@app.get("/catalogo/productos/{producto_id}", response_model=ProductoOut, tags=["Catálogo"])
async def obtener_producto(producto_id: int, conn=Depends(get_db)):
    row = await conn.fetchrow("""
        SELECT id, nombre, categoria_feriaapp_id, subcategoria_feriaapp_id,
               categoria_revistete_id, genero_id, segmento_edad_id,
               talla, precio_online, precio_feria, precio_standard,
               estado, condicion, marca, fotos, created_at
        FROM productos WHERE id = $1 AND activo = TRUE
    """, producto_id)
    if not row:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return dict(row)

@app.get("/catalogo/categorias", tags=["Catálogo"])
async def listar_categorias(conn=Depends(get_db)):
    rows = await conn.fetch("SELECT id, nombre, sector_puesto, tipo_origen FROM categorias_producto WHERE activo = TRUE ORDER BY nombre")
    return [dict(r) for r in rows]

@app.get("/catalogo/categorias-revistete", tags=["Catálogo"])
async def listar_categorias_revistete(conn=Depends(get_db)):
    rows = await conn.fetch("SELECT id, codigo, nombre, grupo FROM categorias_ropa WHERE activo = TRUE ORDER BY grupo, nombre")
    return [dict(r) for r in rows]

@app.get("/catalogo/generos", tags=["Catálogo"])
async def listar_generos(conn=Depends(get_db)):
    rows = await conn.fetch("SELECT id, codigo, nombre FROM generos WHERE activo = TRUE")
    return [dict(r) for r in rows]

@app.get("/catalogo/segmentos-edad", tags=["Catálogo"])
async def listar_segmentos_edad(conn=Depends(get_db)):
    rows = await conn.fetch("SELECT id, codigo, nombre, rango_anios FROM segmentos_edad WHERE activo = TRUE")
    return [dict(r) for r in rows]

# --- VENTAS ---

@app.post("/ventas", tags=["Ventas"])
async def crear_venta(venta: VentaIn, current_user=Depends(get_current_user), conn=Depends(get_db)):
    """Registrar una nueva venta"""
    # Verificar evento existe y está activo
    evento = await conn.fetchrow(
        "SELECT id, estado FROM eventos_feria WHERE id = $1", venta.evento_feria_id
    )
    if not evento:
        raise HTTPException(status_code=404, detail="Evento no encontrado")
    if evento["estado"] == "cerrado":
        raise HTTPException(status_code=400, detail="No se pueden crear ventas en evento cerrado")

    # Insertar venta
    venta_id = await conn.fetchval("""
        INSERT INTO journal_ventas (
            evento_feria_id, usuario_id, dispositivo_id,
            timestamp_local, forma_pago, total_venta, notas, sync_estado
        ) VALUES ($1, $2, $3, NOW(), $4, $5, $6, 'sincronizado')
        RETURNING id
    """, venta.evento_feria_id, current_user["id"], 1, venta.forma_pago, venta.total_venta, venta.notas)

    return {"id": venta_id, "message": "Venta registrada exitosamente"}

@app.get("/ventas", tags=["Ventas"])
async def listar_ventas(
    evento_id: Optional[int] = None,
    fecha_desde: Optional[datetime] = None,
    fecha_hasta: Optional[datetime] = None,
    conn=Depends(get_db)
):
    query = """
        SELECT jv.id, jv.timestamp_local, jv.total_venta, jv.forma_pago,
               jv.estado_pago, jv.sync_estado, jv.notas,
               ef.fecha as fecha_evento, ef.lugar,
               u.nombre as vendedor
        FROM journal_ventas jv
        JOIN eventos_feria ef ON jv.evento_feria_id = ef.id
        JOIN usuarios u ON jv.usuario_id = u.id
        WHERE 1=1
    """
    params = []
    if evento_id:
        query += " AND jv.evento_feria_id = $" + str(len(params) + 1)
        params.append(evento_id)
    if fecha_desde:
        query += " AND jv.timestamp_local >= $" + str(len(params) + 1)
        params.append(fecha_desde)
    if fecha_hasta:
        query += " AND jv.timestamp_local <= $" + str(len(params) + 1)
        params.append(fecha_hasta)
    query += " ORDER BY jv.timestamp_local DESC LIMIT 100"

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]

# --- SYNC ---

@app.post("/sync/batch", tags=["Sync"])
async def sync_batch(batch: List[SyncBatch], current_user=Depends(get_current_user), conn=Depends(get_db)):
    """Recibir batch de operaciones offline desde dispositivos"""
    results = []
    for op in batch:
        try:
            # Insertar en sync_log
            await conn.execute("""
                INSERT INTO sync_log (dispositivo_id, usuario_id, tabla_afectada, 
                    registro_id, operacion, timestamp_local, estado, detalle)
                VALUES ($1, $2, $3, $4, $5, $6, 'ok', 'Sincronizado exitosamente')
            """, op.dispositivo_id, current_user["id"], op.tabla, 
                op.datos.get("id", 0), op.operacion, op.timestamp_local)
            results.append({"status": "ok", "tabla": op.tabla})
        except Exception as e:
            results.append({"status": "error", "tabla": op.tabla, "error": str(e)})

    return {"procesados": len(batch), "resultados": results}

# --- EVENTOS ---

@app.get("/eventos", tags=["Eventos"])
async def listar_eventos(estado: Optional[str] = None, conn=Depends(get_db)):
    query = """
        SELECT ef.id, ef.fecha, ef.lugar, ef.estado, ef.total_calculado,
               ef.total_confirmado, ef.diferencia,
               cv.nombre as canal_venta, cv.tipo as tipo_canal,
               u.nombre as vendedor_principal
        FROM eventos_feria ef
        JOIN canales_venta cv ON ef.canal_venta_id = cv.id
        JOIN usuarios u ON ef.vendedor_principal_id = u.id
        WHERE 1=1
    """
    params = []
    if estado:
        query += " AND ef.estado = $" + str(len(params) + 1)
        params.append(estado)
    query += " ORDER BY ef.fecha DESC"

    rows = await conn.fetch(query, *params)
    return [dict(r) for r in rows]

@app.post("/eventos", tags=["Eventos"])
async def crear_evento(
    canal_venta_id: int,
    fecha: str,
    lugar: str,
    current_user=Depends(get_current_user),
    conn=Depends(get_db)
):
    """Crear nuevo evento de feria (siempre estado='activo')"""
    evento_id = await conn.fetchval("""
        INSERT INTO eventos_feria (canal_venta_id, fecha, lugar, vendedor_principal_id, estado, total_calculado)
        VALUES ($1, $2, $3, $4, 'activo', 0)
        RETURNING id
    """, canal_venta_id, fecha, lugar, current_user["id"])

    return {"id": evento_id, "estado": "activo", "message": "Evento creado. Requiere cierre manual."}

# ============================================
# MAIN
# ============================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
