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
 * Pinagem Física:
 *   - MPU-6050: SDA -> GPIO 22 | SCL -> GPIO 21 | AD0 -> GND (Endereço 0x68)
 *   - DFPlayer: RX -> Resistor 1kΩ -> GPIO 17 (TX2) | VCC -> 5V/VIN | GND -> GND
 *   - Alto-falante: SPK_1 (Pino 6) e SPK_2 (Pino 8) do DFPlayer
 *   - LED Verde: Anodo -> Resistor -> GPIO 2 (D2) | Catodo -> GND
 * 
 * Áudios no Cartão MicroSD (/mp3/):
 *   - 0001.mp3 -> Impacto Fraco
 *   - 0002.mp3 -> Impacto Médio
 *   - 0003.mp3 -> Impacto Forte
 *   - 0004.mp3 -> Impacto K.O. (Perfeito)
 * 
 * Regra de Comunicação BLE:
 *   - Calibração: Notifica bola a bola para atualizar a barra de progresso do front.
 *   - Treino: Executa silenciosamente e envia UMA ÚNICA requisição ao final da sessão.
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

// --- CONFIGURAÇÕES DE IMPACTO E INCLINAÇÃO ---
const float LIMIAR_CHOQUE_DELTA = 0.70; // Choque brusco inicial em G's
const float ANGULO_MIN_IMPACTO  = 12.0; // Ângulo mínimo para validar tombo
const float ANGULO_ESTABILIZADO = 10.0; // Tobias voltou à verticalidade

// Categorias de Pancada
const float ANGULO_FRACO = 15.0; // 15° a 30° -> 0001.mp3
const float ANGULO_MEDIO = 30.0; // 30° a 50° -> 0002.mp3
const float ANGULO_FORTE = 50.0; // 50° a 65° -> 0003.mp3
const float ANGULO_KO    = 65.0; // Acima de 65° -> 0004.mp3 (K.O. / Perfeito)

// Estados da Máquina Física do Tobias
enum EstadoFisico { REPOUSO_PRONTO, CAPTURANDO_PICO, TOCANDO_AUDIO, ESPERANDO_ESTABILIZAR };
EstadoFisico estadoFisico = REPOUSO_PRONTO;

// Modos de Operação do Sistema
enum ModoOperacao { MODO_AGUARDANDO, MODO_CALIBRACAO, MODO_TREINO };
ModoOperacao modoAtual = MODO_AGUARDANDO;

// Vetor de Referência da Gravidade (calibração automática em pé)
float refX = 0, refY = 0, refZ = 1.0;
float forcaGAnterior = 1.0;

unsigned long tempoInicioImpacto = 0;
unsigned long tempoInicioAudio = 0;
unsigned long ultimoAjusteVolume = 0;

float picoAnguloRegistrado = 0.0;
float picoForcaGRegistrado = 0.0;

// Configurações de Áudio
const uint8_t VOLUME_PADRAO = 20; // Volume ideal seguro (0 a 30)

// Contadores de Sessão
int bolaAtual = 0;
int totalBolasSessao = 0;

// Estatísticas da Sessão
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
void iniciarTreino(int total);
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
  Serial.printf("🔊 [AUDIO] Disparando faixa 000%d.mp3 (3s com fade-out)\n", faixa);
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
    pTxCharacteristic->setValue(msg.c_str());
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
    Serial.println("📱 Celular desconectado. Aguardando reconexao...");
    pServer->startAdvertising();
  }
};

// Processador de Comandos Recebidos do App
class MyRxCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    String comando = pCharacteristic->getValue().c_str();
    comando.trim();
    Serial.print("📩 [BLE RX] Comando recebido: ");
    Serial.println(comando);

    // 1. Comando de Calibração (Ex: "CALIBRAR" ou "CALIBRAR:5")
    if (comando.startsWith("CALIBRAR")) {
      int bolas = 5;
      int index = comando.indexOf(':');
      if (index != -1) {
        bolas = comando.substring(index + 1).toInt();
        if (bolas <= 0) bolas = 5;
      }
      iniciarCalibracao(bolas);
    }
    // 2. Comando de Treino Personalizado (Ex: "TREINO:15" ou "TREINO:20")
    else if (comando.startsWith("TREINO")) {
      int bolas = 15;
      int index = comando.indexOf(':');
      if (index != -1) {
        bolas = comando.substring(index + 1).toInt();
        if (bolas <= 0) bolas = 15;
      }
      iniciarTreino(bolas);
    }
    // 3. Cancelar Sessão Atual / Reset
    else if (comando == "STOP" || comando == "CANCELAR" || comando == "RESET") {
      modoAtual = MODO_AGUARDANDO;
      bolaAtual = 0;
      totalBolasSessao = 0;
      pararAudio();
      setVolume(VOLUME_PADRAO);
      enviarBLE("{\"status\":\"CANCELADO\",\"modo\":\"AGUARDANDO\"}");
    }
    // 4. Ping / Checagem de Status
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
  contFraco = contMedio = contForte = contKO = 0;
  somaAngulos = 0;
  maiorAngulo = 0;

  digitalWrite(PIN_LED_VERDE, HIGH); delay(200); digitalWrite(PIN_LED_VERDE, LOW);
  tocarFaixaMP3(1);
  enviarBLE("{\"status\":\"CALIB_INICIADA\",\"total\":" + String(totalBolasSessao) + "}");
}

