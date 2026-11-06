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
import '../../transport/device_transport.dart';
import '../../widgets/buttons.dart';
import '../../widgets/charts.dart';
import '../../widgets/layout.dart';

/// 4.2 Sessão · Em andamento (21:741). Não mostra pontuação — só tempo e
/// animação. Sem botão voltar: sai-se por "Finalizar sessão".
class EmAndamentoScreen extends StatefulWidget {
  const EmAndamentoScreen({
    super.key,
    required this.sessao,
    this.fila,
    this.transport,
  });

  /// Congelada na seleção: os parâmetros não são relidos do treino.
  final SessaoAtiva sessao;

  /// Fila onde a sessão é gravada; nos testes, uma isolada.
  final FilaSessoes? fila;

  /// Canal com o Tobias; nos testes, um falso. Padrão: o do [DeviceState].
  final DeviceTransport? transport;

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

  /// Estado CONFIRMADO pelo Tobias (ver [GravadorSessao.pausado]).
  var _pausado = false;

  /// PAUSAR/RETOMAR enviado, confirmação ainda não veio.
  var _aguardando = false;

  /// Comando que ficou sem resposta; a mensagem some na próxima tentativa.
  _Comando? _falha;

  /// Grava a sessão na fila local e fala com o Tobias (etapa 3).
  late final _gravador = GravadorSessao(
    sessao: widget.sessao,
    fila: widget.fila ?? FilaSessoes.doApp,
    transport: widget.transport ?? DeviceState.transport,
  );
  late final Future<void> _iniciada = _gravador.iniciar();

  @override
  void initState() {
    super.initState();
    _iniciarTimer();
    _gravador.pausado.addListener(_aoMudarPausa);
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

  /// A tela só entra e sai da pausa quando o Tobias confirma, inclusive
  /// numa confirmação que chegue depois do prazo.
  void _aoMudarPausa() {
    if (!mounted) return;
    final pausado = _gravador.pausado.value;
    if (pausado == _pausado) return;
    setState(() {
      _pausado = pausado;
      _falha = null;
    });
    if (pausado) {
      _timer?.cancel();
      _pulse.stop();
      _spin.stop();
    } else {
      _iniciarTimer();
      _pulse.repeat(reverse: true);
      _spin.repeat();
    }
  }

  /// Pede e espera a confirmação sem travar a tela: "Finalizar sessão"
  /// continua disponível enquanto isso.
  Future<void> _alternarPausa() async {
    if (_aguardando) return;
    final pausar = !_pausado;
    setState(() {
      _aguardando = true;
      _falha = null;
    });
    final ok = pausar ? await _gravador.pausar() : await _gravador.retomar();
    if (!mounted) return;
    setState(() {
      _aguardando = false;
      if (!ok) _falha = pausar ? _Comando.pausa : _Comando.retomada;
    });
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
    _gravador.pausado.removeListener(_aoMudarPausa);
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
            // Sem rolagem: os botões ficam sempre à vista, e quem cede espaço
            // numa tela baixa é o cronômetro (ver o Expanded abaixo).
            child: Padding(
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
                  // Ocupa a sobra e encolhe o círculo (280 no máximo) quando
                  // falta altura, como num celular de 360×640.
                  Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _cronometro(),
                      ),
                    ),
                  ),
                  _cartaoStatus(),
                  _BotaoPausar(
                    pausado: _pausado,
                    aguardando: _aguardando,
                    onTap: _alternarPausa,
                  ),
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

  static const _keyConectado = ValueKey('cartao-conectado');
  static const _keyFalha = ValueKey('cartao-falha');

  /// Cartão de conexão, que também mostra a falha de comando. A altura é
  /// sempre a do maior conteúdo possível (a reserva invisível leva o texto
  /// mais longo), então a mensagem aparece e some sem deslocar os botões:
  /// "Finalizar sessão" é justamente a saída de quem viu a falha.
  Widget _cartaoStatus() {
    Widget conteudo(IconData icone, String titulo, String texto) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Icon(icone, size: 20, color: AppColors.iconOnBrand),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(titulo, style: AppText.titleM.c(AppColors.textOnBrand)),
              Text(texto, style: AppText.bodyS.c(AppColors.textOnBrandMuted)),
            ],
          ),
        ),
      ],
    );

    Widget camada(Key? key, {required bool visivel, required Widget child}) =>
        Visibility(
          key: key,
          visible: visivel,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: child,
        );

    final falha = _falha;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgBrand,
        borderRadius: BorderRadius.circular(AppRadius.r20),
      ),
      child: Stack(
        children: [
          camada(
            _keyConectado,
            visivel: falha == null,
            child: conteudo(
              AppIcons.bluetoothConnected,
              'TOBIAS conectado',
              'Os lances são registrados no boneco. A pontuação aparece só depois que você finalizar a sessão.',
            ),
          ),
          // Reserva: nunca aparece, só garante a altura da falha mais longa.
          camada(
            null,
            visivel: false,
            child: conteudo(
              AppIcons.bluetooth,
              _tituloFalha,
              _textoFalha(_Comando.retomada),
            ),
          ),
          camada(
            _keyFalha,
            visivel: falha != null,
            child: conteudo(
              AppIcons.bluetooth,
              _tituloFalha,
              _textoFalha(falha ?? _Comando.pausa),
            ),
          ),
        ],
      ),
    );
  }

  static const _tituloFalha = 'O TOBIAS não respondeu';

  static String _textoFalha(_Comando c) =>
      'O comando de ${c.name} não foi confirmado pelo boneco. '
      'Tente de novo ou finalize a sessão.';

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

/// Comando de pausa/retomada, nomeado como aparece na mensagem de falha.
/// A retomada é o nome mais longo: é ela que reserva a altura do cartão.
enum _Comando { pausa, retomada }

/// Botão transparente de 56 com borda 2 `text/on-brand-muted`.
class _BotaoPausar extends StatelessWidget {
  const _BotaoPausar({
    required this.pausado,
    required this.aguardando,
    required this.onTap,
  });

  final bool pausado;

  /// Comando enviado, sem confirmação ainda: botão inativo com indicador.
  final bool aguardando;
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
          onTap: aguardando ? null : onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 8,
            children: [
              if (aguardando)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.iconOnBrand,
                  ),
                )
              else
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
