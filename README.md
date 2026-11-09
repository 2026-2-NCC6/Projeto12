# 🏫 FECAP - Fundação de Comércio Álvares Penteado

<p align="center">
<a href= "https://www.fecap.br/"><img src="https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcRhZPrRa89Kma0ZZogxm0pi-tCn_TLKeHGVxywp-LXAFGR3B1DPouAJYHgKZGV0XTEf4AE&usqp=CAU" alt="FECAP - Fundação de Comércio Álvares Penteado" border="0"></a>
</p>

# Projeto 12: Smart Tennis Arena — Alvo Interativo TOBIAS 🤖🎾

## Nome do Grupo: Radonix

## Integrantes: <a href="https://www.linkedin.com/in/gabrielcarvalhomota/">Gabriel Carvalho</a>, <a href="https://www.linkedin.com/in/sik4s/">Guilherme Siqueira</a>, <a href="https://www.linkedin.com/in/rluizreis/">Rodrigo Reis</a>, <a href="https://www.linkedin.com/in/vitória-maciel-8308a42a6/">Vitória Leticia Maciel</a>.

## Professores Orientadores: <a href="https://www.linkedin.com/in/edsonbarbero/">Edson Ricardo Barbero</a>, <a href="https://www.linkedin.com/in/trencher/">Joao Francisco Trencher Martins</a>, <a href="https://www.linkedin.com/in/katia-bossi/">Katia Milani Lara Bossi</a>, <a href="https://www.linkedin.com/in/professorrodnil/">Rodnil da Silva Moreira Lisboa</a>, <a href="https://www.linkedin.com/in/victorbarq/">Victor Rosetti</a>.

## 🎾 TOBIAS - O Boneco Interativo

O **TOBIAS** é um boneco joão-bobo instrumentado que transforma o treino de tênis em jogo. Um sensor inercial dentro do alvo detecta cada bolada, classifica a intensidade do impacto e dispara na hora uma reação sonora — tudo em menos de um décimo de segundo, sem depender de internet.

Um aplicativo mobile conduz a sessão: conecta-se ao alvo por Bluetooth, exibe a pontuação em tempo real e guarda os lances localmente, sincronizando depois com a nuvem, onde ficam o histórico de evolução do jogador e o catálogo de treinos publicados pelos treinadores.

A proposta é dar a quem está começando o retorno objetivo que hoje só existe com um professor ao lado ou uma máquina lançadora importada, a uma fração do custo.

## Componentes

| Módulo | Descrição |
|---|---|
| `firmware/` | ESP32 + sensor MPU6050 + áudio via DFPlayer Mini, comunicação por BLE |
| `apps/mobile/` | Aplicativo Flutter (Android) com operação offline |
| `apps/api/` | API REST em FastAPI com PostgreSQL, autenticação JWT e painel de treinos |

## 🛠️ Tecnologias

**Dispositivo IoT**

