#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Inicialização dos módulos
Adafruit_MPU6050 mpu;

// Configuração BLE (Serviço UART Padrão)
BLEServer *pServer = NULL;
BLECharacteristic *pTxCharacteristic;
bool deviceConnected = false;
#define SERVICE_UUID "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    pServer->startAdvertising(); // Volta a anunciar se desconectar
  }
};

// Definição dos pinos dos LEDs
const int LED_VERDE = 25;
const int LED_AMARELO = 26;
const int LED_VERMELHO = 27;

// Pinos de comunicação com o DFPlayer Mini
#define RXD2 16
#define TXD2 17

// Limiares de aceleração e impulso
const float LIMIAR_FRACO = 14.0;
const float LIMIAR_MEDIO = 22.0;
const float LIMIAR_FORTE = 35.0;
const float LIMIAR_IMPULSO = 8.0; // Variação brusca mínima (Delta) para considerar uma NOVA pancada

unsigned long tempoUltimoImpacto = 0;
const int intervaloBloqueio = 300; // Reduzido de 1500ms para 300ms para capturar bolas seguidas

// Variáveis para física e LEDs não-bloqueantes
float forcaAnterior = 9.81;
unsigned long tempoLedsAcesos = 0;
bool ledsEstaoAcesos = false;
const int tempoExibicaoLed = 1000;

// Função para enviar comandos ao DFPlayer Mini
void enviarComandoDFPlayer(uint8_t comando, uint8_t parametro1, uint8_t parametro2) {
  uint8_t buffer[10] = {0x7E, 0xFF, 0x06, comando, 0x00, parametro1, parametro2, 0x00, 0x00, 0xEF};
  uint16_t checksum = 0;
  for (int i = 1; i < 7; i++) {
    checksum += buffer[i];
  }
  checksum = -checksum;
  buffer[7] = (uint8_t)(checksum >> 8);
  buffer[8] = (uint8_t)checksum;
  Serial2.write(buffer, 10);
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(9600, SERIAL_8N1, RXD2, TXD2);

  // Inicializa os pinos dos LEDs
  pinMode(LED_VERDE, OUTPUT);
  pinMode(LED_AMARELO, OUTPUT);
  pinMode(LED_VERMELHO, OUTPUT);
  digitalWrite(LED_VERDE, LOW);
  digitalWrite(LED_AMARELO, LOW);
  digitalWrite(LED_VERMELHO, LOW);

  // --- Inicialização do BLE ---
  BLEDevice::init("JoaoBobo_BLE");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());
  BLEService *pService = pServer->createService(SERVICE_UUID);
  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  pServer->getAdvertising()->start();
  Serial.println("BLE iniciado! Aguardando conexão...");

  // Inicializa o sensor MPU6050
  if (!mpu.begin()) {
    Serial.println("Falha ao encontrar o chip MPU6050!");
    while (1) { delay(10); }
  }
  mpu.setAccelerometerRange(MPU6050_RANGE_16_G);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);

  delay(500);
  enviarComandoDFPlayer(0x06, 0x00, 0x1E); // Volume 30
}

void loop() {
  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  float forcaResultante = sqrt(a.acceleration.x * a.acceleration.x +
                               a.acceleration.y * a.acceleration.y +
                               a.acceleration.z * a.acceleration.z);

  // O pulo do gato: diferença entre a leitura de agora e a leitura de 10ms atrás
  float deltaForca = abs(forcaResultante - forcaAnterior);

  // Lógica de Impulso: A força superou o mínimo E houve uma variação muito brusca (Impacto)
  if (forcaResultante > LIMIAR_FRACO && deltaForca > LIMIAR_IMPULSO && (millis() - tempoUltimoImpacto > intervaloBloqueio)) {
    tempoUltimoImpacto = millis();
    
    // Liga a flag dos LEDs de forma não-bloqueante
    tempoLedsAcesos = millis();
    ledsEstaoAcesos = true;
    digitalWrite(LED_VERDE, LOW);
    digitalWrite(LED_AMARELO, LOW);
    digitalWrite(LED_VERMELHO, LOW);

    String mensagemBLE = "";

    if (forcaResultante >= LIMIAR_FORTE) {
      mensagemBLE = "IMPACTO FORTE: " + String(forcaResultante) + "G";
      digitalWrite(LED_VERDE, HIGH);
      digitalWrite(LED_AMARELO, HIGH);
      digitalWrite(LED_VERMELHO, HIGH);
      enviarComandoDFPlayer(0x03, 0x00, 0x03);
    }
    else if (forcaResultante >= LIMIAR_MEDIO) {
      mensagemBLE = "IMPACTO MEDIO: " + String(forcaResultante) + "G";
      digitalWrite(LED_VERDE, HIGH);
      digitalWrite(LED_AMARELO, HIGH);
      enviarComandoDFPlayer(0x03, 0x00, 0x02);
    }
    else {
      mensagemBLE = "IMPACTO FRACO: " + String(forcaResultante) + "G";
      digitalWrite(LED_VERDE, HIGH);
      enviarComandoDFPlayer(0x03, 0x00, 0x01);
    }

    Serial.println(mensagemBLE);

    // Envia o dado via BLE se o telemóvel estiver conectado
    if (deviceConnected) {
      pTxCharacteristic->setValue(mensagemBLE.c_str());
      pTxCharacteristic->notify();
    }
  }
  
  // Guarda a força atual para comparar na próxima iteração
  forcaAnterior = forcaResultante;

  // Lógica de apagamento dos LEDs baseada no tempo (Sem usar Delay!)
  if (ledsEstaoAcesos && (millis() - tempoLedsAcesos >= tempoExibicaoLed)) {
    digitalWrite(LED_VERDE, LOW);
    digitalWrite(LED_AMARELO, LOW);
    digitalWrite(LED_VERMELHO, LOW);
    ledsEstaoAcesos = false;
  }
  
  delay(10); // Amostragem a ~100Hz
}