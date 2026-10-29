# 📄 Manual de Integração do Tobias (ESP32) com Aplicativo Mobile e Backend

Este documento descreve detalhadamente o **protocolo de comunicação Bluetooth Low Energy (BLE)**, os **comandos suportados**, os **formatos de JSON** e a **arquitetura de integração** entre o microcontrolador ESP32 (Tobias) e as camadas de software (Aplicativo Mobile Flutter e Backend FastAPI).

---

## 1. Visão Geral da Arquitetura e Decisão de Tráfego BLE

Para otimizar o consumo de energia, a estabilidade de conexão e a experiência de usuário (UX):

1. **Modo Calibração (5 Bolas):**
   * **Fluxo em Tempo Real (Bola a Bola):** O Tobias envia um JSON a cada bola acertada para que o Front-end atualize a **barra de progresso** ao vivo na tela do celular.
   * **Ao final da 5ª bola:** Envia o relatório final `CALIB_CONCLUIDA` com médias e picos.
2. **Modo Treino Personalizado (Ex: 15 ou 20 lances):**
   * **Fluxo Otimizado (Requisição Única ao Final):** Durante os 15 lances, o Tobias processa a física localmente, toca os áudios correspondentes (`0001` a `0004.mp3`), acende o LED e **não polui o Bluetooth com requisições intermediárias**.
   * **Ao final do 15º lance:** O Tobias emite **UMA ÚNICA REQUISIÇÃO CONSOLIDADA** (`TREINO_CONCLUIDO`) contendo todo o resumo da sessão para o App salvar no Backend.

```
┌─────────────────────────────────┐       Bluetooth (BLE)       ┌────────────────────────────────┐
│         ESP32 (TOBIAS)          │ ◄─────────────────────────► │       APLICATIVO MOBILE        │
│  - Leitura MPU-6050 (100Hz)     │     Nordic UART Service     │  - Conexão e Pareamento        │
│  - Disparo de Áudios (DFPlayer) │                             │  - Barra de Progresso (Calib)  │
│  - Consolidação do Treino       │                             │  - Relatório Final do Treino   │
└─────────────────────────────────┘                             └────────────────┬───────────────┘
                                                                                 │ HTTP REST / WebSocket
                                                                                 ▼
                                                                ┌────────────────────────────────┐
                                                                │        BACKEND / API           │
                                                                │  - Perfis de Calibração        │
                                                                │  - Histórico de Treinos        │
                                                                │  - Banco de Dados (PostgreSQL) │
                                                                └────────────────────────────────┘
```

---

## 2. Especificação do Bluetooth Low Energy (BLE)

O ESP32 opera como um **Servidor BLE (GATT Server)** utilizando o protocolo industrial **Nordic UART Service (NUS)**:

