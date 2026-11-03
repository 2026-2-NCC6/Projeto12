/**
 * ============================================================================
 * PROJETO TOBIAS - SMART TENNIS (FIRMWARE OFICIAL ENTREGA 2 - ESP32)
 * ============================================================================
 * 
 * Hardware:
 *   - Microcontrolador: ESP32 Dev Module
 *   - Sensor Inercial: MPU-6050 (Acelerômetro e Giroscópio)
 *   - Módulo de Áudio: DFPlayer Mini (HW-247A) com cartão MicroSD FAT32
 *   - Alto-falante: 4 Ohms / 3 Watts
 *   - LED Indicador: Verde (GPIO 2)
 * 
 * Pinagem Física Confirmada:
 *   - MPU-6050: SDA -> GPIO 22 | SCL -> GPIO 21 | AD0 -> GND (Endereço 0x68)
 *   - DFPlayer: RX -> Resistor 1kΩ -> GPIO 17 (TX2) | VCC -> 5V/VIN | GND -> GND
 *   - Alto-falante: SPK_1 (Pino 6) e SPK_2 (Pino 8) do DFPlayer
 *   - LED Verde: Anodo -> Resistor -> GPIO 2 (D2) | Catodo -> GND
 * 
 * Áudios no Cartão MicroSD (/mp3/):
 *   - 0001.mp3 -> Impacto Fraco
 *   - 0002.mp3 -> Impacto Médio
 *   - 0004.mp3 -> Impacto K.O. (Forte / Perfeito)
 * 
 * Modos de Operação:
 *   1. MODO_AGUARDANDO (Standby): O Tobias fica 100% SILENCIOSO. Não toca som,
 *      não acende LED e não processa batidas físicas enquanto o App não comandar.
 *   2. MODO_CALIBRACAO: Espera 5 batidas no tempo do usuário (sem timeout),
 *      notifica bola a bola (1/5 a 5/5) para animar o anel/barra no App.
 *   3. MODO_TREINO: Treino dinâmico com quantidade e intervalo configuráveis (mín. 3s).
 *      Detecta acertos físicos e detecta ERROS por timeout caso passe o tempo sem impacto.
 * ============================================================================
 */

#include <Wire.h>
#include <math.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- MAPEAMENTO DE PINOS ---
#define PIN_SDA 22        // MPU-6050 SDA (Fio Azul)
#define PIN_SCL 21        // MPU-6050 SCL (Fio Verde)
#define PIN_LED_VERDE 2   // LED Verde (GPIO 2)

#define RXD2 16           
#define TXD2 17           // ESP32 TX2 -> Resistor 1kΩ -> RX do DFPlayer

#define MPU_ADDR 0x68

// --- UUIDs BLE PADRÃO NORDIC UART SERVICE ---
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic = NULL;
bool deviceConnected = false;

// --- LIMIARES FÍSICOS DE INCLINAÇÃO (EM GRAUS) ---
const float ANGULO_GATILHO = 22.0; // Mínimo de 22° para validar pancada
const float ANGULO_MEDIO   = 38.0; // 22° a 38° = FRACO | 38° a 58° = MÉDIO
const float ANGULO_KO      = 58.0; // Acima de 58° = KO (FORTE)
const float ANGULO_REPOUSO = 14.0; // Abaixo de 14° = Tobias voltou a ficar em pé
float calibDificuldade     = 0.0;  // Dificuldade dinâmica configurada pela calibração (graus adicionais)

// Estados da Máquina Física do Tobias
enum EstadoFisico { REPOUSO_PRONTO, CAPTURANDO_PICO, TOCANDO_AUDIO, ESPERANDO_ESTABILIZAR };
EstadoFisico estadoFisico = REPOUSO_PRONTO;

// Modos de Operação do Sistema
enum ModoOperacao { MODO_AGUARDANDO, MODO_CALIBRACAO, MODO_TREINO };
ModoOperacao modoAtual = MODO_AGUARDANDO; // Inicia em STANDBY silencioso

