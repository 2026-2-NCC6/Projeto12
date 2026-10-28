import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/format.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 4.3 Sessão · Finalização (21:897) — resumo da sessão.
class ResumoScreen extends StatelessWidget {
  const ResumoScreen({super.key, required this.treino});

  final String treino;

  @override
  Widget build(BuildContext context) {
    const s = Mock.ultimaSessao;
    int contar(ShotResult r) =>
        Mock.lances.where((l) => l.resultado == r).length;
    return StatusBarStyle(
      light: true,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        body: Column(
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
                      Text(
                        fmtInt(s.pontos),
                        style: AppText.displayScore.c(AppColors.textOnBrand),
                      ),
                      Text(
                        'pontos · $treino',
                        style: AppText.bodyM.c(AppColors.textOnBrandMuted),
                      ),
                      const AppBadge(
                        'Novo recorde pessoal',
                        tone: BadgeTone.accent,
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
                      Row(
                        spacing: 12,
                        children: [
                          Expanded(
                            child: StatCard(
                              icon: AppIcons.target,
                              value: '${s.precisao}%',
                              label: 'Precisão',
                            ),
                          ),
                          const Expanded(
                            child: StatCard(
                              icon: AppIcons.flame,
                              value: '${Mock.ultimaSessaoMelhorSequencia}',
                              label: 'Melhor sequência',
                            ),
                          ),
                        ],
                      ),
                      Row(
                        spacing: 12,
                        children: [
                          // KO = derrubou o boneco; Erros = sem impacto válido.
                          Expanded(
                            child: StatCard(
                              icon: AppIcons.zap,
                              value: '${contar(ShotResult.ko)}',
                              label: 'KO',
                            ),
                          ),
                          Expanded(
                            child: StatCard(
                              icon: AppIcons.x,
                              value: '${contar(ShotResult.erro)}',
                              label: 'Erros',
                            ),
                          ),
                        ],
                      ),
                      const InfoBanner(
                        icon: AppIcons.cloudUpload,
                        tone: InfoTone.warning,
                        title: 'Sincronização pendente',
                        body:
                            'Salvo no celular. Precisão estimada: impacto não é erro.',
                      ),
                      const Spacer(),
                      AppButton(
                        'Ver lances da sessão',
                        icon: AppIcons.list,
                        onPressed: () => context.push(Routes.historicoDetalhe),
                      ),
                      Row(
                        spacing: 12,
                        children: [
                          Expanded(
                            child: AppButton.outline(
                              'Treinar de novo',
                              onPressed: () => context.go(Routes.sessao),
                            ),
                          ),
                          Expanded(
                            child: AppButton.text(
                              'Concluir',
                              onPressed: () => context.go(Routes.historico),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
