import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../router.dart';
import '../../state/device_state.dart';
import '../../transport/ble_transport.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// Estados da tela de conexão (todos na rota `/pareamento`).
enum EstadoPareamento {
  /// 2.1 Pareamento (14:289).
  busca,

  /// 2.2 Conectando (98:2384) — transitório.
  conectando,

  /// 2.3 Conectado (98:2464).
  conectado,

  /// 2.4 Falha (98:2544).
  falha,

  /// 2.5 Simulador (98:2624).
  simulador;

  static EstadoPareamento fromQuery(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => busca);
}

/// 2.1 a 2.5 — Pareamento e telas de feedback de conexão.
class PareamentoScreen extends StatefulWidget {
  const PareamentoScreen({
    super.key,
    this.estadoInicial = EstadoPareamento.busca,
    this.lerUsuario,
  });

  final EstadoPareamento estadoInicial;

  /// Nos testes: o usuário "guardado". Padrão: [AuthStore.lerUsuario].
  final Future<UsuarioApi?> Function()? lerUsuario;

  @override
  State<PareamentoScreen> createState() => _PareamentoScreenState();
}

class _PareamentoScreenState extends State<PareamentoScreen> {
  BleTransport get _ble => DeviceState.bleTransport;

  late var _estado = widget.estadoInicial;

  // Busca BLE (2.1)
  var _adapter = BluetoothAdapterState.unknown;
  var _buscando = false;
  FalhaBusca? _falhaBusca;
  List<TobiasEncontrado> _doScan = const [];
  List<TobiasEncontrado> _doSistema = const [];
  DeviceIdentifier? _selecionadoId;

  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<List<TobiasEncontrado>>? _encontradosSub;
  StreamSubscription<bool>? _buscandoSub;

  /// Quem está logado, para saber se já calibrou (`calibrado_em`).
  UsuarioApi? _usuario;

  /// Calibra uma vez só: com `calibrado_em` preenchido, conectar leva direto
  /// a treinar, e recalibrar fica no Perfil. Sem usuário guardado (login de
  /// uma versão anterior), calibra, como antes. NUNCA decida pelo valor da
  /// calibração: 0 é resultado legítimo de quem bate com mediana de 38° ou
  /// menos, e essa pessoa seria mandada para a calibração para sempre.
  bool get _precisaCalibrar => _usuario?.precisaCalibrar ?? true;

  @override
  void initState() {
    super.initState();
    (widget.lerUsuario ?? AuthStore.lerUsuario)().then((u) {
      if (mounted) setState(() => _usuario = u);
    });
    _encontradosSub = _ble.encontrados.listen((lista) {
      if (mounted) setState(() => _doScan = lista);
    });
    _buscandoSub = _ble.buscando.listen((b) {
      if (mounted) setState(() => _buscando = b);
    });
    _ble.suportado.then((ok) {
      if (!mounted) return;
      if (!ok) {
        setState(() => _falhaBusca = FalhaBusca.naoSuportado);
        return;
      }
      // Emite o estado atual logo ao assinar; a busca começa quando estiver ligado
      _adapterSub = _ble.adapterState.listen(_aoMudarAdapter);
    });
    _entrar(_estado);
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _encontradosSub?.cancel();
    _buscandoSub?.cancel();
    _ble.pararBusca();
    super.dispose();
  }

  void _aoMudarAdapter(BluetoothAdapterState s) {
    if (!mounted) return;
    setState(() => _adapter = s);
    if (s == BluetoothAdapterState.on && _estado == EstadoPareamento.busca) {
      _buscar();
    } else if (s == BluetoothAdapterState.off) {
      _ble.pararBusca();
    }
  }

  /// Já conectados pelo sistema primeiro, depois os do scan (sem repetir).
  List<TobiasEncontrado> get _encontrados {
    final ids = {for (final t in _doSistema) t.device.remoteId};
    return [
      ..._doSistema,
      for (final t in _doScan)
        if (!ids.contains(t.device.remoteId)) t,
    ];
  }

