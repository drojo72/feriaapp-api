# FeriaApp API v2.1

Backend FastAPI para FeriaApp — Feria Dominical, Re-Vistete y Granja Toqui.

## Stack

- **FastAPI** + Uvicorn
- **PostgreSQL** (Neon)
- **JWT** Auth (access + refresh tokens)
- **asyncpg** para queries asíncronos

## Estructura
feriaapp-api/
├── main.py              # Entry point FastAPI
├── lib/
│   ├── core/            # Config, DB pool, Security
│   │   ├── config.py
│   │   ├── database.py
│   │   └── security.py
│   ├── models/          # Pydantic models
│   │   ├── auth.py
│   │   ├── productos.py
│   │   ├── ventas.py
│   │   └── eventos.py
│   └── routers/         # Endpoints por dominio
│       ├── auth.py
│       ├── catalogo.py
│       ├── productos.py
│       ├── ventas.py
│       ├── eventos.py
│       ├── sync.py
│       └── health.py
├── schema_v2_1.sql      # Schema completo
├── migrate_v1_to_v2_1.sql
├── migrate_historical_data_v2_1.sql
├── render.yaml          # Blueprint Render
├── Dockerfile
├── requirements.txt
├── env.example
└── setup.sh
