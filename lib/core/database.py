"""
FeriaApp API v2.1 — Pool de conexiones PostgreSQL (asyncpg)
Frugal: pool global, adquiere y libera por request.
"""
import asyncpg
import logging
from typing import Optional

from lib.core.config import settings

logger = logging.getLogger(__name__)

# Pool global — se inicializa en startup de FastAPI
pool: Optional[asyncpg.Pool] = None


async def init_pool() -> asyncpg.Pool:
    """Crear pool de conexiones. Llamar una vez en startup."""
    global pool
    pool = await asyncpg.create_pool(
        settings.database_url,
        min_size=2,
        max_size=10,
        command_timeout=60,
        ssl=settings.db_ssl
    )
    logger.info("✅ PostgreSQL pool conectado")
    return pool


async def close_pool():
    """Cerrar pool. Llamar en shutdown."""
    global pool
    if pool:
        await pool.close()
        logger.info("🔌 PostgreSQL pool cerrado")


async def get_db():
    """Dependencia FastAPI: yield conexión del pool."""
    if pool is None:
        raise RuntimeError("Pool no inicializado. Llamar init_pool() en startup.")
    async with pool.acquire() as conn:
        yield conn