  /// Escolhido pelo usuário; se nenhum, o de sinal mais forte.
  TobiasEncontrado? get _selecionado {
    final lista = _encontrados;
    if (lista.isEmpty) return null;
    for (final t in lista) {
      if (t.device.remoteId == _selecionadoId) return t;
    }
    return lista.first;
  }

  Future<void> _buscar() async {
    if (_buscando || _adapter != BluetoothAdapterState.on) return;
    setState(() {
      _falhaBusca = null;
      _doScan = const [];
    });
    final sistema = await _ble.jaConectados();
    final falha = await _ble.iniciarBusca();
    if (!mounted) return;
    setState(() {
      _doSistema = sistema;
      _falhaBusca = falha;
    });
  }

  void _ir(EstadoPareamento estado) => setState(() => _entrar(estado));

  void _entrar(EstadoPareamento estado) {
    _estado = estado;
    switch (estado) {
      case EstadoPareamento.busca:
        // Ao voltar para a busca, procura de novo (na abertura, quem dispara é o adapter)
        if (_adapter == BluetoothAdapterState.on) _buscar();
      case EstadoPareamento.conectando:
        _conectarBle();
      case EstadoPareamento.conectado:
        DeviceState.simulador.value = false;
      case EstadoPareamento.simulador:
        _ble.pararBusca();
        DeviceState.simulador.value = true;
      case EstadoPareamento.falha:
        break;
    }
  }

  Future<void> _conectarBle() async {
    final alvo = _selecionado;
    if (alvo == null) {
      _ir(EstadoPareamento.falha);
      return;
    }
    final ok = await _ble.connect(alvo, timeout: const Duration(seconds: 10));
    if (!mounted || _estado != EstadoPareamento.conectando) return;
    _ir(ok ? EstadoPareamento.conectado : EstadoPareamento.falha);
  }

  Future<void> _calibrar() async {
    await context.push(Routes.calibracao);
    // Voltar da Calibração cai no Pareamento (busca).
    if (mounted) _ir(EstadoPareamento.busca);
  }

