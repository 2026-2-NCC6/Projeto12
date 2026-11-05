import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/fila_sessoes.dart';
import '../../data/models.dart';
import '../../data/resumo_sessao.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 5.1 Histórico · Sessões (22:852), com as sessões guardadas no aparelho.
///
/// Uma lista só, da mais recente para a mais antiga: pendentes (RF21: quem
/// treinou sem rede tem de ver que treinou), sincronizadas e as separadas
/// por erro. Sem filtro por período: com no máximo ~30 sessões locais seria
/// enfeite. O RF13 completo (por período, independente de aparelho) pede um
/// `GET /v1/sessions`, que ainda não existe.
class HistoricoScreen extends StatefulWidget {
  const HistoricoScreen({super.key, this.fila});

  /// Nos testes, uma fila isolada.
  final FilaSessoes? fila;

  @override
  State<HistoricoScreen> createState() => _HistoricoScreenState();
}

class _HistoricoScreenState extends State<HistoricoScreen> {
  FilaSessoes get _fila => widget.fila ?? FilaSessoes.doApp;

  /// Nulo enquanto carrega. Relido quando a fila muda (ex.: um envio
  /// terminou e a pendente virou sincronizada).
  List<Session>? _sessoes;

  @override
  void initState() {
    super.initState();
    _fila.alteracoes.addListener(_carregar);
    _carregar();
  }

  @override
  void dispose() {
    _fila.alteracoes.removeListener(_carregar);
    super.dispose();
  }

  Future<void> _carregar() async {
    final sessoes = [for (final s in await _fila.historico()) itemDoHistorico(s)];
    if (mounted) setState(() => _sessoes = sessoes);
  }

  @override
  Widget build(BuildContext context) {
    final sessoes = _sessoes;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                Text('Histórico', style: AppText.headlineM),
                Segmented(
                  left: 'Sessões',
                  right: 'Dashboard',
                  leftActive: true,
                  onRight: () => context.go(Routes.historicoDashboard),
                ),
                // Não é detalhe de implementação: se o app for reinstalado,
                // estas sessões somem, e a pessoa precisa ter sido avisada.
                Text(
                  'Últimas sessões deste aparelho. Não voltam se o app for '
                  'reinstalado.',
                  style: AppText.bodyS.c(AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ScrollFill(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  if (sessoes == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.bgBrand,
                        ),
                      ),
                    )
                  else if (sessoes.isEmpty) ...[
                    const SizedBox(height: 32),
                    Text(
                      'Nenhuma sessão neste aparelho ainda.',
                      style: AppText.titleM,
                      textAlign: TextAlign.center,
                    ),
                    AppButton(
                      'Nova sessão',
                      onPressed: () => context.push(Routes.sessao),
                    ),
                  ] else
                    for (final s in sessoes)
                      SessionCard(
                        session: s,
                        onTap: () => context.push(
                          '${Routes.historicoDetalhe}?sessao=${s.id}',
                        ),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _meses = [
  'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
  'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
];

/// O cartão do histórico para uma sessão guardada: data local, nome do
/// treino, pontuação exibida (a oficial, se sincronizada) e precisão.
@visibleForTesting
Session itemDoHistorico(SessaoLocal s) {
  final inicio = DateTime.parse(s.iniciadaEm).toLocal();
  final resumo = ResumoSessao.de(s);
  return Session(
    id: s.uuidSessao,
    dia: inicio.day,
    mes: _meses[inicio.month - 1],
    // Sessões gravadas antes da etapa 7 não guardavam o nome do treino.
    drillTitulo: s.treinoTitulo ?? 'Treino',
    lances: resumo.lances,
    precisao: ((resumo.precisao ?? 0) * 100).round(),
    pontos: s.pontuacaoExibida,
    sincronizada: s.sincronizada,
    separada: s.falha != null,
  );
}
