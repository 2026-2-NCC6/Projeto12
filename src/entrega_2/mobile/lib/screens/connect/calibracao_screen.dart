import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/format.dart';
import '../../router.dart';
import '../../state/device_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../transport/device_transport.dart';
import '../../widgets/buttons.dart';
import '../../widgets/charts.dart';
import '../../widgets/layout.dart';

enum _Fase { coletando, calculando, concluida }

/// 2.6 a 2.12 Calibração (0/5 … 4/5, Calculando, Concluída) e 6.2
/// Recalibração — mesma tela com estado.
///
/// Cada batida vem de `DeviceTransport.events` (no protótipo, do
/// `MockTransport`). Com 5 batidas entra em modo de espera, calcula a
/// mediana (`a_ref`) e termina em "Calibração concluída".
class CalibracaoScreen extends StatefulWidget {
  const CalibracaoScreen({super.key, this.recalibrar = false});

  final bool recalibrar;

  @override
  State<CalibracaoScreen> createState() => _CalibracaoScreenState();
}

class _CalibracaoScreenState extends State<CalibracaoScreen> {
  static const _total = 5;

  /// Duração do anel enchendo e da barra subindo a cada batida (cabe no
  /// intervalo de 1,2 s entre as batidas do simulador).
  static const _anim = Duration(milliseconds: 900);

  /// Espera mínima em "Calculando a mediana…" (2,5 s no protótipo).
  static const _espera = Duration(milliseconds: 2500);

  final _batidas = <double>[];
  var _fase = _Fase.coletando;
  StreamSubscription<ImpactEvent>? _sub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _ouvir();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _ouvir() {
    _sub = DeviceState.transport.events.listen(_aoImpacto);
  }

  void _aoImpacto(ImpactEvent e) {
    if (_fase != _Fase.coletando) return;
    setState(() => _batidas.add(e.aPkG));
    if (_batidas.length < _total) return;
    // Modo de espera: ignora novas batidas enquanto calcula a mediana.
    _sub?.cancel();
    _sub = null;
    setState(() => _fase = _Fase.calculando);
    _timer = Timer(_espera, () {
      DeviceState.refG.value = _mediana;
      setState(() => _fase = _Fase.concluida);
    });
  }

  /// "Recomeçar" e "Recalibrar": volta ao 0/5.
  void _recomecar() {
    _sub?.cancel();
    _timer?.cancel();
    setState(() {
      _batidas.clear();
      _fase = _Fase.coletando;
    });
    _ouvir();
  }

