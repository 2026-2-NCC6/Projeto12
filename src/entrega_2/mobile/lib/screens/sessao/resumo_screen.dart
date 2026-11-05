import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fila_sessoes.dart';
import '../../data/format.dart';
import '../../data/resumo_sessao.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/layout.dart';

/// 4.3 Sessão · Finalização (21:897) — resumo da sessão que acabou de
/// acontecer, calculado sobre os lances gravados na fila local.
///
/// Sem "comparação com a sessão anterior" (RF12) por enquanto: fica para
/// outra etapa. A fila já guarda as 10 sincronizadas mais recentes como
/// histórico local, que é de onde ela virá.
class ResumoScreen extends StatefulWidget {
  const ResumoScreen({
    super.key,
    required this.uuidSessao,
    required this.treino,
    this.fila,
  });

  final String? uuidSessao;
  final String treino;

  /// Nos testes, uma fila isolada.
  final FilaSessoes? fila;

  @override
  State<ResumoScreen> createState() => _ResumoScreenState();
}

class _ResumoScreenState extends State<ResumoScreen> {
  FilaSessoes get _fila => widget.fila ?? FilaSessoes.doApp;

  late final Future<ResumoSessao?> _dados = _carregar();

  /// Aguardando envio e separadas por erro; recontadas sempre que a fila
  /// muda (ex.: o envio que o fim da sessão disparou terminou), para os
  /// avisos se atualizarem sozinhos.
  var _pendentes = 0;
  var _separadas = 0;

  @override
  void initState() {
    super.initState();
    _fila.alteracoes.addListener(_recontar);
  }

  @override
  void dispose() {
    _fila.alteracoes.removeListener(_recontar);
    super.dispose();
  }

  Future<(int, int)> _contar() async => (
    (await _fila.aguardandoEnvio()).length,
    (await _fila.separadas()).length,
  );

  Future<void> _recontar() async {
    final (p, s) = await _contar();
    if (mounted) {
      setState(() {
        _pendentes = p;
        _separadas = s;
      });
    }
  }

  Future<ResumoSessao?> _carregar() async {
    final uuid = widget.uuidSessao;
    final sessao = uuid == null ? null : await _fila.sessao(uuid);
    final (p, s) = await _contar();
    _pendentes = p;
    _separadas = s;
    return sessao == null ? null : ResumoSessao.de(sessao);
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle(
      light: true,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        body: FutureBuilder(
          future: _dados,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.bgBrand),
              );
            }
            final resumo = snap.data;
            return resumo == null
                ? _naoEncontrada(context)
                : _conteudo(context, resumo);
          },
        ),
      ),
    );
  }

  Widget _naoEncontrada(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          Text(
            'Sessão não encontrada neste aparelho.',
            style: AppText.titleM,
            textAlign: TextAlign.center,
          ),
          AppButton(
            'Nova sessão',
            onPressed: () => context.go(Routes.sessao),
          ),
        ],
      ),
    ),
  );

  Widget _conteudo(BuildContext context, ResumoSessao r) {
    final pendentes = _pendentes;
    final separadas = _separadas;
    String pct(double? v) => v == null ? '—' : '${(v * 100).round()}%';

    Widget linha(List<Widget> cards) => Row(
      spacing: 12,
      children: [for (final c in cards) Expanded(child: c)],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: AppColors.bgBrand,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
              child: Column(
                spacing: 8,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: AppColors.bgAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.trophy,
                      size: 32,
                      color: AppColors.iconOnAccent,
                    ),
                  ),
                  Text(
                    'Sessão concluída!',
                    style: AppText.titleL.c(AppColors.textOnBrand),
                  ),
                  // O nome do treino numa linha própria: junto do placar
                  // ("145 pontos · Reação rápida") parecia qualificar a nota.
                  if (widget.treino.isNotEmpty)
                    Text(
                      widget.treino,
                      textAlign: TextAlign.center,
                      style: AppText.titleM.c(AppColors.textOnBrandMuted),
                    ),
                  Column(
                    children: [
                      Text(
                        fmtInt(r.pontuacaoTotal),
                        style: AppText.displayScore.c(AppColors.textOnBrand),
                      ),
                      Text(
                        'pontos',
                        style: AppText.bodyM.c(AppColors.textOnBrandMuted),
                      ),
                    ],
                  ),
                  Text(
                    '${r.lances} lances · ${r.acertos} acertos',
                    style: AppText.bodyS.c(AppColors.textOnBrandMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            top: false,
            child: ScrollFill(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  // RF21: o usuário precisa saber que os dados ainda não subiram.
                  // No topo, para ser visto sem rolar a tela.
                  if (pendentes > 0)
                    InfoBanner(
                      icon: AppIcons.cloudUpload,
                      tone: InfoTone.warning,
                      title: 'Salvo no celular, aguardando envio',
                      body: pendentes == 1
                          ? '1 sessão na fila'
                          : '$pendentes sessões na fila',
                    ),
                  // Recusadas pela API por erro do app (422): guardadas no
                  // aparelho, mas não serão enviadas.
                  if (separadas > 0)
                    InfoBanner(
                      icon: AppIcons.cloudUpload,
                      tone: InfoTone.warning,
                      title: 'Não foi possível enviar',
                      body: separadas == 1
                          ? '1 sessão com erro, guardada no celular'
                          : '$separadas sessões com erro, guardadas no celular',
                    ),
                  linha([
                    StatCard(
                      icon: AppIcons.target,
                      value: pct(r.precisao),
                      label: 'Precisão',
                    ),
                    StatCard(
                      icon: AppIcons.flame,
                      value: '${r.melhorSequencia}',
                      label: 'Melhor sequência',
                    ),
                  ]),
                  linha([
                    // KO = derrubou o boneco (ângulo acima do limiar);
                    // Erros = sem impacto válido na janela do lance.
                    StatCard(
                      icon: AppIcons.zap,
                      value: '${r.kos}',
                      label: 'KO',
                    ),
                    StatCard(
                      icon: AppIcons.x,
                      value: '${r.erros}',
                      label: 'Erros',
                    ),
                  ]),
                  // Sem "Fortes": o firmware decide forte e KO na mesma
                  // condição, seria o KO contado duas vezes. Ângulos e
                  // consistência seguem calculados em ResumoSessao, fora da
                  // tela por decisão de produto (etapa 4b).
                  linha([
                    StatCard(
                      icon: AppIcons.tennisBall,
                      value: '${r.fracos}',
                      label: 'Fracos',
                    ),
                    StatCard(
                      icon: AppIcons.tennisBall,
                      value: '${r.medios}',
                      label: 'Médios',
                    ),
                  ]),
                  const Spacer(),
                  linha([
                    AppButton.outline(
                      'Treinar de novo',
                      onPressed: () => context.go(Routes.sessao),
                    ),
                    AppButton.text(
                      'Concluir',
                      onPressed: () => context.go(Routes.historico),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