void iniciarTreino(int total) {
  modoAtual = MODO_TREINO;
  totalBolasSessao = total;
  bolaAtual = 0;
  contFraco = contMedio = contForte = contKO = 0;
  somaAngulos = 0;
  maiorAngulo = 0;

  for (int i = 0; i < 2; i++) {
    digitalWrite(PIN_LED_VERDE, HIGH); delay(100);
    digitalWrite(PIN_LED_VERDE, LOW);  delay(100);
  }
  tocarFaixaMP3(2); // Som de início do treino
  enviarBLE("{\"status\":\"TREINO_INICIADO\",\"total\":" + String(totalBolasSessao) + "}");
}

void finalizarSessao() {
  float media = (totalBolasSessao > 0) ? (somaAngulos / totalBolasSessao) : 0;
  String tipoSessao = (modoAtual == MODO_CALIBRACAO) ? "CALIB_CONCLUIDA" : "TREINO_CONCLUIDO";

  // Envia a requisição única consolidada final
  String jsonRelatorio = "{\"status\":\"" + tipoSessao + "\"" +
                         ",\"total\":" + String(totalBolasSessao) + 
                         ",\"media_angulo\":" + String(media, 1) + 
                         ",\"max_angulo\":" + String(maiorAngulo, 1) + 
                         ",\"fracos\":" + String(contFraco) + 
                         ",\"medios\":" + String(contMedio) + 
                         ",\"fortes\":" + String(contForte) + 
                         ",\"kos\":" + String(contKO) + "}";
  enviarBLE(jsonRelatorio);

  modoAtual = MODO_AGUARDANDO;
  bolaAtual = 0;
  totalBolasSessao = 0;
}

// --- LEITURA E FÍSICA DO MPU-6050 ---

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

  // Servidor BLE
  BLEDevice::init("TOBIAS");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_TX, BLECharacteristic::PROPERTY_NOTIFY);
  pTxCharacteristic->addDescriptor(new BLE2902());

  BLECharacteristic *pRxCharacteristic = pService->createCharacteristic(CHARACTERISTIC_UUID_RX, BLECharacteristic::PROPERTY_WRITE);
  pRxCharacteristic->setCallbacks(new MyRxCallbacks());

  pService->start();
  pServer->getAdvertising()->start();

  Serial.println("Inicializando DFPlayer Mini...");
  delay(1500);
  setVolume(VOLUME_PADRAO);

  for (int i = 0; i < 3; i++) {
    digitalWrite(PIN_LED_VERDE, HIGH); delay(100);
    digitalWrite(PIN_LED_VERDE, LOW);  delay(100);
  }

  Serial.println("===========================================================");
  Serial.println("  SISTEMA TOBIAS ONLINE - PRONTO PARA CONEXAO DO APP      ");
  Serial.println("===========================================================");
}

// --- LOOP ---

