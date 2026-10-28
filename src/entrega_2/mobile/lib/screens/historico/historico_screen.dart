import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/format.dart';
import '../../data/mock_data.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

enum FiltroHistorico { todas, mes, pendentes }

/// 5.1 Histórico · Sessões (22:852), 5.5 Este mês (63:1991),
/// 5.4 Pendentes (59:1726).
class HistoricoScreen extends StatelessWidget {
  const HistoricoScreen({super.key, required this.filtro});

  final FiltroHistorico filtro;

  static const _rotas = [
    Routes.historico,
    Routes.historicoMes,
    Routes.historicoPendentes,
  ];

  @override
  Widget build(BuildContext context) {
    final sessoes = switch (filtro) {
      FiltroHistorico.todas => Mock.sessoesTodas,
      FiltroHistorico.mes => Mock.sessoesMes,
      FiltroHistorico.pendentes => Mock.sessoesPendentes,
    };

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
              ],
            ),
          ),
          ChipBar(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            labels: const ['Todas', 'Este mês', 'Pendentes'],
            selected: filtro.index,
            onSelected: (i) => context.go(_rotas[i]),
          ),
          Expanded(
            child: ScrollFill(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 12,
                children: [
                  if (filtro == FiltroHistorico.pendentes)
                    InfoBanner(
                      icon: AppIcons.cloudOff,
                      tone: InfoTone.warning,
                      title: '${sessoes.length} sessões aguardando envio',
                      body:
                          'Estão salvas no seu celular e serão enviadas quando houver internet. A pontuação é provisória até o servidor confirmar.',
                    ),
                  if (filtro == FiltroHistorico.mes) const _ResumoMes(),
                  for (final s in sessoes)
                    SessionCard(
                      session: s,
                      onTap: () => context.push(Routes.historicoDetalhe),
                    ),
                  if (filtro == FiltroHistorico.pendentes) ...[
                    const Spacer(),
                    AppButton(
                      'Sincronizar agora',
                      icon: AppIcons.refreshCw,
                      onPressed: () {},
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumoMes extends StatelessWidget {
  const _ResumoMes();

  @override
  Widget build(BuildContext context) {
    Widget metrica(String valor, String rotulo) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valor, style: AppText.headlineM.c(AppColors.textOnBrand)),
        Text(rotulo, style: AppText.labelM.c(AppColors.textOnBrandMuted)),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgBrand,
        borderRadius: BorderRadius.circular(AppRadius.r20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            Mock.mesTitulo,
            style: AppText.labelL.c(AppColors.textOnBrandMuted),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              metrica('${Mock.mesSessoes}', 'sessões'),
              metrica(fmtInt(Mock.mesPontos), 'pontos'),
              metrica('${Mock.mesPrecisao}%', 'precisão média'),
            ],
          ),
        ],
      ),
    );
  }
}
