"""Scripts avulsos rodam fora da aplicacao, com so os imports que eles fazem.

Por isso o teste roda o script num processo Python novo: dentro do pytest o
conftest ja importou o main, que registra todos os modelos, e o bug de
metadata incompleto (NoReferencedTableError no flush) nunca apareceria.
"""

import subprocess
import sys
import textwrap
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from src.db.base import Base
from src.models.sessao import Lance, Sessao, TipoLance
from src.models.treino import Escopo, Nivel, Treino, TreinoVersao
from src.models.usuario import Usuario

BACKEND = Path(__file__).parent.parent


def rodar_isolado(codigo: str, *args: str) -> subprocess.CompletedProcess:
    """Executa `codigo` num interpretador limpo, com o backend no path."""
    return subprocess.run(
        [sys.executable, "-c", textwrap.dedent(codigo), *args],
        cwd=BACKEND,
        capture_output=True,
        text=True,
        timeout=120,
    )


def criar_banco_com_sessao_sem_pontuacao(caminho: Path) -> str:
    engine = create_engine(f"sqlite:///{caminho}")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        usuario = Usuario(
            email="script@tobias.dev", senha_hash="x", nome="Script",
            apelido="script", data_nascimento=datetime(2000, 1, 1).date(),
        )
        db.add(usuario)
        db.flush()
        treino = Treino(titulo="Script", escopo=Escopo.pessoal, owner_id=usuario.id)
        db.add(treino)
        db.flush()
        versao = TreinoVersao(
            treino_id=treino.id, numero=1, nivel=Nivel.medio,
            qtd_lances=2, intervalo_ms=3000,
        )
        db.add(versao)
        db.flush()
        sessao = Sessao(
            uuid_sessao=uuid.uuid4(),
            usuario_id=usuario.id,
            treino_versao_id=versao.id,  # a FK que nao resolvia
            iniciada_em=datetime(2026, 10, 1, 11, 15, tzinfo=timezone.utc),
            pontuacao_total=None,
        )
        db.add(sessao)
        db.flush()
        for bola, angulo in ((1, "25.0"), (2, "60.0")):
            db.add(Lance(
                sessao_id=sessao.id, uuid_lance=uuid.uuid4(), bola=bola,
                resultado=TipoLance.acerto, angulo=Decimal(angulo), ts_ms=bola * 1000,
            ))
        db.commit()
        sessao_id = str(sessao.id)
    engine.dispose()
    return sessao_id


def test_script_importado_sozinho_registra_todos_os_modelos():
    r = rodar_isolado(
        """
        import src.scripts.recalcular_pontuacao
        from src.db.base import Base
        print(",".join(sorted(Base.metadata.tables)))
        """
    )
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip().split(",") == [
        "lance", "log_auditoria", "sessao", "treino", "treino_versao", "usuario"
    ]


def test_script_recalcula_e_grava_importando_so_o_proprio_modulo(tmp_path):
    banco = tmp_path / "script.db"
    sessao_id = criar_banco_com_sessao_sem_pontuacao(banco)

    # O processo filho importa SO o modulo do script, como `python -m` faz.
    r = rodar_isolado(
        """
        import sys
        from sqlalchemy import create_engine
        from sqlalchemy.orm import Session
        from src.scripts.recalcular_pontuacao import recalcular_pendentes

        with Session(create_engine(f"sqlite:///{sys.argv[1]}")) as db:
            print(recalcular_pendentes(db))
        """,
        str(banco),
    )

    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "1"

    engine = create_engine(f"sqlite:///{banco}")
    with Session(engine) as db:
        sessao = db.get(Sessao, uuid.UUID(sessao_id))
        # 25,0 graus: 20; 60,0 graus com KO e sequencia 1: 100 x 110% + 75.
        assert sessao.pontuacao_total == 20 + 185
        assert sessao.versao_pontuacao == 1
    engine.dispose()
