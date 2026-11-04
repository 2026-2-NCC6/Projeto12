"""Registra TODOS os modelos no Base.metadata.

Estes imports nao sao usados aqui: existem para registrar as tabelas. Nao
os remova nem deixe um linter "limpar" a lista. Sem eles, quem importa so
um modelo (ex.: Sessao) fica com o metadata incompleto, e o flush falha
com NoReferencedTableError numa FK (sessao.treino_versao_id ->
treino_versao), um erro que nao aponta para a causa.

Como todo `import src.models.<modulo>` executa este arquivo antes, qualquer
import de modelo ja traz o registro completo. Scripts avulsos (recalculo,
seed, exportacao, relatorio) devem mesmo assim fazer `import src.models`
explicitamente. Modelo novo: acrescente aqui e em __all__.
"""

from src.models.log_auditoria import LogAuditoria
from src.models.sessao import ClasseImpacto, Lance, Sessao, TipoLance
from src.models.treino import Escopo, Nivel, Treino, TreinoVersao
from src.models.usuario import Papel, Perfil, Usuario

# __all__ marca os nomes como reexportados: linters nao os tratam como
# imports sem uso.
__all__ = [
    "ClasseImpacto",
    "Escopo",
    "Lance",
    "LogAuditoria",
    "Nivel",
    "Papel",
    "Perfil",
    "Sessao",
    "TipoLance",
    "Treino",
    "TreinoVersao",
    "Usuario",
]
