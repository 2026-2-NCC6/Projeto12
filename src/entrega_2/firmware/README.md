# Firmware Oficial - Projeto Tobias (Smart Tennis) - Entrega 2

Firmware oficial embarcado no ESP32 para a **Entrega 2** do projeto Tobias.

## 📌 Funcionalidades da Entrega 2
1. **Sensoriamento Inercial em Alta Frequência (100Hz):** Leitura via hardware I2C do sensor MPU-6050 (Acelerômetro + Giroscópio) com cálculo de vetor de gravidade 3D (produto escalar para imunidade à orientação de montagem).
2. **Máquina de Estados com Filtro Anti-Rebote:** Distingue o choque agudo da bola de tênis do balanço pendular suave de volta, impedindo contagens duplicadas ou fantasmas.
3. **Classificação em 4 Níveis de Impacto:**
   - 🎾 **FRACO** ($15^\circ$ a $30^\circ$) $\to$ Toca `0001.mp3`
   - ⚡ **MÉDIO** ($30^\circ$ a $50^\circ$) $\to$ Toca `0002.mp3`
   - 💥 **FORTE** ($50^\circ$ a $65^\circ$) $\to$ Toca `0003.mp3`
   - 🥊 **K.O. / PERFEITO** ($> 65^\circ$) $\to$ Toca `0004.mp3`
4. **Reprodução Sonora de 3 Segundos com Fade-Out Suave:** Volume estabilizado em 20 (de 30), diminuindo gradualmente no último segundo para acabamento profissional sem distorções no alto-falante de 4Ω.
5. **Comunicação Bluetooth BLE Bidirecional (Nordic UART Service):**
   - Nome anunciado: `TOBIAS`.
   - Recebe comandos do aplicativo móvel (`CALIBRAR`, `TREINO:X`, `STOP`, `PING`).
   - Notifica a cada bola em tempo real via JSON (`{"tipo":"TREINO","bola":1,"total":15,...}`).
   - Emite relatório consolidado ao final de cada sessão.

---

## 🔌 Pinagem Física Confirmada
* **MPU-6050:**
  * `SDA` $\to$ **GPIO 22**
  * `SCL` $\to$ **GPIO 21**
  * `AD0` $\to$ **GND** (Endereço I2C `0x68`)
  * `VCC` $\to$ Linha Positiva
  * `GND` $\to$ Linha Negativa
* **DFPlayer Mini (HW-247A):**
  * `VCC` (Pino 1) $\to$ **5V / VIN** do ESP32
  * `RX` (Pino 2) $\to$ Resistor 1kΩ $\to$ **TX2 (GPIO 17)** do ESP32
  * `GND` (Pino 7 ou 10) $\to$ **GND**
  * `SPK_1` (Pino 6) e `SPK_2` (Pino 8) $\to$ Alto-falante de 4Ω 3W
* **LED Verde:**
  * Anodo $\to$ Resistor $\to$ **GPIO 2 (D2)**
  * Catodo $\to$ **GND**

---

## 📁 Áudios no Cartão MicroSD (Formatado em FAT32)
Pasta obrigatória na raiz: `/mp3/`
* `0001.mp3`: Golpe Fraco
* `0002.mp3`: Golpe Médio
* `0003.mp3`: Golpe Forte
* `0004.mp3`: Golpe K.O. (Perfeito)

---

## 📖 Manual de Integração com App e Backend
Consulte a documentação completa em:
[`documentos/INTEGRACAO_BLE_BACKEND_ESP32.md`](../../../documentos/INTEGRACAO_BLE_BACKEND_ESP32.md)
