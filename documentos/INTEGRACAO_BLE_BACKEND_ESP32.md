# 📄 Manual Oficial de Integração: Tobias (ESP32) ↔ Aplicativo Mobile ↔ Backend

Este documento é a referência definitiva para a integração entre o microcontrolador **ESP32 (Tobias)**, o **Aplicativo Mobile (Flutter)** e o **Backend (FastAPI)** na **Entrega 2**.

---

## 1. Visão Geral da Arquitetura e Regras de Negócio

### 1.1. Lances Dinâmicos e Criação de Treinos Personalizados
* O número de lances de um treino é **totalmente dinâmico**: o atleta pode escolher treinos de catálogo ou criar treinos personalizados (ex: 8, 12, 15, 20 ou 30 lances).
* O App envia a quantidade desejada no comando de início (ex: `TREINO:12:3:0.0`).

### 1.2. Intervalo entre Lances e Detecção Automática de ERRO por Timeout
* O intervalo entre os lances é configurável (mínimo de **3 segundos** / 3000ms).
* **Detecção de ERRO no ESP32:** Se o jogador não acertar o Tobias dentro do tempo estipulado do intervalo (ex: 3s), o microcontrolador detecta a ausência de impacto por **timeout** e registra automaticamente um lance de **`erro`**:
  - `resultado: "erro"`
  - `classe: "sem_impacto"`
  - `knockout: false`
  - `angulo: 0.0`
* Isso alimenta em tempo real a tela de lances e permite ao Backend calcular a taxa de **precisão real**:
  $$\text{Precisão (\%)} = \frac{\text{Acertos}}{\text{Total de Lances}} \times 100$$

### 1.3. Classificação Física e KO (Base Inicial Fácil)
* A física é **100% baseada no ângulo 3D de inclinação do tombo**:
  - Gatilho Mínimo: $22^\circ$ (abaixo disso é ruído ou retorno elástico)
  - 🎾 **Fraco:** $22^\circ$ a $38^\circ$ $\to$ `classe: "fraco"`, `knockout: false`, áudio `0001.mp3`
  - ⚡ **Médio:** $38^\circ$ a $58^\circ$ $\to$ `classe: "medio"`, `knockout: false`, áudio `0002.mp3`
  - 🥊 **KO / Forte:** $> 58^\circ$ $\to$ `classe: "forte"`, `knockout: true`, áudio `0004.mp3`

### 1.4. Calibração Adaptativa de Dificuldade (Dificulta para Jogadores Fortes)
* **Regra de Negócio:** A calibração (5 batidas no tempo do jogador) serve para **dificultar a vida de jogadores que batem forte**:
  - Se a mediana das 5 batidas for superior a $38^\circ$ (impactos fortes), calcula-se um acréscimo de dificuldade em graus:
    $$\Delta_{\text{calib}} = \min(20.0^\circ, \text{mediana} - 38.0^\circ)$$
  - Se a mediana for $\le 38^\circ$ (golpes fracos ou normais), a dificuldade permanece $0.0^\circ$ (mantém o padrão inicial fácil, sem alteração arquitetural).
  - O valor `calibracao` é persistido no Backend na tabela do usuário (`usuario.calibracao`).
  - Toda vez que o usuário logar, o App recupera esse valor da API (`/v1/auth/eu`).
  - A cada treino iniciado, o App envia a dificuldade ao ESP32: `TREINO:QTD:INTERVALO:CALIB` (ex: `TREINO:15:3:8.5`).
  - No ESP32, os limiares sobem proporcionalmente:
    - $\text{Limiar Médio} = 38.0^\circ + \Delta_{\text{calib}}$
    - $\text{Limiar KO} = 58.0^\circ + \Delta_{\text{calib}}$
  - Na tela de **Recalibração**, o jogador pode recalibrar; o novo valor substitui o anterior no banco de dados e passa a valer para as sessões subsequentes.

---

## 2. Especificação do Bluetooth Low Energy (BLE)

* **Nome do Dispositivo:** `TOBIAS`
* **Service UUID (Nordic UART):** `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
* **Característica RX (App ➔ ESP32):** `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (Write)
* **Característica TX (ESP32 ➔ App):** `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (Notify)

---

## 3. Tabela de Comandos (App ➔ Tobias)

| Comando | Parâmetros | Descrição | Exemplo |
| :--- | :--- | :--- | :--- |
| `TREINO:QTD:INTERVALO:CALIB` | `QTD` (lances), `INTERVALO` (s ou ms, mín. 3s) e opcional `CALIB` (acréscimo de graus) | Inicia treino com controle de timeout e dificuldade adaptativa. | `TREINO:15:3:8.5` ou `TREINO:12:3:0.0` |
| `CALIBRAR:QTD` | Opcional (`QTD`, padrão 5) | Inicia calibração (5 batidas sem timeout nos limiares padrão). | `CALIBRAR:5` |
| `STOP` ou `RESET` | N/A | Cancela imediatamente a sessão e silencia áudios. | `STOP` |
| `PING` | N/A | Consulta status e contagem de bolas do Tobias. | `PING` |

---

## 4. Formatos de Mensagens JSON (Tobias ➔ App)

### 4.1. Início de Treino
```json
{
  "status": "TREINO_INICIADO",
  "total": 12,
  "intervalo_ms": 3000,
  "dificuldade": 8.5
}
```

### 4.2. Lance de ACERTO (Dentro do Tempo)
```json
{
  "tipo": "TREINO",
  "bola": 1,
  "total": 12,
  "resultado": "acerto",
  "classe": "medio",
  "knockout": false,
  "angulo": 34.5,
  "t_ms": 1420,
  "id_lance": "L-1729482-1"
}
```

### 4.3. Lance de ERRO (Tempo Limite Expirado sem Impacto)
```json
{
  "tipo": "TREINO",
  "bola": 2,
  "total": 12,
  "resultado": "erro",
  "classe": "sem_impacto",
  "knockout": false,
  "angulo": 0.0,
  "t_ms": 3000,
  "id_lance": "L-1729482-2"
}
```

### 4.4. Relatório Consolidado de Fim de Sessão
Ao atingir a meta de lances (seja por acerto ou timeout):

```json
{
  "status": "TREINO_CONCLUIDO",
  "total": 12,
  "acertos": 9,
  "erros": 3,
  "precisao": 75,
  "media_angulo": 38.4,
  "max_angulo": 56.1,
  "fracos": 2,
  "medios": 5,
  "fortes": 2,
  "kos": 2,
  "dificuldade": 8.5
}
```

---

## 5. Mapeamento de Hardware e Áudios no ESP32

* **Áudios no MicroSD (Pasta `/mp3/` em FAT32):**
  * `0001.mp3`: Golpe Fraco
  * `0002.mp3`: Golpe Médio
  * `0004.mp3`: Golpe KO / Forte
* **Duração do Áudio:** Ajustado para **1.8 segundos com fade-out suave**, garantindo que o áudio nunca atropele o intervalo mínimo de 3 segundos entre os lances.
* **Volume:** Estabilizado em **15 (de 30)** para proteger o amplificador e evitar reinícios.
* **Pinos do ESP32:**
  * I2C SDA: `GPIO 22`
  * I2C SCL: `GPIO 21`
  * Serial2 TX: `GPIO 17` (com resistor de 1kΩ no RX do DFPlayer)
  * LED Verde de Status: `GPIO 2`
