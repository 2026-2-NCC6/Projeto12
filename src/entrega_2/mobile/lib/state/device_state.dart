import 'package:flutter/foundation.dart';

import '../data/mock_data.dart';
import '../transport/device_transport.dart';
import '../transport/mock_transport.dart';

/// Estado do TOBIAS no app (somente em memória).
abstract final class DeviceState {
  /// Transporte em uso. Sem BLE real por enquanto: sempre o simulador.
  static DeviceTransport transport = MockTransport();

  /// `a_ref` = mediana dos picos das 5 batidas de calibração, em g.
  static final refG = ValueNotifier<double>(Mock.deviceRefG);

  /// Conexão simulada (2.5): a sessão nasce com a flag de simulador e
  /// nunca conta para o ranking.
  static final simulador = ValueNotifier<bool>(false);
}
