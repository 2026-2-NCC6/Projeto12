from sqladmin import Admin, ModelView
from sqladmin.authentication import AuthenticationBackend
from starlette.requests import Request

from src.core.security import conferir_senha
from src.db.session import SessionLocal, engine
from src.models.treino import Treino, TreinoVersao
from src.models.usuario import Papel, Usuario


class AutenticacaoPainel(AuthenticationBackend):
    """Login do painel por formulario e cookie de sessao.

    Nao usa o JWT do aplicativo: o painel e uma interface web, com
    sessao de navegador, e nao um cliente da API.
    """

    async def login(self, request: Request) -> bool:
        form = await request.form()
        email = form.get("username", "")
        senha = form.get("password", "")

        db = SessionLocal()
        try:
            usuario = db.query(Usuario).filter(Usuario.email == email).first()

            if usuario is None or not conferir_senha(senha, usuario.senha_hash):
                return False

            if usuario.papel != Papel.admin:
                return False

            request.session.update({"usuario_id": usuario.id})
            return True
        finally:
            db.close()

    async def logout(self, request: Request) -> bool:
        request.session.clear()
        return True

    async def authenticate(self, request: Request) -> bool:
        return "usuario_id" in request.session


class UsuarioView(ModelView, model=Usuario):
    name = "Usuário"
    name_plural = "Usuários"
    icon = "fa-solid fa-user"

    column_list = [
        Usuario.id,
        Usuario.email,
        Usuario.nome,
        Usuario.apelido,
        Usuario.perfil,
        Usuario.papel,
        Usuario.criado_em,
    ]
    column_searchable_list = [Usuario.email, Usuario.apelido]
    column_sortable_list = [Usuario.id, Usuario.criado_em]

    # CPF, data de nascimento e hash de senha ficam fora do painel:
    # nem o admin precisa ve-los para operar o sistema.
    column_details_exclude_list = [
        Usuario.data_nascimento,
        Usuario.senha_hash,
    ]
    form_excluded_columns = [Usuario.senha_hash]

    can_create = False  # cadastro e pela API, para a senha ser gerada com hash


class TreinoView(ModelView, model=Treino):
    name = "Treino"
    name_plural = "Treinos"
    icon = "fa-solid fa-dumbbell"

    column_list = [
        Treino.id,
        Treino.titulo,
        Treino.escopo,
        Treino.owner_id,
        Treino.origem_id,
        Treino.criado_em,
        Treino.apagado_em,
    ]
    column_searchable_list = [Treino.titulo]
    column_sortable_list = [Treino.id, Treino.criado_em]


class TreinoVersaoView(ModelView, model=TreinoVersao):
    name = "Versão de treino"
    name_plural = "Versões de treino"
    icon = "fa-solid fa-code-branch"

    column_list = [
        TreinoVersao.id,
        TreinoVersao.treino_id,
        TreinoVersao.numero,
        TreinoVersao.nivel,
        TreinoVersao.qtd_lances,
        TreinoVersao.intervalo_ms,
        TreinoVersao.publicado_em,
    ]
    column_sortable_list = [TreinoVersao.treino_id, TreinoVersao.numero]


def montar_painel(app, secret_key: str) -> Admin:
    """Registra o painel administrativo em /admin."""
    painel = Admin(
        app=app,
        engine=engine,
        title="TOBIAS — Administração",
        authentication_backend=AutenticacaoPainel(secret_key=secret_key),
    )
    painel.add_view(UsuarioView)
    painel.add_view(TreinoView)
    painel.add_view(TreinoVersaoView)
    return painel