import logging
import sys

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.admin.painel import montar_painel
from src.core.config import settings
from src.routers import admin, auth, sessoes, treinos

# Logs da aplicacao (ex.: alerta de pontuacao divergente) no stdout, que e
# o que o Azure Container Apps coleta. Sem isto, logger.warning de modulos
# como "tobias.pontuacao" nao aparece em lugar nenhum.
logging.basicConfig(
    level=logging.INFO,
    stream=sys.stdout,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

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