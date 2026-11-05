import 'package:flutter/material.dart';

import '../../data/detalhe_sessao.dart';
import '../../data/fila_sessoes.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../data/resumo_sessao.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';
import '../sessao/sessao_nao_encontrada.dart';

/// 5.2 Histórico · Detalhe (22:978): uma sessão da fila local, lance a lance.
/// Entra pelo cartão do histórico, com o `uuid_sessao`. Voltar = pop para
/// quem chamou.
///
/// Diferenças deliberadas em relação ao Figma: ângulo em graus (o firmware
/// mede inclinação, não g); faixas Fraco/Médio/KO, sem "Forte" (o KO é a
/// faixa forte, como no resumo); erro é "Sem impacto", com os −20.
class DetalheScreen extends StatefulWidget {
  const DetalheScreen({super.key, required this.uuidSessao, this.fila});

  final String? uuidSessao;

  /// Nos testes, uma fila isolada.
  final FilaSessoes? fila;

  @override
  State<DetalheScreen> createState() => _DetalheScreenState();
}

class _DetalheScreenState extends State<DetalheScreen> {
  FilaSessoes get _fila => widget.fila ?? FilaSessoes.doApp;

  var _filtro = FiltroLances.todos;

  /// Relido quando a fila muda (ex.: o envio terminou e o selo de
  /// pendente some, com a pontuação passando à oficial).
  var _carregado = false;
  SessaoLocal? _sessao;

  @override
  void initState() {
    super.initState();
    _fila.alteracoes.addListener(_carregar);
    _carregar();
  }

  /// Outra sessão no mesmo lugar da árvore: recarrega e volta a "Todos".
  @override
  void didUpdateWidget(DetalheScreen antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.uuidSessao != widget.uuidSessao) {
      _filtro = FiltroLances.todos;
      _carregar();
    }
  }

  @override
  void dispose() {
    _fila.alteracoes.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final uuid = widget.uuidSessao;
    final sessao = uuid == null ? null : await _fila.sessao(uuid);
    if (!mounted) return;
    setState(() {
      _carregado = true;
      _sessao = sessao;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sessao = _sessao;
    return StatusBarStyle(
      light: false,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        body: !_carregado
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.bgBrand),
              )
            : sessao == null
            ? const SessaoNaoEncontrada()
            : _conteudo(context, sessao),
      ),
    );
  }

  Widget _conteudo(BuildContext context, SessaoLocal sessao) {
    final todos = lancesDoDetalhe(sessao);
    final lances = filtrarLances(todos, _filtro);

    return SafeArea(
      child: Column(
        children: [
          AppBarX(
            title: tituloDoDetalhe(sessao),
            onBack: () => goBack(context, Routes.historico),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              children: [
                _Resumo(sessao: sessao),
                const SizedBox(height: 12),
                Row(
                  spacing: 8,
                  children: [
                    Expanded(
                      child: Text(
                        'Lances (${todos.length})',
                        style: AppText.titleM,
                      ),
                    ),
                    Row(
                      spacing: 6,
                      children: [
                        for (final (f, rotulo) in const [
                          (FiltroLances.todos, 'Todos'),
                          (FiltroLances.erros, 'Erros'),
                          (FiltroLances.kos, 'KO'),
                        ])
                          AppChip(
                            rotulo,
                            compact: true,
                            selected: _filtro == f,
                            onTap: () => setState(() => _filtro = f),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (lances.isEmpty)
                  _FiltroVazio(filtro: _filtro)
                else
                  for (final (i, l) in lances.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    ShotRow(shot: l),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtro sem resultado: um estado próprio, não uma lista em branco.
class _FiltroVazio extends StatelessWidget {
  const _FiltroVazio({required this.filtro});

  final FiltroLances filtro;

  @override
  Widget build(BuildContext context) {
    final texto = switch (filtro) {
      FiltroLances.erros => 'Nenhum erro nesta sessão.',
      FiltroLances.kos => 'Nenhum KO nesta sessão.',
      FiltroLances.todos => 'Nenhum lance nesta sessão.',
    };
    return SurfaceCard(
      radius: AppRadius.r16,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        spacing: 12,
        children: [
          const IconBadge(icon: AppIcons.target, circle: true),
          Expanded(
            child: Text(
              texto,
              style: AppText.bodyM.c(AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo({required this.sessao});

  final SessaoLocal sessao;

  @override
  Widget build(BuildContext context) {
    final r = ResumoSessao.de(sessao);
    final precisao = r.precisao == null ? '—' : '${(r.precisao! * 100).round()}%';

    Widget metrica(String valor, String rotulo) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgBrandStrong,
          borderRadius: BorderRadius.circular(AppRadius.r12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(valor, style: AppText.titleM.c(AppColors.textOnBrand)),
            Text(rotulo, style: AppText.labelS.c(AppColors.textOnBrandMuted)),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgBrand,
        borderRadius: BorderRadius.circular(AppRadius.r24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // Sessões gravadas antes da etapa 7 não têm o nome.
                      sessao.treinoTitulo ?? 'Treino',
                      style: AppText.labelL.c(AppColors.textOnBrandMuted),
                    ),
                    // A oficial do servidor quando existe.
                    Text(
                      fmtInt(sessao.pontuacaoExibida),
                      style: AppText.displayLarge.c(AppColors.textOnBrand),
                    ),
                  ],
                ),
              ),
              // Mesmos selos do histórico; sincronizada não leva selo.
              if (sessao.falha != null)
                const AppBadge('Não enviada', tone: BadgeTone.error)
              else if (!sessao.sincronizada)
                const AppBadge('Pendente', tone: BadgeTone.warning),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              metrica(precisao, 'Precisão'),
              metrica('${r.melhorSequencia}', 'Melhor sequência'),
            ],
          ),
        ],
      ),
    );
  }
}
