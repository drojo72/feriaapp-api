import asyncpg
from lib.core.config import get_settings

settings = get_settings()

async def get_db():
    conn = await asyncpg.connect(settings.DATABASE_URL)
    try:
        yield conn
    finally:
        await conn.close()