// Vetor de Referência da Gravidade (calibração automática da verticalidade no setup)
float refX = 0, refY = 0, refZ = 1.0;

unsigned long tempoInicioImpacto = 0;
unsigned long tempoInicioAudio = 0;
unsigned long ultimoAjusteVolume = 0;
unsigned long tempoInicioSessao = 0;

// Temporização de Lances e Timeout (Erros)
unsigned long tempoInicioJanelaLance = 0;
unsigned long intervaloLanceMs = 3000;
const unsigned long INTERVALO_MINIMO_MS = 3000;

float picoAnguloRegistrado = 0.0;
const uint8_t VOLUME_PADRAO = 15; // Volume confortável (0 a 30)

// Contadores e Estatísticas
int bolaAtual = 0;
int totalBolasSessao = 0;
int contAcertos = 0;
int contErros = 0;
int contFraco = 0;
int contMedio = 0;
int contForte = 0;
int contKO = 0;
float somaAngulos = 0;
float maiorAngulo = 0;

// --- PROTÓTIPOS DE FUNÇÕES ---
void enviarBLE(String msg);
void enviarComandoDFPlayer(uint8_t comando, uint8_t p1, uint8_t p2);
void tocarFaixaMP3(int faixa);
void setVolume(uint8_t vol);
void pararAudio();
void lerAcelerometroRaw(float *x, float *y, float *z, bool acumular = false);
float calcularAnguloInclinacao(float ax, float ay, float az);
void iniciarCalibracao(int total);
void iniciarTreino(int total, unsigned long intervaloMs, float calib = 0.0);
void registrarErroTimeout();
void finalizarSessao();

// --- IMPLEMENTAÇÃO DE ÁUDIO DFPLAYER MINI ---

void enviarComandoDFPlayer(uint8_t comando, uint8_t p1, uint8_t p2) {
  uint8_t buffer[10] = {0x7E, 0xFF, 0x06, comando, 0x00, p1, p2, 0x00, 0x00, 0xEF};
  uint16_t checksum = 0;
  for (int i = 1; i < 7; i++) checksum += buffer[i];
  checksum = -checksum;
  buffer[7] = (uint8_t)(checksum >> 8);
  buffer[8] = (uint8_t)checksum;

  Serial2.write(buffer, 10);
  delay(30);
}

void tocarFaixaMP3(int faixa) {
  Serial.printf("🔊 [AUDIO] Disparando faixa 000%d.mp3 (Volume %d)\n", faixa, VOLUME_PADRAO);
  enviarComandoDFPlayer(0x12, 0x00, (uint8_t)faixa);
}

void setVolume(uint8_t vol) {
  if (vol > 30) vol = 30;
  enviarComandoDFPlayer(0x06, 0x00, vol);
}

void pararAudio() {
  enviarComandoDFPlayer(0x16, 0x00, 0x00);
}

// --- COMUNICAÇÃO BLUETOOTH BLE ---

void enviarBLE(String msg) {
  if (deviceConnected && pTxCharacteristic != NULL) {
    // '\n' marca o fim de cada JSON para o app (que junta os pacotes BLE por linha)
    String linha = msg + "\n";
    pTxCharacteristic->setValue(linha.c_str());
    pTxCharacteristic->notify();
  }
  Serial.print("📱 [BLE TX] -> ");
  Serial.println(msg);
}

class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("📱 Celular conectado ao Tobias!");
    enviarBLE("{\"status\":\"CONECTADO\",\"dispositivo\":\"TOBIAS\",\"modo\":\"AGUARDANDO\"}");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("📱 Celular desconectado.");
    pServer->startAdvertising();
  }
};

class MyRxCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String comando = pCharacteristic->getValue().c_str();
    comando.trim();
    Serial.print("📩 [BLE RX] Comando recebido: ");
    Serial.println(comando);

    // 1. Iniciar Calibração (App envia "CALIBRAR" ou "CALIBRAR:5")
    if (comando.startsWith("CALIBRAR")) {
      int bolas = 5;
      int index = comando.indexOf(':');
      if (index != -1) {
        bolas = comando.substring(index + 1).toInt();
        if (bolas <= 0) bolas = 5;
      }
      iniciarCalibracao(bolas);
    }
    // 2. Iniciar Treino (App envia "TREINO:15:5" ou "TREINO:12:3:8.5"...)
    else if (comando.startsWith("TREINO")) {
      int qtd = 15;
      unsigned long intervalo = INTERVALO_MINIMO_MS;
      float calib = 0.0;

      int primeiroDoisPontos = comando.indexOf(':');
      if (primeiroDoisPontos != -1) {
        int segundoDoisPontos = comando.indexOf(':', primeiroDoisPontos + 1);
        if (segundoDoisPontos != -1) {
          qtd = comando.substring(primeiroDoisPontos + 1, segundoDoisPontos).toInt();
          int terceiroDoisPontos = comando.indexOf(':', segundoDoisPontos + 1);
          if (terceiroDoisPontos != -1) {
            unsigned long val = comando.substring(segundoDoisPontos + 1, terceiroDoisPontos).toInt();
            intervalo = (val < 100) ? (val * 1000) : val;
            calib = comando.substring(terceiroDoisPontos + 1).toFloat();
          } else {
            unsigned long val = comando.substring(segundoDoisPontos + 1).toInt();
            intervalo = (val < 100) ? (val * 1000) : val;
          }
        } else {
          qtd = comando.substring(primeiroDoisPontos + 1).toInt();
        }
      }

      if (qtd <= 0) qtd = 15;
      if (intervalo < INTERVALO_MINIMO_MS) intervalo = INTERVALO_MINIMO_MS;

      iniciarTreino(qtd, intervalo, calib);
    }
    // 3. Cancelar Sessão / Voltar ao Standby Silencioso
    else if (comando == "STOP" || comando == "CANCELAR" || comando == "RESET") {
      modoAtual = MODO_AGUARDANDO;
      bolaAtual = 0;
      totalBolasSessao = 0;
      pararAudio();
      setVolume(VOLUME_PADRAO);
      digitalWrite(PIN_LED_VERDE, LOW);
      enviarBLE("{\"status\":\"CANCELADO\",\"modo\":\"AGUARDANDO\"}");
      Serial.println("🛑 Sessão cancelada. Tobias em STANDBY silencioso.");
    }
    // 4. Ping / Status
    else if (comando == "PING") {
      String mStr = (modoAtual == MODO_CALIBRACAO) ? "CALIBRACAO" : (modoAtual == MODO_TREINO) ? "TREINO" : "AGUARDANDO";
      enviarBLE("{\"status\":\"PONG\",\"modo\":\"" + mStr + "\",\"bola_atual\":" + String(bolaAtual) + "}");
    }
  }
};

void iniciarCalibracao(int total) {
  modoAtual = MODO_CALIBRACAO;
  totalBolasSessao = total;
  bolaAtual = 0;
  contAcertos = contErros = 0;
  contFraco = contMedio = contForte = contKO = 0;
  somaAngulos = 0;
  maiorAngulo = 0;
  calibDificuldade = 0.0; // Na calibração sempre usa os limiares base
  tempoInicioSessao = millis();

  digitalWrite(PIN_LED_VERDE, HIGH); delay(200); digitalWrite(PIN_LED_VERDE, LOW);
  tocarFaixaMP3(1); // Som curto de sinalização
  enviarBLE("{\"status\":\"CALIB_INICIADA\",\"total\":" + String(totalBolasSessao) + "}");
  Serial.printf("🎾 Modo CALIBRAÇÃO iniciado: %d batidas aguardadas.\n", totalBolasSessao);
}

