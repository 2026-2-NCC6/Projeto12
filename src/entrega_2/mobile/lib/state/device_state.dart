import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../transport/ble_transport.dart';
import '../transport/device_transport.dart';
import '../transport/mock_transport.dart';

/// Estado do TOBIAS no app (somente em memória).
abstract final class DeviceState {
  static final MockTransport mockTransport = MockTransport();
  static final BleTransport bleTransport = BleTransport();

  /// Conexão simulada (2.5): a sessão nasce com a flag de simulador e
  /// nunca conta para o ranking.
  static final simulador = ValueNotifier<bool>(false);

  /// Transporte ativo: se em modo simulador, usa mock; se conectado, usa BLE real.
  static DeviceTransport get transport =>
      simulador.value ? mockTransport : bleTransport;

  static set transport(DeviceTransport t) {
    simulador.value = (t is MockTransport);
  }

  /// `a_ref` = mediana dos picos das 5 batidas de calibração, em GRAUS de
  /// inclinação (o firmware mede ângulo, não g). Só em memória.
  static final refAngulo = ValueNotifier<double>(Mock.deviceRefAngulo);

  /// Nível de calibração / acréscimo de dificuldade em graus (enviado ao ESP32 a cada treino).
  /// 0.0 = Padrão fácil (jogador normal/fraco).
  /// > 0.0 = Dificultador para jogadores fortes.
  static final calibracao = ValueNotifier<double>(0.0);
}
