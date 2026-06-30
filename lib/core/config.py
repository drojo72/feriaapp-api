"""
FeriaApp API v2.1 — Configuración centralizada
Carga desde variables de entorno con valores por defecto para desarrollo.
Frugal: solo lo que se usa, sin bloat.
"""
import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()  # Carga .env automáticamente

@dataclass(frozen=True)
class Settings:
    """Singleton de configuración. Inmutable después de crear."""
    # Database
    database_url: str = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost/feriaapp")

    # JWT
    secret_key: str = os.getenv("SECRET_KEY", "dev-secret-cambiar-en-produccion")
    algorithm: str = "HS256"
    access_token_expire_minutes: int = int(os.getenv("ACCESS_TOKEN_EXPIRE_MINUTES", "15"))
    refresh_token_expire_days: int = int(os.getenv("REFRESH_TOKEN_EXPIRE_DAYS", "90"))

    # App
    environment: str = os.getenv("ENVIRONMENT", "development")
    version: str = "2.1.0"

    # CORS
    cors_origins: list = None

    def __post_init__(self):
        # frozen=True impide asignación directa, usamos object.__setattr__
        origins = [
            "http://localhost:3000",
            "http://localhost:4321",
            "https://feriaapp.pages.dev",
            "https://keysign-labs.eu.org",
        ]
        if self.environment == "development":
            origins.extend(["http://localhost:5173", "http://127.0.0.1:5173"])
        object.__setattr__(self, "cors_origins", origins)

    @property
    def db_ssl(self) -> str:
        """SSL requerido solo para Neon (detecta por hostname)."""
        return "require" if "neon.tech" in self.database_url else None


# Instancia única global
settings = Settings()