void iniciarTreino(int total, unsigned long intervaloMs, float calib) {
  modoAtual = MODO_TREINO;
  totalBolasSessao = total;
  intervaloLanceMs = intervaloMs;
  calibDificuldade = (calib > 0.0) ? calib : 0.0;
  bolaAtual = 0;
  contAcertos = contErros = 0;
  contFraco = contMedio = contForte = contKO = 0;
  somaAngulos = 0;
  maiorAngulo = 0;
  tempoInicioSessao = millis();
  tempoInicioJanelaLance = millis();

  Serial.printf("🎯 Treino Iniciado: %d lances | Intervalo: %lu ms | Dificuldade: +%.1f°\n", 
                totalBolasSessao, intervaloLanceMs, calibDificuldade);

  for (int i = 0; i < 2; i++) {
    digitalWrite(PIN_LED_VERDE, HIGH); delay(100);
    digitalWrite(PIN_LED_VERDE, LOW);  delay(100);
  }
  tocarFaixaMP3(2);

  String json = "{\"status\":\"TREINO_INICIADO\",\"total\":" + String(totalBolasSessao) + 
                ",\"intervalo_ms\":" + String(intervaloLanceMs) + 
                ",\"dificuldade\":" + String(calibDificuldade, 1) + "}";
  enviarBLE(json);
}

void registrarErroTimeout() {
  bolaAtual++;
  contErros++;
  unsigned long tMs = (tempoInicioSessao > 0) ? (millis() - tempoInicioSessao) : millis();
  String idLance = "L-" + String(millis()) + "-" + String(bolaAtual);

  Serial.printf("❌ [ERRO] Lance %d/%d: Tempo limite expirado (%lu ms) sem impacto!\n", 
                bolaAtual, totalBolasSessao, intervaloLanceMs);

  digitalWrite(PIN_LED_VERDE, HIGH); delay(60); digitalWrite(PIN_LED_VERDE, LOW);

  String jsonErro = String("{\"tipo\":\"TREINO\",\"bola\":") + String(bolaAtual) + 
                    ",\"total\":" + String(totalBolasSessao) + 
                    ",\"resultado\":\"erro\"" +
                    ",\"classe\":\"sem_impacto\"" +
                    ",\"knockout\":false" +
                    ",\"angulo\":0.0" +
                    ",\"t_ms\":" + String(tMs) + 
                    ",\"id_lance\":\"" + idLance + "\"}";
  enviarBLE(jsonErro);

  tempoInicioJanelaLance = millis();

  if (bolaAtual >= totalBolasSessao) {
    finalizarSessao();
  }
}

void finalizarSessao() {
  float media = (contAcertos > 0) ? (somaAngulos / contAcertos) : 0;
  int precisao = (totalBolasSessao > 0) ? ((contAcertos * 100) / totalBolasSessao) : 0;
  String tipoSessao = (modoAtual == MODO_CALIBRACAO) ? "CALIB_CONCLUIDA" : "TREINO_CONCLUIDO";

  String jsonRelatorio = String("{\"status\":\"") + tipoSessao + "\"" +
                         ",\"total\":" + String(totalBolasSessao) + 
                         ",\"acertos\":" + String(contAcertos) + 
                         ",\"erros\":" + String(contErros) + 
                         ",\"precisao\":" + String(precisao) + 
                         ",\"media_angulo\":" + String(media, 1) + 
                         ",\"max_angulo\":" + String(maiorAngulo, 1) + 
                         ",\"fracos\":" + String(contFraco) + 
                         ",\"medios\":" + String(contMedio) + 
                         ",\"fortes\":" + String(contForte) + 
                         ",\"kos\":" + String(contKO) + 
                         ",\"dificuldade\":" + String(calibDificuldade, 1) + "}";
  enviarBLE(jsonRelatorio);

  // Retorna imediatamente para o MODO_AGUARDANDO silencioso
  modoAtual = MODO_AGUARDANDO;
  bolaAtual = 0;
  totalBolasSessao = 0;
  digitalWrite(PIN_LED_VERDE, LOW);
  Serial.println("🔒 Sessão finalizada. Tobias retornou ao STANDBY silencioso.");
}

// --- MPU-6050 ---

