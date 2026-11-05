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

/// Texto do comando que o firmware recebe pela característica RX.
///
/// O intervalo vai em milissegundos: o firmware trata valores >= 100 como
/// ms e menores como segundos (`intervalo = val < 100 ? val * 1000 : val`).
/// Mandar ms preserva o `intervalo_ms` exato do treino (2500 ms não vira
/// "3"); a API garante intervalo_ms >= 500. A calibração vai com 1 casa,
/// a mesma precisão que a API aceita para a dificuldade.
String montarComando(
  DeviceCommand cmd, {
  int lances = 15,
  int intervaloMs = 3000,
  double calibracao = 0.0,
}) {
  final calib = calibracao > 0.0 ? calibracao.toStringAsFixed(1) : '0.0';
  return switch (cmd) {
    DeviceCommand.iniciarCalibracao => 'CALIBRAR:5\n',
    DeviceCommand.iniciarSessao ||
    DeviceCommand.retomar => 'TREINO:$lances:$intervaloMs:$calib\n',
    DeviceCommand.pausar || DeviceCommand.finalizar => 'STOP\n',
  };
}

abstract class DeviceTransport {
  Stream<ImpactEvent> get events;
  Future<void> send(
    DeviceCommand cmd, {
    int lances = 15,
    int intervaloMs = 3000,
    double calibracao = 0.0,
  });
  Future<DeviceStatus> status();
  Future<void> disconnect();
}
