import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fila_sessoes.dart';
import '../../data/format.dart';
import '../../data/sincronizador.dart';
import '../../router.dart';
import '../../state/device_state.dart';
import '../../state/gravador_sessao.dart';
import '../../state/sessao_ativa.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/charts.dart';
import '../../widgets/layout.dart';

/// 4.2 Sessão · Em andamento (21:741). Não mostra pontuação — só tempo e
/// animação. Sem botão voltar: sai-se por "Finalizar sessão".
class EmAndamentoScreen extends StatefulWidget {
  const EmAndamentoScreen({super.key, required this.sessao, this.fila});

  /// Congelada na seleção: os parâmetros não são relidos do treino.
  final SessaoAtiva sessao;

  /// Fila onde a sessão é gravada; nos testes, uma isolada.
  final FilaSessoes? fila;

  @override
  State<EmAndamentoScreen> createState() => _EmAndamentoScreenState();
}

class _EmAndamentoScreenState extends State<EmAndamentoScreen>
    with TickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  Timer? _timer;
  var _segundos = 0;
  var _pausado = false;

  /// Grava a sessão na fila local e fala com o Tobias (etapa 3).
  late final _gravador = GravadorSessao(
    sessao: widget.sessao,
    fila: widget.fila ?? FilaSessoes.doApp,
    transport: DeviceState.transport,
  );
  late final Future<void> _iniciada = _gravador.iniciar();

  @override
  void initState() {
    super.initState();
    _iniciarTimer();
    // A sessão é gravada na fila antes de o TREINO: sair (ver GravadorSessao).
    _iniciada.catchError((Object e) {
      debugPrint('[Sessão] falha ao iniciar: $e');
    });
  }

  void _iniciarTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _segundos++);
    });
  }

  void _alternarPausa() {
    setState(() => _pausado = !_pausado);
    if (_pausado) {
      _timer?.cancel();
      _pulse.stop();
      _spin.stop();
      _gravador.pausar();
    } else {
      _iniciarTimer();
      _pulse.repeat(reverse: true);
      _spin.repeat();
      // Pede só os lances que faltam: o firmware recomeça do zero.
      _gravador.retomar();
    }
  }

  Future<void> _finalizar() async {
    await _gravador.encerrar();
    // Gatilho de envio: fim da sessão. Não bloqueia a tela.
    Sincronizador.doApp.disparar();
    if (!mounted) return;
    context.pushReplacement(
      Uri(
        path: Routes.sessaoResumo,
        queryParameters: {
          'treino': widget.sessao.titulo,
          'sessao': _gravador.uuidSessao,
        },
      ).toString(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    _spin.dispose();
    // Saída sem "Finalizar" (ex.: o sistema fechou a tela): para o Tobias e
    // fecha a sessão. Idempotente depois de _finalizar.
    unawaited(_gravador.encerrar());
    super.dispose();
  }

  String get _tempo =>
      '${twoDigits(_segundos ~/ 60)}:${twoDigits(_segundos % 60)}';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: StatusBarStyle(
        light: true,
        child: Scaffold(
          backgroundColor: AppColors.bgBrandStrong,
          body: SafeArea(
            child: ScrollFill(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 16,
                children: [
                  Row(
                    spacing: 12,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.sessao.titulo,
                              style: AppText.titleL.c(AppColors.textOnBrand),
                            ),
                            Text(
                              '${widget.sessao.lances} lances · '
                              '${fmtSegundos(widget.sessao.intervaloMs)} entre eles',
                              style: AppText.bodyS.c(
                                AppColors.textOnBrandMuted,
                              ),
                            ),
                            Text(
                              'Sessão em andamento',
                              style: AppText.bodyM.c(
                                AppColors.textOnBrandMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.bgBrand,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          spacing: 6,
                          children: [
                            FadeTransition(
                              opacity: Tween(
                                begin: 1.0,
                                end: 0.35,
                              ).animate(_pulse),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.bgAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            Text(
                              'Gravando',
                              style: AppText.labelL.c(AppColors.textOnBrand),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Center(child: _cronometro()),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bgBrand,
                      borderRadius: BorderRadius.circular(AppRadius.r20),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 12,
                      children: [
                        const Icon(
                          AppIcons.bluetoothConnected,
                          size: 20,
                          color: AppColors.iconOnBrand,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: 2,
                            children: [
                              Text(
                                'TOBIAS conectado',
                                style: AppText.titleM.c(AppColors.textOnBrand),
                              ),
                              Text(
                                'Os lances são registrados no boneco. A pontuação aparece só depois que você finalizar a sessão.',
                                style: AppText.bodyS.c(
                                  AppColors.textOnBrandMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  _BotaoPausar(pausado: _pausado, onTap: _alternarPausa),
                  AppButton.danger(
                    'Finalizar sessão',
                    icon: AppIcons.stop,
                    onPressed: _finalizar,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cronometro() {
    Widget circle(double size, Color color) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return SizedBox.square(
      dimension: 280,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_pulse.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 0.94 + 0.06 * t,
                child: Opacity(
                  opacity: 0.6 + 0.4 * (1 - t),
                  child: circle(280, AppColors.bgBrand.withValues(alpha: 0.3)),
                ),
              ),
              Transform.scale(
                scale: 0.97 + 0.03 * t,
                child: circle(244, AppColors.bgBrand.withValues(alpha: 0.6)),
              ),
              child!,
            ],
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _spin,
              child: CustomPaint(
                size: const Size.square(228),
                painter: ArcPainter(
                  color: AppColors.bgAccent,
                  sweep: 153 * math.pi / 180,
                ),
              ),
            ),
            Container(
              width: 196,
              height: 196,
              decoration: const BoxDecoration(
                color: AppColors.bgBrand,
                shape: BoxShape.circle,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _tempo,
                    style: AppText.displayScore.c(AppColors.textOnBrand),
                  ),
                  Text(
                    'tempo de sessão',
                    style: AppText.labelM.c(AppColors.textOnBrandMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão transparente de 56 com borda 2 `text/on-brand-muted`.
class _BotaoPausar extends StatelessWidget {
  const _BotaoPausar({required this.pausado, required this.onTap});

  final bool pausado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r16),
          side: const BorderSide(color: AppColors.textOnBrandMuted, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              Icon(
                pausado ? AppIcons.play : AppIcons.pause,
                size: 20,
                color: AppColors.iconOnBrand,
              ),
              Text(
                pausado ? 'Continuar' : 'Pausar',
                style: AppText.button.c(AppColors.textOnBrand),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
