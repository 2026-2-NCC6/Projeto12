import 'dart:async';

import 'package:flutter/foundation.dart';

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

  final _estados = StreamController<StatusTobias>.broadcast();

  /// Como o firmware: pausado, nenhuma batida é registrada.
  var _pausado = false;

  @override
  Stream<StatusTobias> get estados => _estados.stream;

  /// Cada escuta recebe a sequência desde o começo. Cancelar a escuta para o
  /// timer, sem deixar nada pendente.
  @override
  Stream<ImpactEvent> get events {
    Timer? timer;
    var n = 0;
    late final StreamController<ImpactEvent> controller;
    void agendar() {
      timer = Timer(n == 0 ? primeira : seguintes, () {
        if (_pausado) return agendar();
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

  /// Não fala com hardware, mas registra o comando que o BLE mandaria:
  /// dá para conferir os parâmetros da sessão também no simulador.
  @override
  Future<void> send(
    DeviceCommand cmd, {
    int lances = 15,
    int intervaloMs = 3000,
    double calibracao = 0.0,
  }) async {
    final payload = montarComando(
      cmd,
      lances: lances,
      intervaloMs: intervaloMs,
      calibracao: calibracao,
    );
    debugPrint('[Simulador] comando (não enviado): ${payload.trim()}');
    // Confirma como o firmware confirmaria; pausar só vale com sessão rodando.
    switch (cmd) {
      case DeviceCommand.pausar when !_pausado:
        _pausado = true;
        _estados.add(StatusTobias.pausado);
      case DeviceCommand.retomar when _pausado:
        _pausado = false;
        _estados.add(StatusTobias.retomado);
      case DeviceCommand.iniciarSessao ||
          DeviceCommand.iniciarCalibracao ||
          DeviceCommand.finalizar:
        _pausado = false;
      default:
        break;
    }
  }

  @override
  Future<DeviceStatus> status() async => const DeviceStatus(
    nome: Mock.deviceName,
    conectado: true,
    bateria: Mock.deviceBateria,
    simulador: true,
  );

  @override
  Future<void> disconnect() async {}
}