void lerAcelerometroRaw(float *x, float *y, float *z, bool acumular) {
  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  Wire.requestFrom((uint16_t)MPU_ADDR, (uint8_t)6, true);

  if (Wire.available() >= 6) {
    int16_t rawX = (Wire.read() << 8) | Wire.read();
    int16_t rawY = (Wire.read() << 8) | Wire.read();
    int16_t rawZ = (Wire.read() << 8) | Wire.read();

    float ax = (float)rawX / 2048.0;
    float ay = (float)rawY / 2048.0;
    float az = (float)rawZ / 2048.0;

    if (acumular) {
      *x += ax; *y += ay; *z += az;
    } else {
      *x = ax; *y = ay; *z = az;
    }
  }
}

float calcularAnguloInclinacao(float ax, float ay, float az) {
  float mod = sqrt(ax * ax + ay * ay + az * az);
  if (mod < 0.1) return 0.0;
  float dot = (ax * refX + ay * refY + az * refZ) / mod;
  if (dot > 1.0) dot = 1.0;
  if (dot < -1.0) dot = -1.0;
  return acos(dot) * (180.0 / 3.14159265);
}

// --- SETUP ---

void setup() {
  Serial.begin(115200);
  delay(500);

  pinMode(PIN_LED_VERDE, OUTPUT);
  digitalWrite(PIN_LED_VERDE, LOW);

  Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2);

  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setTimeOut(50);

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x6B);
  Wire.write(0x00);
  Wire.endTransmission();

  Wire.beginTransmission(MPU_ADDR);
  Wire.write(0x1C);
  Wire.write(0x18); // 16G
  Wire.endTransmission();

  Serial.println("\n--- CALIBRANDO VERTICALIDADE DE REPOUSO DO TOBIAS ---");
  float somaX = 0, somaY = 0, somaZ = 0;
  for (int i = 0; i < 50; i++) {
    lerAcelerometroRaw(&somaX, &somaY, &somaZ, true);
    delay(20);
  }
  float modRef = sqrt(somaX * somaX + somaY * somaY + somaZ * somaZ);
  refX = somaX / modRef;
  refY = somaY / modRef;
  refZ = somaZ / modRef;

  BLEDevice::init("TOBIAS");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyRxCallbacks());

  pService->start();

  // Anuncia o UUID do serviço NUS junto com o nome, para o app encontrar o Tobias no scan
  BLEAdvertising *pAdvertising = pServer->getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->start();

  Serial.println("Inicializando DFPlayer Mini...");
  delay(1500);
  setVolume(VOLUME_PADRAO); // Volume 15

  // 3 piscadas confirmando que o sistema ligou
  for (int i = 0; i < 3; i++) {
    digitalWrite(PIN_LED_VERDE, HIGH); delay(100);
    digitalWrite(PIN_LED_VERDE, LOW);  delay(100);
  }

  Serial.println("===========================================================");
  Serial.println("  SISTEMA TOBIAS ONLINE - EM STANDBY SILENCIOSO           ");
  Serial.println("  Aguardando comando do App ('TREINO' ou 'CALIBRAR')...   ");
  Serial.println("===========================================================");
}

// --- LOOP PRINCIPAL ---

