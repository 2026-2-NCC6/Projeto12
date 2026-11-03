/// Interface que isola o BLE: as telas dependem dela e nunca falam com o
/// Bluetooth direto.
library;

/// Impacto ou lance medido pelo ESP32 (ou gerado pelo simulador).
class ImpactEvent {
  const ImpactEvent({
    required this.aPkG,
    this.tMs = 0,
    this.resultado = 'acerto',
    this.classe = 'medio',
    this.knockout = false,
    this.bola = 0,
    this.idLance = '',
  });

  /// Pico de aceleração ou ângulo medido em graus.
  final double aPkG;

  /// Instante do impacto no relógio do ESP32, em ms.
  final int tMs;

  /// 'acerto' ou 'erro' (por timeout de intervalo sem impacto).
  final String resultado;

  /// 'fraco', 'medio', 'forte' ou 'sem_impacto'.
  final String classe;

  /// True se ultrapassou o limiar de KO (pancada forte / derrubada).
  final bool knockout;

  /// Número sequencial da bola no treino.
  final int bola;

  /// Identificador único gerado pelo ESP32 (ex: L-1729482-1).
  final String idLance;
}

enum DeviceCommand {
  iniciarCalibracao,
  iniciarSessao,
  pausar,
  retomar,
  finalizar,
}

class DeviceStatus {
  const DeviceStatus({
    required this.nome,
    required this.conectado,
    required this.bateria,
    this.simulador = false,
  });

  final String nome;
  final bool conectado;

  /// Bateria em % (0–100).
  final int bateria;
  final bool simulador;
}

abstract class DeviceTransport {
  Stream<ImpactEvent> get events;
  Future<void> send(
    DeviceCommand cmd, {
    int lances = 15,
    int intervaloSegundos = 3,
    double calibracao = 0.0,
  });
  Future<DeviceStatus> status();
  Future<void> disconnect();
}