  @override
  Widget build(BuildContext context) {
    final busca = _estado == EstadoPareamento.busca;
    return PopScope(
      canPop: busca,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _ir(EstadoPareamento.busca);
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey(_estado),
          child: StackedScreen(
            title: 'Conectar ao TOBIAS',
            onBack: busca
                ? () => goBack(context, Routes.login)
                : () => _ir(EstadoPareamento.busca),
            crossAxisAlignment: CrossAxisAlignment.center,
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            gap: busca ? 12 : 14,
            children: switch (_estado) {
              EstadoPareamento.busca => _busca(),
              EstadoPareamento.conectando => _conectando(),
              EstadoPareamento.conectado => _conectado(),
              EstadoPareamento.falha => _falha(),
              EstadoPareamento.simulador => _simulador(),
            },
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 2.1 Busca

  List<Widget> _busca() {
    final lista = _encontrados;
    final selecionado = _selecionado;

    // Problemas que impedem a busca: título, explicação e ação para resolver
    final (String, String, String, VoidCallback)? problema =
        switch ((_falhaBusca, _adapter)) {
          (FalhaBusca.naoSuportado, _) || (_, BluetoothAdapterState.unavailable) => (
            'Bluetooth indisponível',
            'Este aparelho não tem Bluetooth Low Energy. Use o simulador para testar o app.',
            '',
            () {},
          ),
          (FalhaBusca.semPermissao, _) ||
          (_, BluetoothAdapterState.unauthorized) => (
            'Permissão necessária',
            'Permita Bluetooth e Dispositivos próximos nas configurações do app para encontrar o TOBIAS.',
            'Tentar novamente',
            _buscar,
          ),
          (_, BluetoothAdapterState.off || BluetoothAdapterState.turningOff) => (
            'Bluetooth desligado',
            'Ligue o Bluetooth do celular para encontrar o TOBIAS.',
            'Ligar Bluetooth',
            _ble.ligarBluetooth,
          ),
          (FalhaBusca.erro, _) => (
            'Não foi possível buscar',
            'Algo deu errado ao procurar o TOBIAS. Tente de novo.',
            'Tentar novamente',
            _buscar,
          ),
          _ => null,
        };

    final (titulo, subtitulo) = switch (problema) {
      (final t, final s, _, _) => (t, s),
      null when lista.isNotEmpty => (
        _buscando ? 'Procurando o TOBIAS…' : 'Escolha o seu TOBIAS',
        'Toque no boneco que deseja usar e conecte.',
      ),
      null when _buscando || _adapter == BluetoothAdapterState.unknown => (
        'Procurando o TOBIAS…',
        'Ligue o boneco e deixe-o por perto. O LED azul pisca enquanto ele anuncia.',
      ),
      null => (
        'Nenhum TOBIAS encontrado',
        'Confirme que o boneco está ligado, com o LED azul piscando, e perto do celular.',
      ),
    };

    return [
      _Radar(animate: problema == null),
      Text(titulo, textAlign: TextAlign.center, style: AppText.titleL),
      Text(
        subtitulo,
        textAlign: TextAlign.center,
        style: AppText.bodyM.c(AppColors.textSecondary),
      ),
      if (problema == null && lista.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Text(
              'Dispositivos encontrados (${lista.length})',
              style: AppText.labelM.c(AppColors.textSecondary),
            ),
            for (final t in lista)
              _DeviceItem(
                nome: t.nome,
                detalhe: switch (t.rssi) {
                  null => 'ESP32 · já conectado ao celular',
                  final rssi when t.sinalForte =>
                    'ESP32 · sinal forte (${_dbm(rssi)})',
                  final rssi => 'ESP32 · sinal fraco (${_dbm(rssi)})',
                },
                badge: t.sinalForte ? 'Sinal forte' : 'Sinal fraco',
                tone: t.sinalForte ? BadgeTone.accent : BadgeTone.warning,
                selected: t.device.remoteId == selecionado?.device.remoteId,
                onTap: () =>
                    setState(() => _selecionadoId = t.device.remoteId),
              ),
          ],
        ),
      const Spacer(),
      const NoteRow(
        icon: AppIcons.info,
        text:
            'No Android 12+, permita Bluetooth e Dispositivos próximos para encontrar o TOBIAS.',
      ),
      if (problema != null && problema.$3.isNotEmpty)
        AppButton(problema.$3, icon: AppIcons.bluetooth, onPressed: problema.$4)
      else if (problema == null && selecionado != null)
        AppButton(
          'Conectar ao ${selecionado.nome}',
          icon: AppIcons.bluetooth,
          onPressed: () => _ir(EstadoPareamento.conectando),
        )
      else if (problema == null && !_buscando)
        AppButton(
          'Procurar novamente',
          icon: AppIcons.refreshCw,
          onPressed: _buscar,
        ),
      if (problema == null && selecionado != null && !_buscando)
        AppButton.text('Procurar novamente', onPressed: _buscar),
      AppButton.text(
        'Usar simulador (sem calibração)',
        onPressed: () => _ir(EstadoPareamento.simulador),
      ),
    ];
  }

  /// −52 dBm com sinal de menos tipográfico, como no protótipo.
  static String _dbm(int rssi) => '${rssi.toString().replaceFirst('-', '−')} dBm';

  // ------------------------------------------------------- 2.2 Conectando

  List<Widget> _conectando() => [
    const _Radar(compact: true),
    ..._titulo(
      'Conectando ao ${_selecionado?.nome ?? 'TOBIAS'}…',
      'Mantenha o celular perto do boneco. Isso leva só alguns segundos.',
    ),
    const _Passos([
      (_Passo.feito, 'Dispositivo encontrado'),
      (_Passo.andamento, 'Abrindo a conexão Bluetooth…'),
      (_Passo.pendente, 'Verificando o boneco'),
    ]),
    const Spacer(),
    AppButton.outline('Cancelar', onPressed: () {
      DeviceState.bleTransport.disconnect();
      _ir(EstadoPareamento.busca);
    }),
  ];

  // -------------------------------------------------------- 2.3 Conectado

  List<Widget> _conectado() => [
    const _Radar(compact: true, icon: AppIcons.bluetoothConnected),
    ..._titulo(
      'Bluetooth conectado',
      _precisaCalibrar
          ? 'A conexão com o ${_ble.deviceName} foi realizada. Falta calibrar o sensor para medir seus lances.'
          : 'A conexão com o ${_ble.deviceName} foi realizada. Você já calibrou: é só treinar. Para recalibrar, use o Perfil.',
    ),
    _DeviceItem(
      nome: _ble.deviceName,
      detalhe: 'ESP32 · Bluetooth conectado',
      badge: 'Conectado',
      tone: BadgeTone.accent,
      selected: true,
    ),
    // O firmware ainda não informa a bateria, então ela não aparece aqui
    const _Passos([
      (_Passo.feito, 'Dispositivo encontrado'),
      (_Passo.feito, 'Conexão Bluetooth realizada'),
      (_Passo.feito, 'Canal de comunicação com o boneco pronto'),
    ]),
    const Spacer(),
    if (_precisaCalibrar)
      AppButton(
        'Continuar para a calibração',
        icon: AppIcons.chevronRight,
        iconAfter: true,
        onPressed: _calibrar,
      )
    else
      // O mesmo destino de quem acaba de calibrar (CalibracaoScreen).
      AppButton(
        'Começar a treinar',
        icon: AppIcons.chevronRight,
        iconAfter: true,
        onPressed: () => context.go(Routes.treinos),
      ),
  ];

  // ------------------------------------------------------------ 2.4 Falha

  List<Widget> _falha() => [
    const _Radar(
      compact: true,
      animate: false,
      rings: (
        AppColors.bgSurfaceMuted,
        AppColors.bgErrorSoft,
        AppColors.bgSurface,
      ),
      core: AppColors.bgError,
      icon: AppIcons.x,
    ),
    ..._titulo(
      'Não foi possível conectar ao boneco',
      'O ${_selecionado?.nome ?? 'TOBIAS'} não respondeu. Siga os passos abaixo e tente de novo.',
    ),
    const _ComoConectar(),
    const Spacer(),
    AppButton(
      'Tentar novamente',
      icon: AppIcons.refreshCw,
      onPressed: () => _ir(EstadoPareamento.conectando),
    ),
    AppButton.text(
      'Usar simulador (sem calibração)',
      onPressed: () => _ir(EstadoPareamento.simulador),
    ),
  ];

  // -------------------------------------------------------- 2.5 Simulador

  /// Usa o `MockTransport` e pula a calibração (a_ref = valor padrão).
  List<Widget> _simulador() => [
    const _Radar(compact: true, icon: AppIcons.activity),
    ..._titulo(
      'Simulador pronto',
      'Conexão simulada: sem Bluetooth e sem calibração. Os lances são gerados no celular.',
    ),
    const _Passos([
      (_Passo.feito, 'Simulador carregado no celular'),
      (_Passo.feito, 'Lances de exemplo prontos'),
      (_Passo.info, 'Sessões simuladas não contam para o ranking'),
    ]),
    const Spacer(),
    AppButton(
      'Começar a treinar',
      icon: AppIcons.play,
      onPressed: () => context.go(Routes.sessao),
    ),
    AppButton.text(
      'Conectar ao TOBIAS',
      onPressed: () => _ir(EstadoPareamento.busca),
    ),
  ];

  List<Widget> _titulo(String titulo, String subtitulo) => [
    Text(titulo, textAlign: TextAlign.center, style: AppText.titleL),
    Text(
      subtitulo,
      textAlign: TextAlign.center,
      style: AppText.bodyM.c(AppColors.textSecondary),
    ),
  ];
}

/// Radar 240×240 com ondas animadas. Nas telas de feedback encolhe para
/// 168×168 (70%).
class _Radar extends StatefulWidget {
  const _Radar({
    this.compact = false,
    this.animate = true,
    this.rings = (
      AppColors.bgBrandSoft,
      AppColors.bgAccentSoft,
      AppColors.bgAccent,
    ),
    this.core = AppColors.bgBrand,
    this.icon = AppIcons.bluetooth,
  });

  final bool compact;
  final bool animate;

  /// Cores dos círculos de 240, 176 e 112.
  final (Color, Color, Color) rings;
  final Color core;
  final IconData icon;

  @override
  State<_Radar> createState() => _RadarState();
}

class _RadarState extends State<_Radar> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _anim.repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Widget _circle(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );

  @override
  Widget build(BuildContext context) {
    final (r240, r176, r112) = widget.rings;
    final radar = SizedBox.square(
      dimension: 240,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          final t = Curves.easeInOut.transform(_anim.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 0.94 + 0.06 * t,
                child: _circle(240, r240),
              ),
              Transform.scale(
                scale: 0.96 + 0.04 * t,
                child: _circle(176, r176),
              ),
              _circle(112, r112),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: widget.core,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 32,
                  color: AppColors.iconOnBrand,
                ),
              ),
            ],
          );
        },
      ),
    );
    if (!widget.compact) return radar;
    return SizedBox.square(dimension: 168, child: FittedBox(child: radar));
  }
}

