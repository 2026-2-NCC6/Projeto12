/// Interface que isola o BLE: as telas dependem dela e nunca falam com o
/// Bluetooth direto. `BleTransport` (flutter_blue_plus) entra depois.
library;

/// Impacto medido pelo ESP32 (o relógio e o pico vêm prontos do firmware).
class ImpactEvent {
  const ImpactEvent({required this.aPkG, this.tMs = 0});

  /// Pico de aceleração, em g.
  final double aPkG;

  /// Instante do impacto no relógio do ESP32, em ms.
  final int tMs;
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
  Future<void> send(DeviceCommand cmd);
  Future<DeviceStatus> status();
}