void loop() {
  float ax = 0, ay = 0, az = 0;
  lerAcelerometroRaw(&ax, &ay, &az);

  float forcaG = sqrt(ax * ax + ay * ay + az * az);
  float deltaChoque = abs(forcaG - forcaGAnterior);
  float anguloAtual = calcularAnguloInclinacao(ax, ay, az);

  switch (estadoFisico) {

    case REPOUSO_PRONTO:
      if (deltaChoque > LIMIAR_CHOQUE_DELTA && anguloAtual > ANGULO_MIN_IMPACTO) {
        tempoInicioImpacto = millis();
        picoAnguloRegistrado = anguloAtual;
        picoForcaGRegistrado = forcaG;
        estadoFisico = CAPTURANDO_PICO;
      }
      break;

    case CAPTURANDO_PICO:
      if (anguloAtual > picoAnguloRegistrado) picoAnguloRegistrado = anguloAtual;
      if (forcaG > picoForcaGRegistrado) picoForcaGRegistrado = forcaG;

      if (millis() - tempoInicioImpacto >= 350) {
        String intensidade = "FRACO";
        int somTocar = 1;

        if (picoAnguloRegistrado >= ANGULO_KO) {
          intensidade = "KO";
          somTocar = 4; // 0004.mp3 (K.O. / Perfeito)
          contKO++;
        }
        else if (picoAnguloRegistrado >= ANGULO_FORTE) {
          intensidade = "FORTE";
          somTocar = 3; // 0003.mp3
          contForte++;
        }
        else if (picoAnguloRegistrado >= ANGULO_MEDIO) {
          intensidade = "MEDIO";
          somTocar = 2; // 0002.mp3
          contMedio++;
        }
        else {
          intensidade = "FRACO";
          somTocar = 1; // 0001.mp3
          contFraco++;
        }

        somaAngulos += picoAnguloRegistrado;
        if (picoAnguloRegistrado > maiorAngulo) maiorAngulo = picoAnguloRegistrado;

        setVolume(VOLUME_PADRAO);
        tocarFaixaMP3(somTocar);
        digitalWrite(PIN_LED_VERDE, HIGH);

        // 1. MODO CALIBRAÇÃO: Notifica bola a bola para o front-end mover a barra de progresso!
        if (modoAtual == MODO_CALIBRACAO) {
          bolaAtual++;
          String jsonBola = "{\"tipo\":\"CALIB\"" +
                            ",\"bola\":" + String(bolaAtual) + 
                            ",\"total\":" + String(totalBolasSessao) + 
                            ",\"intensidade\":\"" + intensidade + "\"" +
                            ",\"angulo\":" + String(picoAnguloRegistrado, 1) + 
                            ",\"forca_g\":" + String(picoForcaGRegistrado, 1) + "}";
          enviarBLE(jsonBola);
        }
        // 2. MODO TREINO: Apenas conta a bola internamente (NÃO envia pacotes intermediários)
        else if (modoAtual == MODO_TREINO) {
          bolaAtual++;
          Serial.printf("🎾 [TREINO] Lance %d/%d registrado (Tombo: %.1f° | Força: %s)\n",
                        bolaAtual, totalBolasSessao, picoAnguloRegistrado, intensidade.c_str());
        }
        // 3. MODO LIVRE: Golpe avulso fora de sessão
        else {
          String jsonLivre = "{\"tipo\":\"GOLPE_LIVRE\"" +
                             ",\"intensidade\":\"" + intensidade + "\"" +
                             ",\"angulo\":" + String(picoAnguloRegistrado, 1) + 
                             ",\"forca_g\":" + String(picoForcaGRegistrado, 1) + "}";
          enviarBLE(jsonLivre);
        }

        tempoInicioAudio = millis();
        ultimoAjusteVolume = millis();
        estadoFisico = TOCANDO_AUDIO;
      }
      break;

    case TOCANDO_AUDIO: {
      unsigned long tempoDecorrido = millis() - tempoInicioAudio;

      if (tempoDecorrido >= 2000 && tempoDecorrido < 3000) {
        if (millis() - ultimoAjusteVolume >= 150) {
          ultimoAjusteVolume = millis();
          float progresso = (float)(tempoDecorrido - 2000) / 1000.0;
          uint8_t volFade = VOLUME_PADRAO - (uint8_t)(progresso * (VOLUME_PADRAO - 3));
          setVolume(volFade);
        }
      }

      if (tempoDecorrido >= 3000) {
        pararAudio();
        setVolume(VOLUME_PADRAO);
        digitalWrite(PIN_LED_VERDE, LOW);

        // Se completou a sessão (Calibração ou Treino) -> Dispara a requisição final consolidada!
        if ((modoAtual == MODO_CALIBRACAO || modoAtual == MODO_TREINO) && bolaAtual >= totalBolasSessao) {
          finalizarSessao();
        }

        estadoFisico = ESPERANDO_ESTABILIZAR;
      }
      break;
    }

    case ESPERANDO_ESTABILIZAR:
      if (anguloAtual < ANGULO_ESTABILIZADO && deltaChoque < 0.25) {
        estadoFisico = REPOUSO_PRONTO;
      }
      break;
  }

  forcaGAnterior = forcaG;
  delay(10);
}