class _DeviceItem extends StatelessWidget {
  const _DeviceItem({
    required this.nome,
    required this.detalhe,
    required this.badge,
    required this.tone,
    required this.selected,
    this.onTap,
  });

  final String nome;
  final String detalhe;
  final String badge;
  final BadgeTone tone;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      radius: AppRadius.r16,
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      color: selected ? AppColors.bgBrandSoft : AppColors.bgSurface,
      shadow: selected ? null : AppShadows.card,
      border: selected
          ? Border.all(color: AppColors.borderBrand, width: 2)
          : null,
      child: Row(
        spacing: 12,
        children: [
          IconBadge(
            icon: AppIcons.radio,
            circle: true,
            background: selected ? AppColors.bgBrand : AppColors.bgSurfaceMuted,
            color: selected ? AppColors.iconOnBrand : AppColors.iconDefault,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nome, style: AppText.titleM),
                Text(detalhe, style: AppText.bodyS.c(AppColors.textSecondary)),
              ],
            ),
          ),
          AppBadge(badge, tone: tone),
        ],
      ),
    );
  }
}

enum _Passo { feito, andamento, pendente, info }

/// Cartão de passos: ícone 20 + texto `body/m` por linha.
class _Passos extends StatelessWidget {
  const _Passos(this.itens);

