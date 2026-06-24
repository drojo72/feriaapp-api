from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from api import auth, catalogo, sync, ventas

app = FastAPI(title="FeriaApp API", version="2.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(catalogo.router)
app.include_router(sync.router)
app.include_router(ventas.router)

@app.get("/health")
async def health():
    return {"status": "ok", "version": "2.0.0"}
