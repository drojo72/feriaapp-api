"""
FeriaApp API v2.1
FastAPI + PostgreSQL (Neon) + JWT Auth
Refactorizado: módulos separados en lib/routers/

Estructura:
  lib/core/       — config, database, security
  lib/models/     — Pydantic models
  lib/routers/    — endpoints por dominio
"""
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from lib.core.config import settings
from lib.core.database import init_pool, close_pool
from lib.routers import auth, catalogo, productos, ventas, eventos, sync, health, auditoria

# Configuración logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# App FastAPI
app = FastAPI(
    title="FeriaApp API",
    description="API para FeriaApp v2.1 - Feria Dominical + Re-Vistete + Granja Toqui",
    version=settings.version
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:4321",
        "http://localhost:3000",
        "http://localhost:5173",
        "https://feriaapp.pages.dev",
        "*"  # ← temporal para debug
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
    max_age=3600,
)

app.include_router(auditoria.router)

# ============================================
# LIFECYCLE
# ============================================

@app.on_event("startup")
async def startup():
    """Inicializar pool de conexiones PostgreSQL."""
    try:
        await init_pool()
    except Exception as e:
        logger.error(f"❌ Database connection failed: {e}")
        raise

@app.on_event("shutdown")
async def shutdown():
    """Cerrar pool de conexiones."""
    await close_pool()

# ============================================
# ROUTERS
# ============================================

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(catalogo.router)
app.include_router(productos.router)
app.include_router(ventas.router)
app.include_router(eventos.router)
app.include_router(sync.router)

# ============================================
# ROOT
# ============================================

@app.get("/", tags=["Root"])
async def root():
    return {
        "message": "FeriaApp API v2.1",
        "version": settings.version,
        "environment": settings.environment,
        "docs": "/docs",
        "health": "/health"
    }

# ============================================
# MAIN
# ============================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
