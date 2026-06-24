# FeriaApp API v2.1

Backend FastAPI para FeriaApp - Feria Dominical, Re-Vistete y Granja Toqui.

## Stack

- **FastAPI** + Uvicorn
- **PostgreSQL** (Neon)
- **JWT** Auth (access + refresh tokens)
- **asyncpg** para queries asíncronos

## Deploy en Render

### Opción A: Blueprint (render.yaml)
1. Push a GitHub (`drojo72/feriaapp-api`)
2. En Render Dashboard → **New** → **Blueprint**
3. Conectar repo → Render detecta `render.yaml`
4. Configurar variables de entorno en dashboard
5. Deploy automático

### Opción B: Manual
1. **New Web Service**
2. Conectar `drojo72/feriaapp-api`
3. Build: `pip install -r requirements.txt`
4. Start: `uvicorn main:app --host 0.0.0.0 --port $PORT`
5. Environment variables desde `.env`

## Variables de Entorno

| Variable | Descripción |
|----------|-------------|
| `DATABASE_URL` | Connection string PostgreSQL (Neon) |
| `SECRET_KEY` | Clave JWT (generar con `openssl rand -hex 32`) |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | 15 |
| `REFRESH_TOKEN_EXPIRE_DAYS` | 90 |
| `ENVIRONMENT` | production / development |

## Endpoints

| Método | Endpoint | Auth | Descripción |
|--------|----------|------|-------------|
| GET | `/` | No | Info API |
| GET | `/health` | No | Health check |
| POST | `/auth/login` | No | Login JWT |
| POST | `/auth/refresh` | No | Refresh token |
| GET | `/auth/me` | Sí | Usuario actual |
| GET | `/catalogo/productos` | Sí | Listar productos |
| GET | `/catalogo/categorias` | Sí | Categorías FeriaApp |
| GET | `/catalogo/categorias-revistete` | Sí | Categorías Re-Vistete |
| POST | `/ventas` | Sí | Registrar venta |
| GET | `/ventas` | Sí | Listar ventas |
| POST | `/sync/batch` | Sí | Sync offline |
| GET | `/eventos` | Sí | Listar eventos |
| POST | `/eventos` | Sí | Crear evento |

## Anti-Sleep (Free Tier)

Render free tier duerme después de 15 min sin tráfico. Configurar UptimeRobot:
- URL: `https://feriaapp-api.onrender.com/health`
- Intervalo: 5 minutos
- Método: GET

## Estructura

```
feriaapp-api/
├── main.py              # Entry point FastAPI
├── render.yaml          # Blueprint Render
├── requirements.txt     # Dependencias
├── .env.example         # Template variables
└── README.md
```