  /// Mediana dos picos recebidos (com número par, média dos dois do meio).
  double get _mediana {
    final s = List<double>.of(_batidas)..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  void _concluir() => widget.recalibrar
      ? goBack(context, Routes.perfil)
      : context.go(Routes.treinos);

  @override
  Widget build(BuildContext context) {
    final n = _batidas.length;
    final concluida = _fase == _Fase.concluida;
    final ref = n == 0 ? '—' : '${fmtDec(_mediana)} g';

    final (titulo, subtitulo) = switch (_fase) {
      _Fase.coletando => (
        'Dê 5 batidas de referência',
        'Bata no TOBIAS com a força normal do seu jogo. Usamos a mediana das batidas como sua referência.',
      ),
      _Fase.calculando => (
        'Calculando a mediana…',
        'Recebemos as 5 batidas. Aguarde um instante enquanto definimos a sua referência de força.',
      ),
      _Fase.concluida => (
        'Calibração concluída',
        'Sua referência de força é $ref, a mediana das 5 batidas. Já pode treinar.',
      ),
    };

    return StackedScreen(
      title: widget.recalibrar ? 'Recalibrar o TOBIAS' : 'Calibração',
      onBack: () => goBack(
        context,
        widget.recalibrar ? Routes.perfil : Routes.pareamento,
      ),
      crossAxisAlignment: CrossAxisAlignment.center,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      gap: 14,
      children: [
        _Troca(
          Text(
            titulo,
            key: ValueKey(titulo),
            textAlign: TextAlign.center,
            style: AppText.titleL,
          ),
        ),
        _Troca(
          Text(
            subtitulo,
            key: ValueKey(subtitulo),
            textAlign: TextAlign.center,
            style: AppText.bodyM.c(AppColors.textSecondary),
          ),
        ),
        _Anel(batidas: n, total: _total, concluida: concluida, duracao: _anim),
        SizedBox(
          width: double.infinity,
          child: SectionCard(
            gap: 10,
            children: [
              Text(
                'Força de cada batida',
                style: AppText.labelM.c(AppColors.textSecondary),
              ),
              _Barras(batidas: _batidas, total: _total, duracao: _anim),
              Row(
                spacing: 6,
                children: [
                  switch (_fase) {
                    _Fase.coletando => const Icon(
                      AppIcons.activity,
                      size: 16,
                      color: AppColors.iconDefault,
                    ),
                    _Fase.calculando => const Spinning(
                      child: Icon(
                        AppIcons.refreshCw,
                        size: 16,
                        color: AppColors.iconDefault,
                      ),
                    ),
                    _Fase.concluida => const Icon(
                      AppIcons.checkCircle,
                      size: 16,
                      color: AppColors.iconBrand,
                    ),
                  },
                  Expanded(
                    child: Text(switch (_fase) {
                      _Fase.coletando =>
                        'Referência provisória (mediana): $ref',
                      _Fase.calculando => 'Calculando a mediana das 5 batidas…',
                      _Fase.concluida => 'Referência final (mediana): $ref',
                    }, style: AppText.bodyS.c(AppColors.textSecondary)),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Troca(switch (_fase) {
          _Fase.coletando => const InfoBanner(
            key: ValueKey('dica'),
            icon: AppIcons.lightbulb,
            tone: InfoTone.warning,
            body:
                'Evite batidas fracas de propósito: elas inflam sua pontuação e podem ser sinalizadas.',
          ),
          _Fase.calculando => const InfoBanner(
            key: ValueKey('espera'),
            icon: AppIcons.lightbulb,
            tone: InfoTone.warning,
            body: 'Não mexa no boneco enquanto calculamos.',
          ),
          _Fase.concluida => const InfoBanner(
            key: ValueKey('recalibrar'),
            icon: AppIcons.info,
            bodyColor: AppColors.textPrimary,
            body:
                'Você pode recalibrar quando quiser em Perfil › Recalibrar o TOBIAS.',
          ),
        }),
        const Spacer(),
        ...switch (_fase) {
          _Fase.coletando => [
            const AppButton('Concluir calibração'),
            AppButton.outline('Recomeçar', onPressed: _recomecar),
          ],
          _Fase.calculando => [const AppButton('Calculando…')],
          _Fase.concluida => [
            // Na Recalibração (Perfil) o destino final é o Perfil.
            AppButton(
              widget.recalibrar ? 'Concluir calibração' : 'Ir para os treinos',
              onPressed: _concluir,
            ),
            AppButton.outline('Recalibrar', onPressed: _recomecar),
          ],
        },
      ],
    );
  }
}

/// Troca suave (fade) quando o filho muda de chave.
class _Troca extends StatelessWidget {
  const _Troca(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}

/// Anel de progresso 176×176: enche até n/5 a cada batida. Concluída: arco
/// `bg/accent` e ícone `check` 72 no centro.
class _Anel extends StatelessWidget {
  const _Anel({
    required this.batidas,
    required this.total,
    required this.concluida,
    required this.duracao,
  });

  final int batidas;
  final int total;
  final bool concluida;
  final Duration duracao;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: batidas / total),
      duration: duracao,
      // Sai rápido e desacelera devagar até a nova fração.
      curve: Curves.easeOutCubic,
      builder: (context, fracao, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(
          end: concluida ? AppColors.bgAccent : AppColors.bgBrand,
        ),
        duration: duracao,
        curve: Curves.easeInOut,
        builder: (context, cor, _) => ProgressRing(
          size: 176,
          fraction: fracao,
          arc: cor!,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: concluida
                ? const Icon(
                    AppIcons.check,
                    key: ValueKey('ok'),
                    size: 72,
                    color: AppColors.iconBrand,
                  )
                : Column(
                    key: const ValueKey('contagem'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Contador(batidas, duracao: duracao),
                          Text('/$total', style: AppText.displayLarge),
                        ],
                      ),
                      Text(
                        'batidas',
                        style: AppText.labelM.c(AppColors.textSecondary),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// 5 barras (largura 44) alinhadas na base. Pendente: tracejada de 24 com
/// "—"; feita: sobe até a altura da força e fica sólida `bg/brand`.
class _Barras extends StatelessWidget {
  const _Barras({
    required this.batidas,
    required this.total,
    required this.duracao,
  });

  final List<double> batidas;
  final int total;
  final Duration duracao;

  static const _alturaMax = 76.0;

  /// Altura proporcional à força: 8,4 g → 58, 8,9 g → 69, 9,2 g → 76.
  static double _altura(double g) =>
      (58 + (g - 8.4) * 22.5).clamp(28.0, _alturaMax);

  @override
  Widget build(BuildContext context) {
    // Área fixa (barra mais alta + valor) para o cartão não "pular" quando
    // as barras sobem.
    final rotulo = MediaQuery.textScalerOf(context).scale(16);
    return SizedBox(
      height: _alturaMax + 6 + rotulo,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < total; i++)
            _barra(i < batidas.length ? batidas[i] : null),
        ],
      ),
    );
  }

  Widget _barra(double? valor) {
    final feita = valor != null;
    return SizedBox(
      width: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: 6,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: _subirComFade,
            child: Text(
              feita ? '${fmtDec(valor)} g' : '—',
              key: ValueKey(valor),
              maxLines: 1,
              style: AppText.labelM.c(
                feita ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
          AnimatedContainer(
            duration: duracao,
            curve: Curves.easeOutCubic,
            width: 44,
            height: feita ? _altura(valor) : 24,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // O tracejado some enquanto o preenchimento aparece, na
                // primeira metade da subida.
                AnimatedOpacity(
                  duration: duracao ~/ 2,
                  curve: Curves.easeOut,
                  opacity: feita ? 0 : 1,
                  child: CustomPaint(
                    painter: DashedRRectPainter(color: AppColors.borderStrong),
                  ),
                ),
                AnimatedOpacity(
                  duration: duracao ~/ 2,
                  curve: Curves.easeOut,
                  opacity: feita ? 1 : 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.bgBrand,
                      borderRadius: BorderRadius.circular(AppRadius.r8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Entrada de baixo para cima com fade (número do anel e valor das barras).
Widget _subirComFade(Widget child, Animation<double> anim) => FadeTransition(
  opacity: anim,
  child: SlideTransition(
    position: Tween(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(anim),
    child: child,
  ),
);

/// Número de batidas do anel: o novo valor sobe no lugar do anterior junto
/// com o preenchimento do arco.
class _Contador extends StatelessWidget {
  const _Contador(this.valor, {required this.duracao});

  final int valor;
  final Duration duracao;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: duracao ~/ 2,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          // O que entra sobe de baixo; o que sai continua subindo e some.
          final entrando = child.key == ValueKey(valor);
          final inicio = entrando
              ? const Offset(0, 0.6)
              : const Offset(0, -0.6);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: inicio, end: Offset.zero).animate(anim),
              child: child,
            ),
          );
        },
        child: Text(
          '$valor',
          key: ValueKey(valor),
          style: AppText.displayLarge,
        ),
      ),
    );
  }
}
