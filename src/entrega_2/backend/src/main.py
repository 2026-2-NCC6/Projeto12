from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.admin.painel import montar_painel
from src.core.config import settings
from src.db.base import Base
from src.db.session import engine
import src.models.usuario
import src.models.treino
import src.models.sessao
import src.models.log_auditoria
from src.routers import admin, auth, treinos

# Garante a criação de todas as tabelas caso o banco ainda não as possua
Base.metadata.create_all(bind=engine)

app = FastAPI(title="TOBIAS API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(treinos.router)
app.include_router(admin.router)

montar_painel(app, settings.admin_secret)


@app.get("/health")
def health():
    return {"status": "ok"}
