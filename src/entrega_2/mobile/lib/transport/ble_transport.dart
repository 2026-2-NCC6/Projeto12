import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_transport.dart';

/// TOBIAS encontrado na busca BLE.
class TobiasEncontrado {
  const TobiasEncontrado({
    required this.device,
    required this.nome,
    this.rssi,
  });

  final BluetoothDevice device;
  final String nome;

  /// Intensidade do sinal em dBm. Nulo quando o aparelho já está conectado
  /// pelo sistema (não aparece no scan, então não há leitura de sinal).
  final int? rssi;

  /// Acima de −70 dBm a conexão costuma ser estável.
  bool get sinalForte => rssi == null || rssi! >= -70;
}

/// Motivos para a busca BLE não poder começar.
enum FalhaBusca {
  /// Aparelho (ou navegador) sem Bluetooth Low Energy.
  naoSuportado,

  /// Usuário negou Bluetooth / Dispositivos próximos.
  semPermissao,

  /// Qualquer outro erro do plugin.
  erro,
}

/// Implementação real de [DeviceTransport] usando Bluetooth Low Energy (BLE)
/// e o protocolo Nordic UART Service (NUS) para comunicação com o Tobias (ESP32).
class BleTransport implements DeviceTransport {
  BleTransport();

  // UUIDs do Nordic UART Service (NUS) definidos no firmware do Tobias
  static final Guid serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid rxUuid = Guid('6E400002-B5A3-F393-E0A9-E50E24DCCA9E'); // App -> ESP32 (Write)
  static final Guid txUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E'); // ESP32 -> App (Notify)

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rxChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<List<int>>? _txSubscription;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final _eventController = StreamController<ImpactEvent>.broadcast();
  final _estadoController = StreamController<StatusTobias>.broadcast();
  final StringBuffer _buffer = StringBuffer();

  bool _isConnected = false;
  String _deviceName = 'TOBIAS';
  final int _bateria = 85;

  Map<String, dynamic>? ultimoResumoTreino;

  @override
  Stream<ImpactEvent> get events => _eventController.stream;

  @override
  Stream<StatusTobias> get estados => _estadoController.stream;

  bool get isConnected => _isConnected;
  BluetoothDevice? get device => _device;

  /// Nome do TOBIAS conectado (ou do último usado).
  String get deviceName => _deviceName;

  /// Estado do Bluetooth do celular (ligado, desligado, sem permissão...).
  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  /// Emite `true` enquanto a busca BLE está rodando.
  Stream<bool> get buscando => FlutterBluePlus.isScanning;