![ESP32](https://img.shields.io/badge/ESP32-E7352C?style=for-the-badge&logo=espressif&logoColor=white)
![C++](https://img.shields.io/badge/C%2B%2B-00599C?style=for-the-badge&logo=cplusplus&logoColor=white)
![PlatformIO](https://img.shields.io/badge/PlatformIO-FF7F00?style=for-the-badge&logo=platformio&logoColor=white)
![MPU6050](https://img.shields.io/badge/MPU6050-5A5A5A?style=for-the-badge)
![DFPlayer Mini](https://img.shields.io/badge/DFPlayer%20Mini-5A5A5A?style=for-the-badge)
![Bluetooth LE](https://img.shields.io/badge/Bluetooth%20LE-0082FC?style=for-the-badge&logo=bluetooth&logoColor=white)

**Aplicativo mobile**

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-34A853?style=for-the-badge&logo=android&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-003B57?style=for-the-badge&logo=sqlite&logoColor=white)

**Backend e dados**

![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)
![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white)
![Pydantic](https://img.shields.io/badge/Pydantic-E92063?style=for-the-badge&logo=pydantic&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)
![JWT](https://img.shields.io/badge/JWT-000000?style=for-the-badge&logo=jsonwebtokens&logoColor=white)
![OpenAPI](https://img.shields.io/badge/OpenAPI-85EA2D?style=for-the-badge&logo=swagger&logoColor=black)
![Pytest](https://img.shields.io/badge/Pytest-0A9EDC?style=for-the-badge&logo=pytest&logoColor=white)

**Infraestrutura e processo**

![Docker](https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Azure](https://img.shields.io/badge/Microsoft%20Azure-0078D4?style=for-the-badge&logo=microsoftazure&logoColor=white)
![Figma](https://img.shields.io/badge/Figma-F24E1E?style=for-the-badge&logo=figma&logoColor=white)
![Scrum](https://img.shields.io/badge/Scrum-1E7A3C?style=for-the-badge)

## 💡 Principais Funcionalidades

### 🎯 No alvo (dispositivo IoT)

- **Detecção de impacto** — o sensor inercial lê o alvo 200 vezes por segundo, identifica o pico do golpe e mede a oscilação do boneco para estimar a intensidade.
- **Um golpe, um evento** — um período refratário calibrado impede que o balanço natural do joão-bobo transforme uma única bolada em vários acertos.
- **Reação sonora imediata** — o áudio dispara em menos de 100 ms, direto no dispositivo, com falas sorteadas por faixa de intensidade e sem repetir a reação anterior.
- **Calibração por jogador** — cinco batidas de referência ajustam a escala de pontuação ao praticante, gravadas na memória do próprio dispositivo.
- **Comportamento modelado** — o ciclo da sessão é descrito por uma máquina de estados formal, com transições previsíveis e verificáveis.

### 📱 No aplicativo

- **Pareamento por Bluetooth** — encontra e conecta o alvo em segundos, exibindo status do sensor e versão do firmware.
- **Catálogo de treinos** — lista os treinos publicados, com dificuldade, duração e instruções antes de começar.
- **Controle da sessão** — iniciar, pausar, retomar e encerrar, com pontos, sequência atual e lances restantes sempre à vista.
- **Pontuação em tempo real** — cada acerto atualiza o placar na hora, premiando constância e tempo de reação, não só força.
- **Resumo ao final** — total de pontos, precisão, consistência, melhor sequência e comparação com a sessão anterior.
- **Histórico e progressão** — consulta das sessões anteriores para acompanhar a evolução ao longo do tempo.
- **Funciona sem internet** — a sessão roda inteira offline e sincroniza sozinha quando a conexão volta.

## 🛠 Estrutura de pastas

```
├── docs/
│   ├── Entrega1/
│   │   ├── Inovação e Empreendedorismo/
│   │   ├── Redes de Computadores e Cibersegurança/
│   │   ├── Sistemas Embarcados e Robótica/
│   │   ├── Teoria da Computação e Linguagens Formais/
│   │   └── Projeto Interdisciplinar: IoT e Robótica/
│   ├── Entrega2/
│   │   ├── Inovação e Empreendedorismo/
│   │   ├── Redes de Computadores e Cibersegurança/
│   │   ├── Sistemas Embarcados e Robótica/
│   │   ├── Teoria da Computação e Linguagens Formais/
│   │   └── Projeto Interdisciplinar: IoT e Robótica/
│   ├── Documentação.docx
│   ├── Documentação.pdf
│   ├── Banner.docx
│   ├── Banner.pdf
│   ├── Declaração de Uso de IA.pdf
├── imagens/
├── src/
│   ├── Entrega1/
│   ├── Entrega2/
└── readme.md<br>
```

<b>📄 README.MD</b>: Arquivo que serve como guia e explicação geral sobre o projeto.

Há também 4 pastas que seguem da seguinte forma:

<b>🗂️ Documentos</b>: Toda a documentação geral do projeto. Além das entregas das disciplinas do semestre.

<b>📷 imagens</b>: Imagens utilizadas para documentação e explicação do projeto.

<b>🧑‍💻 src</b>: Pasta que contém o código fonte (frontend e backend).

### 📥 Testar sem instalar nada

Baixe o APK mais recente em
[**executaveis**](https://github.com/2026-2-NCC6/Projeto12/src/executais)
e instale no celular Android.

1. Ao abrir o arquivo, o Android vai pedir permissão para instalar de fonte
   desconhecida — autorize o app que está fazendo a instalação (navegador ou
   gerenciador de arquivos).
2. Crie uma conta e faça login. O app já usa a API hospedada no Azure.
3. Aproveite a experiência em uma sessão com o boneco interativo TOBIAS.

## 📋 Licença/License
<a href="https://github.com/2026-2-NCC6/Projeto12">TOBIAS - O Boneco Interativo</a> © 2026 by <a href="https://github.com/2026-2-NCC6/Projeto12">Guilherme de Lima Siqueira, Gabriel Carvalho Mota, Rodrigo Luiz Menezes dos Reis, Vitória Leticia Maciel da Silva.</a> is licensed under <a href="https://creativecommons.org/licenses/by/4.0/">CC BY 4.0</a>
