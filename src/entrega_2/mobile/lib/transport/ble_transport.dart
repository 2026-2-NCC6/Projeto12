import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'device_transport.dart';

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
  final StringBuffer _buffer = StringBuffer();

  bool _isConnected = false;
  String _deviceName = 'TOBIAS';
  int _bateria = 85;

  Map<String, dynamic>? ultimoResumoTreino;

  @override
  Stream<ImpactEvent> get events => _eventController.stream;

  bool get isConnected => _isConnected;
  BluetoothDevice? get device => _device;

  /// Procura e conecta ao dispositivo BLE Tobias.
  Future<bool> connect({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      // 1. Garante que o adaptador Bluetooth está disponível
      if (await FlutterBluePlus.isSupported == false) {
        developer.log('BLE não suportado neste aparelho', name: 'BleTransport');
        return false;
      }

      // Se já estiver conectado ao Tobias, descobre os serviços e retorna sucesso
      if (_device != null && _isConnected && _rxChar != null && _txChar != null) {
        return true;
      }

      // 2. Inicia o scan pelo dispositivo nomeado 'TOBIAS' ou pelo Service UUID
      developer.log('Iniciando busca BLE pelo TOBIAS...', name: 'BleTransport');
      
      BluetoothDevice? alvo;

      // Primeiro verifica dispositivos já pareados/conectados pelo sistema
      final connectedSystemDevices = await FlutterBluePlus.systemDevices([serviceUuid]);
      for (final d in connectedSystemDevices) {
        if (d.platformName.toUpperCase().contains('TOBIAS')) {
          alvo = d;
          break;
        }
      }

      if (alvo == null) {
        await FlutterBluePlus.startScan(
          timeout: timeout,
          withServices: [serviceUuid],
        );

        await for (final results in FlutterBluePlus.scanResults) {
          for (final r in results) {
            final name = r.device.platformName.toUpperCase();
            final advName = r.advertisementData.advName.toUpperCase();
            if (name.contains('TOBIAS') || advName.contains('TOBIAS')) {
              alvo = r.device;
              break;
            }
          }
          if (alvo != null) break;
        }

        await FlutterBluePlus.stopScan();
      }

      if (alvo == null) {
        developer.log('TOBIAS não encontrado no scan BLE', name: 'BleTransport');
        return false;
      }

      // 3. Conecta ao dispositivo
      _device = alvo;
      _deviceName = alvo.platformName.isNotEmpty ? alvo.platformName : 'TOBIAS';
      developer.log('Conectando ao dispositivo $_deviceName...', name: 'BleTransport');

      await alvo.connect(timeout: timeout, autoConnect: false);

      _connSub?.cancel();
      _connSub = alvo.connectionState.listen((state) {
        _isConnected = (state == BluetoothConnectionState.connected);
        if (!_isConnected) {
          _rxChar = null;
          _txChar = null;
        }
      });

      // 4. Descobre serviços e características RX/TX
      final services = await alvo.discoverServices();
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

      if (_txChar == null) {
        developer.log('Característica TX não encontrada', name: 'BleTransport');
        return false;
      }

      // 5. Ativa notificações no canal TX (ESP32 -> App)
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

  /// Interpreta mensagens JSON do firmware Tobias
  void _interpretarJson(String jsonString) {
    try {
      final map = jsonDecode(jsonString);
      if (map is! Map<String, dynamic>) return;

      // Resumo final de treino concluído
      if (map['status'] == 'TREINO_CONCLUIDO') {
        ultimoResumoTreino = map;
        developer.log('Treino concluído no Tobias: $map', name: 'BleTransport');
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
    int intervaloSegundos = 3,
    double calibracao = 0.0,
  }) async {
    if (!_isConnected || _rxChar == null) {
      developer.log('Não é possível enviar comando: BLE não conectado', name: 'BleTransport');
      return;
    }

    final calibStr = (calibracao > 0.0) ? calibracao.toStringAsFixed(1) : '0.0';

    final String payload;
    switch (cmd) {
      case DeviceCommand.iniciarCalibracao:
        payload = 'CALIBRAR:5\n';
      case DeviceCommand.iniciarSessao:
        payload = 'TREINO:$lances:$intervaloSegundos:$calibStr\n';
      case DeviceCommand.pausar:
        payload = 'STOP\n';
      case DeviceCommand.retomar:
        payload = 'TREINO:$lances:$intervaloSegundos:$calibStr\n';
      case DeviceCommand.finalizar:
        payload = 'STOP\n';
    }

    try {
      final bytes = utf8.encode(payload);
      await _rxChar!.write(bytes, withoutResponse: false);
      developer.log('Comando enviado para o Tobias: $payload', name: 'BleTransport');
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
  }
}

