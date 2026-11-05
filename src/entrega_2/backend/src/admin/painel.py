from sqladmin import Admin, ModelView
from sqladmin.authentication import AuthenticationBackend
from sqlalchemy import delete
from sqlalchemy.orm import object_session
from starlette.requests import Request

from src.core.security import conferir_senha
from src.db.session import SessionLocal, engine
from src.models.sessao import Lance, Sessao
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


class SessaoView(ModelView, model=Sessao):
    name = "Sessão"
    name_plural = "Sessões"
    icon = "fa-solid fa-table-tennis-paddle-ball"

    column_list = [
        Sessao.uuid_sessao,
        Sessao.usuario_id,
        Sessao.treino_versao_id,
        Sessao.iniciada_em,
        Sessao.encerrada_em,
        Sessao.recebida_em,
        Sessao.pontuacao_total,
        Sessao.versao_pontuacao,
        Sessao.acertos,
        Sessao.erros,
        Sessao.kos,
        Sessao.melhor_sequencia,
        Sessao.precisao,
    ]
    # `id` e o que aparece nos logs (ex.: pontuacao_divergente sessao_id=...)
    # e `uuid_sessao` e o que o app conhece: os dois pesquisaveis, para
    # correlacionar um alerta com a sessao. A busca aceita trecho do UUID.
    column_searchable_list = [Sessao.uuid_sessao, Sessao.id]
    column_sortable_list = [
        Sessao.usuario_id,
        Sessao.iniciada_em,
        Sessao.recebida_em,
        Sessao.pontuacao_total,
    ]
    column_default_sort = [(Sessao.recebida_em, True)]

    # Sessao e lance sao registro de evento, nao cadastro: entram pela API
    # (POST /v1/sessions), nunca a mao, e nao se editam. Editar a
    # pontuacao_total faria o painel exibir um placar "oficial" que o
    # servidor nunca calculou, contradizendo a US-705: o numero voltaria a
    # depender de confianca em quem tem acesso ao painel. E os totais sao
    # derivados dos lances; edita-los e editar um cache.
    #
    # Excluir fica ligado, e a unidade e a sessao inteira (com os lances,
    # ver on_model_delete): e como o admin limpa dados de teste.
    can_create = False
    can_edit = False
    can_delete = True

    async def on_model_delete(self, model, request: Request) -> None:
        # Redundante desde que lance.sessao_id tem ON DELETE CASCADE (migration
        # d4f8b2c6e1a7): o banco ja apaga os lances. Mantido de proposito, como
        # segunda garantia. Mesma transacao da exclusao da sessao: ou sai
        # tudo, ou nada.
        object_session(model).execute(
            delete(Lance).where(Lance.sessao_id == model.id)
        )


class LanceView(ModelView, model=Lance):
    name = "Lance"
    name_plural = "Lances"
    icon = "fa-solid fa-baseball"

    column_list = [
        Lance.sessao_id,
        Lance.bola,
        Lance.uuid_lance,
        Lance.id_lance_firmware,
        Lance.resultado,
        Lance.classe,
        Lance.angulo,
        Lance.ts_ms,
        Lance.pontos,
    ]
    # Pelo sessao_id (o `id` da sessao) se acham os lances de uma sessao.
    column_searchable_list = [Lance.sessao_id, Lance.uuid_lance]
    column_sortable_list = [Lance.sessao_id, Lance.bola]
    column_default_sort = [(Lance.sessao_id, False), (Lance.bola, False)]

    # Mesmo motivo da SessaoView: registro de evento, entra pela API e nao
    # se edita. Nem se exclui avulso: sem o lance, os totais e a pontuacao
    # da sessao mentiriam. Para limpar, exclui-se a sessao inteira.
    can_create = False
    can_edit = False
    can_delete = False


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
    painel.add_view(SessaoView)
    painel.add_view(LanceView)
    return painel