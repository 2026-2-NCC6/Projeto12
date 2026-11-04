from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.admin.painel import montar_painel
from src.core.config import settings
from src.routers import admin, auth, sessoes, treinos

app = FastAPI(title="TOBIAS API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.origens,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(treinos.router)
app.include_router(sessoes.router)
app.include_router(admin.router)

montar_painel(app, settings.admin_secret)


@app.get("/health")
def health():
    """Usado pelo Container Apps e pelo aquecimento antes da demo (US-1004)."""
    return {"status": "ok"}