  Future<bool> get suportado async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (_) {
      return false;
    }
  }

  /// Pede ao Android para ligar o Bluetooth (no iOS não há como).
  Future<void> ligarBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      developer.log('Não foi possível ligar o Bluetooth: $e', name: 'BleTransport');
    }
  }

  static bool _ehTobias(String nome) => nome.toUpperCase().contains('TOBIAS');

  /// Lista ao vivo dos TOBIAS por perto, do sinal mais forte para o mais fraco.
  ///
  /// Assine antes de chamar [iniciarBusca]. Filtra pelo nome ou pelo UUID do
  /// serviço, então funciona mesmo com firmware que não anuncia o UUID.
  Stream<List<TobiasEncontrado>> get encontrados =>
      FlutterBluePlus.onScanResults.map((results) {
        final lista = [
          for (final r in results)
            if (_ehTobias(r.advertisementData.advName) ||
                _ehTobias(r.device.platformName) ||
                r.advertisementData.serviceUuids.contains(serviceUuid))
              TobiasEncontrado(
                device: r.device,
                nome: _nomeDe(r.device, r.advertisementData.advName),
                rssi: r.rssi,
              ),
        ]..sort((a, b) => (b.rssi ?? 0).compareTo(a.rssi ?? 0));
        return lista;
      });

  /// TOBIAS já conectados pelo sistema: não anunciam, então o scan não os vê.
  Future<List<TobiasEncontrado>> jaConectados() async {
    try {
      final devices = await FlutterBluePlus.systemDevices([serviceUuid]);
      return [
        for (final d in devices)
          if (_ehTobias(d.platformName))
            TobiasEncontrado(device: d, nome: _nomeDe(d, '')),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _nomeDe(BluetoothDevice d, String advName) {
    if (advName.isNotEmpty) return advName;
    if (d.platformName.isNotEmpty) return d.platformName;
    return 'TOBIAS';
  }

  /// Inicia a busca BLE. Retorna `null` se começou, ou o motivo da falha.
  ///
  /// Sem filtro de serviço no scan: o firmware antigo não anunciava o UUID.
  /// No Android 12+ o plugin pede as permissões de Bluetooth aqui.
  Future<FalhaBusca?> iniciarBusca({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!await suportado) return FalhaBusca.naoSuportado;
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      return null;
    } catch (e) {
      developer.log('Erro ao iniciar busca BLE: $e', name: 'BleTransport', error: e);
      final msg = e.toString().toLowerCase();
      if (msg.contains('permission')) return FalhaBusca.semPermissao;
      return FalhaBusca.erro;
    }
  }

  Future<void> pararBusca() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  /// Conecta ao TOBIAS escolhido na busca e prepara os canais RX/TX.
  Future<bool> connect(
    TobiasEncontrado alvo, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      // Já conectado a este mesmo TOBIAS: nada a fazer
      if (_device?.remoteId == alvo.device.remoteId &&
          _isConnected &&
          _rxChar != null &&
          _txChar != null) {
        return true;
      }
      if (_device != null) await disconnect();

      // O scan atrapalha a conexão em alguns Androids
      await pararBusca();

      // 1. Conecta ao dispositivo
      final device = alvo.device;
      _device = device;
      _deviceName = alvo.nome;
      developer.log('Conectando ao dispositivo $_deviceName...', name: 'BleTransport');

      await device.connect(timeout: timeout, autoConnect: false);

      _connSub?.cancel();
      _connSub = device.connectionState.listen((state) {
        _isConnected = (state == BluetoothConnectionState.connected);
        if (!_isConnected) {
          _rxChar = null;
          _txChar = null;
        }
      });

      // 2. Descobre serviços e características RX/TX
      final services = await device.discoverServices();
      for (final s in services) {
        if (s.uuid == serviceUuid) {
          for (final c in s.characteristics) {
            if (c.uuid == rxUuid) {
              _rxChar = c;
            } else if (c.uuid == txUuid) {
              _txChar = c;
            }
          }
        }
      }

      if (_txChar == null || _rxChar == null) {
        developer.log('Características RX/TX não encontradas', name: 'BleTransport');
        await disconnect();
        return false;
      }

      // 3. Ativa notificações no canal TX (ESP32 -> App)
      await _txChar!.setNotifyValue(true);
      _txSubscription?.cancel();
      _txSubscription = _txChar!.onValueReceived.listen(_processarDadosRecebidos);

      _isConnected = true;
      developer.log('Conectado ao TOBIAS com sucesso!', name: 'BleTransport');
      return true;
    } catch (e, st) {
      developer.log('Erro ao conectar via BLE: $e', name: 'BleTransport', error: e, stackTrace: st);
      await disconnect();
      return false;
    }
  }

  /// Processa os bytes recebidos via notificação BLE
  void _processarDadosRecebidos(List<int> bytes) {
    if (bytes.isEmpty) return;
    final text = utf8.decode(bytes, allowMalformed: true);
    _buffer.write(text);

    final content = _buffer.toString();
    if (!content.contains('\n')) {
      // Firmware antigo não manda '\n': aceita o pacote se já for um JSON inteiro
      final semQuebra = content.trim();
      if (semQuebra.startsWith('{') && semQuebra.endsWith('}')) {
        try {
          jsonDecode(semQuebra);
          _buffer.clear();
          _interpretarJson(semQuebra);
        } catch (_) {}
      }
      return; // Aguarda o terminador de linha
    }

    final lines = content.split('\n');
    // Mantém a última linha incompleta no buffer
    _buffer.clear();
    _buffer.write(lines.last);

    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      _interpretarJson(line);
    }
  }

  /// Uma linha JSON do firmware, como se tivesse chegado pelo BLE.
  @visibleForTesting
  void interpretarLinha(String linha) => _interpretarJson(linha);

  /// Interpreta mensagens JSON do firmware Tobias
  void _interpretarJson(String jsonString) {
    try {
      final map = jsonDecode(jsonString);
      if (map is! Map<String, dynamic>) return;

      // Mensagem de status: nunca é lance. Status que o app não conhece
      // (CONECTADO, PONG, CANCELADO, CALIB_INICIADA...) só vai para o log.
      if (map.containsKey('status')) {
        final status = map['status'];
        if (status == 'TREINO_CONCLUIDO') {
          ultimoResumoTreino = map;
          developer.log('Treino concluído no Tobias: $map', name: 'BleTransport');
          _estadoController.add(StatusTobias.concluido);
        } else if (statusTobiasDe(status) case final estado?) {
          debugPrint('[BLE] Tobias confirmou: $status');
          _estadoController.add(estado);
        } else {
          developer.log('Status ignorado do Tobias: $status', name: 'BleTransport');
        }
        return;
      }

      // Lance de treino ou calibração
      if (map.containsKey('angulo') || map.containsKey('resultado')) {
        final angulo = (map['angulo'] as num?)?.toDouble() ??
            (map['forca_g'] as num?)?.toDouble() ??
            0.0;
        final tMs = (map['t_ms'] as num?)?.toInt() ?? 0;
        final resultado = map['resultado'] as String? ?? 'acerto';
        final classe = map['classe'] as String? ?? 'medio';
        final knockout = map['knockout'] as bool? ?? false;
        final bola = (map['bola'] as num?)?.toInt() ?? 0;
        final idLance = map['id_lance'] as String? ?? '';

        _eventController.add(
          ImpactEvent(
            aPkG: angulo,
            tMs: tMs,
            resultado: resultado,
            classe: classe,
            knockout: knockout,
            bola: bola,
            idLance: idLance,
          ),
        );
      }
    } catch (e) {
      developer.log('Falha ao decodificar JSON do Tobias: $jsonString', name: 'BleTransport', error: e);
    }
  }

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

    if (!_isConnected || _rxChar == null) {
      debugPrint('[BLE] não conectado, comando NÃO enviado: ${payload.trim()}');
      return;
    }

    try {
      final bytes = utf8.encode(payload);
      await _rxChar!.write(bytes, withoutResponse: false);
      // debugPrint (e não só developer.log) para aparecer no console do
      // `flutter run`: é como se confere o comando que foi ao Tobias.
      debugPrint('[BLE] comando enviado ao Tobias: ${payload.trim()}');
    } catch (e) {
      developer.log('Erro ao escrever no canal RX BLE: $e', name: 'BleTransport', error: e);
    }
  }

  @override
  Future<DeviceStatus> status() async {
    return DeviceStatus(
      nome: _deviceName,
      conectado: _isConnected,
      bateria: _bateria,
      simulador: false,
    );
  }

  @override
  Future<void> disconnect() async {
    try {
      await _txSubscription?.cancel();
      _txSubscription = null;
      await _connSub?.cancel();
      _connSub = null;
      if (_device != null) {
        await _device!.disconnect();
      }
    } catch (_) {}
    _device = null;
    _rxChar = null;
    _txChar = null;
    _isConnected = false;
    _buffer.clear();
  }

  void dispose() {
    disconnect();
    _eventController.close();
    _estadoController.close();
  }
}