* **Nome do Dispositivo (Device Name):** `TOBIAS`
* **Service UUID:** `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
* **Característica RX (App ➔ ESP32):** `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` *(Permissão: Write / Write Without Response)*
* **Característica TX (ESP32 ➔ App):** `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` *(Permissão: Notify)*

---

## 3. Tabela de Comandos (App ➔ Tobias)

O aplicativo envia strings simples de comando pela **Característica RX**:

| Comando | Parâmetro | Descrição | Exemplo |
| :--- | :--- | :--- | :--- |
| `CALIBRAR` | Opcional (`:QTD`) | Inicia o modo de calibração com envio bola a bola (padrão: 5 bolas). | `CALIBRAR` ou `CALIBRAR:5` |
| `TREINO` | Obrigatório (`:QTD`) | Inicia treino silencioso via BLE; envia requisição única ao atingir a meta. | `TREINO:15` ou `TREINO:20` |
| `STOP` | N/A | Interrompe imediatamente qualquer sessão ativa e silencia o som. | `STOP` |
| `PING` | N/A | Checa se o Tobias está ativo e qual o estado atual. | `PING` |

---

## 4. Estrutura dos Dados JSON (Tobias ➔ App)

Todas as mensagens enviadas pelo Tobias via BLE pela **Característica TX** são em formato **JSON UTF-8**.

### 4.1. Ao Conectar no Bluetooth
```json
{
  "status": "CONECTADO",
  "dispositivo": "TOBIAS",
  "modo": "AGUARDANDO"
}
```

---

### 4.2. Início de Sessão (Calibração ou Treino)
```json
{
  "status": "CALIB_INICIADA",
  "total": 5
}
```
*(ou no caso de treino: `{"status": "TREINO_INICIADO", "total": 15}`)*

---

### 4.3. Notificação Bola a Bola (Exclusiva da Calibração para a Barra de Progresso)
A cada pancada recebida durante a calibração, o Tobias avisa o front-end para mover a barra de progresso:

```json
{
  "tipo": "CALIB",
  "bola": 1,
  "total": 5,
  "intensidade": "FORTE",
  "angulo": 55.2,
  "forca_g": 4.5
}
```

#### Definição das Categorias de `intensidade`:
* `"FRACO"`: Ângulo de $15.0^\circ$ a $30.0^\circ$ $\to$ Toca `0001.mp3`
* `"MEDIO"`: Ângulo de $30.0^\circ$ a $50.0^\circ$ $\to$ Toca `0002.mp3`
* `"FORTE"`: Ângulo de $50.0^\circ$ a $65.0^\circ$ $\to$ Toca `0003.mp3`
* `"KO"`: Ângulo $> 65.0^\circ$ (Golpe perfeito) $\to$ Toca `0004.mp3`

---

### 4.4. Requisição Única Consolidada ao Final da Sessão
Ao atingir a meta (seja a 5ª bola da calibração ou a 15ª bola do treino), o Tobias emite **uma única requisição final**:

#### Exemplo de Fim de Treino:
```json
{
  "status": "TREINO_CONCLUIDO",
  "total": 15,
  "media_angulo": 54.3,
  "max_angulo": 68.4,
  "fracos": 1,
  "medios": 4,
  "fortes": 8,
  "kos": 2
}
```

#### Exemplo de Fim de Calibração:
```json
{
  "status": "CALIB_CONCLUIDA",
  "total": 5,
  "media_angulo": 48.2,
  "max_angulo": 62.0,
  "fracos": 0,
  "medios": 2,
  "fortes": 3,
  "kos": 0
}
```

---

## 5. Regras de Negócio e Modelos de Integração

### 5.1. Classificação do Atleta pelo Backend
Com base no payload `CALIB_CONCLUIDA`, o backend classifica o atleta:

$$\text{Perfil} = \begin{cases} 
\text{Iniciante / Criança}, & \text{se } \overline{\theta} \le 35^\circ \\
\text{Intermediário}, & \text{se } 35^\circ < \overline{\theta} \le 55^\circ \\
\text{Avançado / Alta Performance}, & \text{se } \overline{\theta} > 55^\circ 
\end{cases}$$

---

### 5.2. Modelos de Código

#### Backend Python (FastAPI / Pydantic):
```python
from pydantic import BaseModel
from typing import Literal

class RelatorioSessaoDTO(BaseModel):
    usuario_id: str
    status: Literal["CALIB_CONCLUIDA", "TREINO_CONCLUIDO"]
    total: int
    media_angulo: float
    max_angulo: float
    fracos: int
    medios: int
    fortes: int
    kos: int
```

#### Mobile Flutter (Dart):
```dart
class RelatorioSessao {
  final String status;
  final int total;
  final double mediaAngulo;
  final double maxAngulo;
  final int fracos;
  final int medios;
  final int fortes;
  final int kos;

  RelatorioSessao({
    required this.status,
    required this.total,
    required this.mediaAngulo,
    required this.maxAngulo,
    required this.fracos,
    required this.medios,
    required this.fortes,
    required this.kos,
  });

  factory RelatorioSessao.fromJson(Map<String, dynamic> json) {
    return RelatorioSessao(
      status: json['status'] ?? '',
      total: json['total'] ?? 0,
      mediaAngulo: (json['media_angulo'] as num).toDouble(),
      maxAngulo: (json['max_angulo'] as num).toDouble(),
      fracos: json['fracos'] ?? 0,
      medios: json['medios'] ?? 0,
      fortes: json['fortes'] ?? 0,
      kos: json['kos'] ?? 0,
    );
  }
}
```
