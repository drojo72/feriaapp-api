"""
FeriaApp API v2.1 — Router: Health check
"""
from datetime import datetime
from fastapi import APIRouter, Depends, Request, HTTPException

from lib.core.database import get_db

router = APIRouter(tags=["Health"])


@router.api_route("/health", methods=["GET", "HEAD"])
async def health_check(request: Request, conn=Depends(get_db)):
    """Health check con verificación de base de datos."""
    try:
        db_status = await conn.fetchval("SELECT 1")
        return {
            "status": "healthy",
            "version": "2.1.0",
            "database": "connected" if db_status else "error",
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Database error: {str(e)}")
