import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from src.db.base import Base
from src.db.session import get_db
from src.main import app
from src.models.usuario import Papel, Usuario

engine_teste = create_engine(
    "sqlite://",
    connect_args={"check_same_thread": False},
    poolclass=StaticPool,
)
SessionTeste = sessionmaker(bind=engine_teste)


@pytest.fixture
def cliente():
    Base.metadata.create_all(engine_teste)

    def get_db_teste():
        db = SessionTeste()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = get_db_teste
    yield TestClient(app)
    app.dependency_overrides.clear()
    Base.metadata.drop_all(engine_teste)


@pytest.fixture
def promover_admin():
    """Promove um usuario a admin direto no banco de teste.

    Precisa ser fixture, e nao funcao importada: importar o conftest
    criaria um segundo banco em memoria, separado do que o pytest usa.
    """

    def _promover(email="vitoria@tobias.dev"):
        db = SessionTeste()
        usuario = db.query(Usuario).filter(Usuario.email == email).first()
        usuario.papel = Papel.admin
        db.commit()
        db.close()

    return _promover