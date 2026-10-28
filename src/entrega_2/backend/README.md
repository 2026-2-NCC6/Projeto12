> Readme destinado a descrição do módulo do projeto e documentar os passos de execução e desenvolvimento

# Backend API

## Instruções de Desenvolvimento

```bash
# Criar e ativar um ambiente virtual
python3 -m venv .venv
source .venv/bin/activate

# Instalar dependências (inclui pytest e httpx para os testes)
pip install -r requirements-dev.txt

# Rodar o servidor de desenvolvimento (http://127.0.0.1:8000)
uvicorn src.main:app --reload

# Rodar os testes
pytest
```

Para instalar só as dependências de produção (sem pytest), use `pip install -r requirements.txt`.

Documentação interativa (Swagger UI) gerada automaticamente em `/docs`.

## Bibliotecas

- FastAPI
- Uvicorn
- pytest + httpx (testes)