  final List<(_Passo, String)> itens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.r16),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 14,
        children: [
          for (final (passo, texto) in itens)
            Row(
              spacing: 12,
              children: [
                switch (passo) {
                  _Passo.feito => const Icon(
                    AppIcons.checkCircle,
                    size: 20,
                    color: AppColors.iconBrand,
                  ),
                  _Passo.andamento => const Spinning(
                    child: Icon(
                      AppIcons.refreshCw,
                      size: 20,
                      color: AppColors.iconAccent,
                    ),
                  ),
                  _Passo.pendente => const Icon(
                    AppIcons.minus,
                    size: 20,
                    color: AppColors.iconDefault,
                  ),
                  _Passo.info => const Icon(
                    AppIcons.info,
                    size: 20,
                    color: AppColors.iconDefault,
                  ),
                },
                Expanded(
                  child: Text(
                    texto,
                    style: AppText.bodyM.c(
                      passo == _Passo.feito || passo == _Passo.andamento
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Cartão "Como conectar" da tela de falha: 4 passos numerados.
class _ComoConectar extends StatelessWidget {
  const _ComoConectar();

  static const _passos = [
    'Confirme que o boneco está ligado e com o LED azul piscando.',
    'Fique a menos de 2 metros do boneco.',
    'Ative o Bluetooth e a permissão Dispositivos próximos.',
    'Se não resolver, desligue e ligue o boneco e tente de novo.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgErrorSoft,
        borderRadius: BorderRadius.circular(AppRadius.r16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text('Como conectar', style: AppText.titleM),
          for (final (i, texto) in _passos.indexed)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.bgSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: AppText.labelM.c(AppColors.textError),
                  ),
                ),
                Expanded(child: Text(texto, style: AppText.bodyM)),
              ],
            ),
        ],
      ),
    );
  }
}
