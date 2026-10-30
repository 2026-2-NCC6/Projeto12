from fastapi import FastAPI
from src.routers import auth
from fastapi.middleware.cors import CORSMiddleware
from src.routers import admin, auth, treinos
from src.admin.painel import montar_painel
from src.core.config import settings

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