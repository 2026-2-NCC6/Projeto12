import 'dart:async';

import '../data/mock_data.dart';
import 'device_transport.dart';

/// Simulador autorizado pelo edital: gera impactos sintéticos no celular.
/// No protótipo também alimenta a calibração (1,5 s até a 1ª batida e 1,2 s
/// entre as seguintes, como no Smart Animate do Figma).
class MockTransport implements DeviceTransport {
  MockTransport({
    this.primeira = const Duration(milliseconds: 1500),
    this.seguintes = const Duration(milliseconds: 1200),
    this.picos = Mock.calibracaoBatidas,
  });

  final Duration primeira;
  final Duration seguintes;

  /// Picos enviados em sequência (repetem quando acabam).
  final List<double> picos;

  /// Cada escuta recebe a sequência desde o começo. Cancelar a escuta para o
  /// timer, sem deixar nada pendente.
  @override
  Stream<ImpactEvent> get events {
    Timer? timer;
    var n = 0;
    late final StreamController<ImpactEvent> controller;
    void agendar() {
      timer = Timer(n == 0 ? primeira : seguintes, () {
        controller.add(
          ImpactEvent(
            aPkG: picos[n % picos.length],
            tMs: n * seguintes.inMilliseconds,
          ),
        );
        n++;
        agendar();
      });
    }

    controller = StreamController<ImpactEvent>(
      onListen: agendar,
      onPause: () => timer?.cancel(),
      onResume: agendar,
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> send(DeviceCommand cmd) async {}

  @override
  Future<DeviceStatus> status() async => const DeviceStatus(
    nome: Mock.deviceName,
    conectado: true,
    bateria: Mock.deviceBateria,
    simulador: true,
  );
}