void loop() {
  // REGRA DE OURO: SE NÃO ESTIVER EM TREINO NEM CALIBRAÇÃO, FICA 100% SILENCIOSO!
  // Nenhuma batida, balanço ou toque emite som ou acende LED no modo de espera.
  if (modoAtual == MODO_AGUARDANDO) {
    delay(40);
    return;
  }

  float ax = 0, ay = 0, az = 0;
  lerAcelerometroRaw(&ax, &ay, &az);
  float anguloAtual = calcularAnguloInclinacao(ax, ay, az);

  // 1. CHECAGEM DE TIMEOUT (APENAS NO MODO TREINO)
  // No modo calibração NÃO há timeout: o atleta bate as 5 bolas no tempo dele
  if (modoAtual == MODO_TREINO && estadoFisico == REPOUSO_PRONTO) {
    if (millis() - tempoInicioJanelaLance >= intervaloLanceMs) {
      registrarErroTimeout();
    }
  }

  // 2. MÁQUINA DE ESTADOS FÍSICA
  switch (estadoFisico) {

    case REPOUSO_PRONTO:
      if (anguloAtual >= ANGULO_GATILHO) {
        tempoInicioImpacto = millis();
        picoAnguloRegistrado = anguloAtual;
        estadoFisico = CAPTURANDO_PICO;
      }
      break;

    case CAPTURANDO_PICO:
      if (anguloAtual > picoAnguloRegistrado) {
        picoAnguloRegistrado = anguloAtual;
      }

      if (millis() - tempoInicioImpacto >= 350) {
        String classe = "fraco";
        bool knockout = false;
        int somTocar = 1;

        // Limiares ajustados dinamicamente com base na calibração do jogador
        float limiarKO = ANGULO_KO + calibDificuldade;
        float limiarMedio = ANGULO_MEDIO + calibDificuldade;

        if (picoAnguloRegistrado >= limiarKO) {
          classe = "forte";
          knockout = true;
          somTocar = 4; // 0004.mp3 (KO)
          contForte++;
          contKO++;
        }
        else if (picoAnguloRegistrado >= limiarMedio) {
          classe = "medio";
          knockout = false;
          somTocar = 2; // 0002.mp3 (Médio)
          contMedio++;
        }
        else {
          classe = "fraco";
          knockout = false;
          somTocar = 1; // 0001.mp3 (Fraco)
          contFraco++;
        }

        somaAngulos += picoAnguloRegistrado;
        if (picoAnguloRegistrado > maiorAngulo) maiorAngulo = picoAnguloRegistrado;

        // Dispara o som e acende o LED
        setVolume(VOLUME_PADRAO);
        tocarFaixaMP3(somTocar);
        digitalWrite(PIN_LED_VERDE, HIGH);

        unsigned long tMs = (tempoInicioSessao > 0) ? (millis() - tempoInicioSessao) : millis();
        bolaAtual++;
        contAcertos++;

        String tipoMsg = (modoAtual == MODO_CALIBRACAO) ? "CALIB" : "TREINO";
        String idLance = "L-" + String(millis()) + "-" + String(bolaAtual);

        String jsonLance = String("{\"tipo\":\"") + tipoMsg + "\"" +
                           ",\"bola\":" + String(bolaAtual) + 
                           ",\"total\":" + String(totalBolasSessao) + 
                           ",\"resultado\":\"acerto\"" +
                           ",\"classe\":\"" + classe + "\"" +
                           ",\"knockout\":" + (knockout ? "true" : "false") + 
                           ",\"angulo\":" + String(picoAnguloRegistrado, 1) + 
                           ",\"t_ms\":" + String(tMs) + 
                           ",\"id_lance\":\"" + idLance + "\"}";
        enviarBLE(jsonLance);

        tempoInicioJanelaLance = millis(); // Reinicia janela do próximo lance
        tempoInicioAudio = millis();
        ultimoAjusteVolume = millis();
        estadoFisico = TOCANDO_AUDIO;
      }
      break;

    case TOCANDO_AUDIO: {
      unsigned long tempoDecorrido = millis() - tempoInicioAudio;

      if (tempoDecorrido >= 1200 && tempoDecorrido < 1800) {
        if (millis() - ultimoAjusteVolume >= 100) {
          ultimoAjusteVolume = millis();
          float progresso = (float)(tempoDecorrido - 1200) / 600.0;
          uint8_t volFade = VOLUME_PADRAO - (uint8_t)(progresso * (VOLUME_PADRAO - 2));
          setVolume(volFade);
        }
      }

      if (tempoDecorrido >= 1800) {
        pararAudio();
        setVolume(VOLUME_PADRAO);
        digitalWrite(PIN_LED_VERDE, LOW);

        if (bolaAtual >= totalBolasSessao) {
          finalizarSessao();
        }

        estadoFisico = ESPERANDO_ESTABILIZAR;
      }
      break;
    }

    case ESPERANDO_ESTABILIZAR:
      if (anguloAtual < ANGULO_REPOUSO) {
        estadoFisico = REPOUSO_PRONTO;
      }
      break;
  }

  delay(10);
}
