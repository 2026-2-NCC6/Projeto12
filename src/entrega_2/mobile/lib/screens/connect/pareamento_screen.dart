import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../router.dart';
import '../../state/device_state.dart';
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
  });

  final EstadoPareamento estadoInicial;

  @override
  State<PareamentoScreen> createState() => _PareamentoScreenState();
}

class _PareamentoScreenState extends State<PareamentoScreen> {
  /// No protótipo, "Conectando" avança sozinho para "Conectado" após 2,5 s.
  /// No app real: GATT conectado → Conectado; erro ou 10 s → Falha.
  static const _tempoConexao = Duration(milliseconds: 2500);

  late var _estado = widget.estadoInicial;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _entrar(_estado);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ir(EstadoPareamento estado) => setState(() => _entrar(estado));

  void _entrar(EstadoPareamento estado) {
    _timer?.cancel();
    _estado = estado;
    switch (estado) {
      case EstadoPareamento.conectando:
        _timer = Timer(_tempoConexao, () => _ir(EstadoPareamento.conectado));
      case EstadoPareamento.conectado:
        DeviceState.simulador.value = false;
      case EstadoPareamento.simulador:
        DeviceState.simulador.value = true;
      case EstadoPareamento.busca || EstadoPareamento.falha:
        break;
    }
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

  List<Widget> _busca() => [
    const _Radar(),
    Text(
      'Procurando o TOBIAS…',
      textAlign: TextAlign.center,
      style: AppText.titleL,
    ),
    Text(
      'Ligue o boneco e deixe-o por perto. O LED azul pisca enquanto ele anuncia.',
      textAlign: TextAlign.center,
      style: AppText.bodyM.c(AppColors.textSecondary),
    ),
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          'Dispositivos encontrados (2)',
          style: AppText.labelM.c(AppColors.textSecondary),
        ),
        const _DeviceItem(
          nome: Mock.deviceName,
          detalhe: 'ESP32 · sinal forte (−52 dBm)',
          badge: 'Sinal forte',
          tone: BadgeTone.accent,
          selected: true,
        ),
        // Sinal fraco: no protótipo, tocar leva à tela de falha.
        _DeviceItem(
          nome: 'TOBIAS-02',
          detalhe: 'ESP32 · sinal fraco (−81 dBm)',
          badge: 'Sinal fraco',
          tone: BadgeTone.warning,
          selected: false,
          onTap: () => _ir(EstadoPareamento.falha),
        ),
      ],
    ),
    const Spacer(),
    const NoteRow(
      icon: AppIcons.info,
      text:
          'No Android 12+, permita Bluetooth e Dispositivos próximos para encontrar o TOBIAS.',
    ),
    AppButton(
      'Conectar ao ${Mock.deviceName}',
      icon: AppIcons.bluetooth,
      onPressed: () => _ir(EstadoPareamento.conectando),
    ),
    AppButton.text(
      'Usar simulador (sem calibração)',
      onPressed: () => _ir(EstadoPareamento.simulador),
    ),
  ];

  // ------------------------------------------------------- 2.2 Conectando

  List<Widget> _conectando() => [
    const _Radar(compact: true),
    ..._titulo(
      'Conectando ao ${Mock.deviceName}…',
      'Mantenha o celular perto do boneco. Isso leva só alguns segundos.',
    ),
    const _Passos([
      (_Passo.feito, 'Dispositivo encontrado'),
      (_Passo.andamento, 'Abrindo a conexão Bluetooth…'),
      (_Passo.pendente, 'Verificando o boneco'),
    ]),
    const Spacer(),
    AppButton.outline('Cancelar', onPressed: () => _ir(EstadoPareamento.busca)),
  ];

  // -------------------------------------------------------- 2.3 Conectado

  List<Widget> _conectado() => [
    const _Radar(compact: true, icon: AppIcons.bluetoothConnected),
    ..._titulo(
      'Bluetooth conectado',
      'A conexão com o ${Mock.deviceName} foi realizada. Falta calibrar o sensor para medir seus lances.',
    ),
    const _DeviceItem(
      nome: Mock.deviceName,
      detalhe: 'ESP32 · Bluetooth conectado',
      badge: 'Conectado',
      tone: BadgeTone.accent,
      selected: true,
    ),
    const _Passos([
      (_Passo.feito, 'Dispositivo encontrado'),
      (_Passo.feito, 'Conexão Bluetooth realizada'),
      (
        _Passo.feito,
        'Boneco respondendo · bateria ${Mock.deviceBateriaAoConectar}%',
      ),
    ]),
    const Spacer(),
    AppButton(
      'Continuar para a calibração',
      icon: AppIcons.chevronRight,
      iconAfter: true,
      onPressed: _calibrar,
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
      'O ${Mock.deviceName} não respondeu. Siga os passos abaixo e tente de novo.',
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
