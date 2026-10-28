import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/format.dart';
import '../../data/mock_data.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/charts.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 5.3 Histórico · Dashboard (49:1289).
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// 0 = 7 dias, 1 = 30 dias, 2 = Tudo.
  var _periodo = 1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Segmented(
              left: 'Sessões',
              right: 'Dashboard',
              leftActive: false,
              onLeft: () => context.go(Routes.historico),
            ),
          ),
          ChipBar(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            labels: const ['7 dias', '30 dias', 'Tudo'],
            selected: _periodo,
            onSelected: (i) => setState(() => _periodo = i),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              children: const [
                _KpiPrincipal(),
                SizedBox(height: 14),
                _LinhaMetricas(),
                SizedBox(height: 14),
                _Distribuicao(),
                SizedBox(height: 14),
                _Frequencia(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiPrincipal extends StatelessWidget {
  const _KpiPrincipal();

  @override
  Widget build(BuildContext context) {
    const barras = Mock.dashMiniBarras;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgBrand,
        borderRadius: BorderRadius.circular(AppRadius.r24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pontuação total · ${Mock.dashSessoes} sessões',
                      style: AppText.labelL.c(AppColors.textOnBrandMuted),
                    ),
                    Text(
                      fmtInt(Mock.dashPontos),
                      style: AppText.displayLarge.c(AppColors.textOnBrand),
                    ),
                  ],
                ),
              ),
              const AppBadge(Mock.dashVariacao, tone: BadgeTone.accent),
            ],
          ),
          SizedBox(
            height: 31,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < barras.length; i++)
                  Container(
                    width: 16,
                    height: barras[i],
                    decoration: BoxDecoration(
                      color: i == barras.length - 1
                          ? AppColors.bgAccent
                          : AppColors.bgBrandStrong,
                      borderRadius: BorderRadius.circular(AppRadius.r8),
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

class _LinhaMetricas extends StatelessWidget {
  const _LinhaMetricas();

  @override
  Widget build(BuildContext context) {
    // Altura de referência no Figma: 150. IntrinsicHeight iguala os dois
    // cartões sem cortar o conteúdo quando o texto é maior.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 150),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Expanded(
              child: SurfaceCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 8,
                  children: [
                    Text(
                      'Precisão',
                      style: AppText.labelL.c(AppColors.textSecondary),
                    ),
                    ProgressRing(
                      size: 68,
                      fraction: Mock.dashPrecisao / 100,
                      child: Text(
                        '${Mock.dashPrecisao}%',
                        style: AppText.titleL,
                      ),
                    ),
                    Text(
                      Mock.dashPrecisaoVariacao,
                      style: AppText.labelS.c(AppColors.textBrand),
                    ),
                  ],
                ),
              ),
            ),
            // O cartão "Reação média" saiu; "Melhor sequência" ocupa a
            // altura toda da coluna.
            Expanded(
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 2,
                  children: [
                    Row(
                      spacing: 6,
                      children: [
                        const Icon(
                          AppIcons.flame,
                          size: 16,
                          color: AppColors.iconBrand,
                        ),
                        Expanded(
                          child: Text(
                            'Melhor sequência',
                            style: AppText.labelM.c(AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${Mock.dashMelhorSequencia}',
                      style: AppText.headlineM,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Distribuicao extends StatelessWidget {
  const _Distribuicao();

  @override
  Widget build(BuildContext context) {
    const partes = [
      ('Acertos', Mock.dashAcertos, AppColors.bgBrand),
      ('KO', Mock.dashKo, AppColors.bgWarning),
      ('Erros', Mock.dashErros, AppColors.bgError),
    ];
    return SectionCard(
      gap: 14,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Distribuição dos lances', style: AppText.titleM),
            ),
            Text(
              '${Mock.dashTotalLances} lances',
              style: AppText.labelM.c(AppColors.textSecondary),
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r7),
          child: SizedBox(
            height: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (_, pct, cor) in partes)
                  Expanded(
                    flex: pct,
                    child: ColoredBox(color: cor),
                  ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final (rotulo, pct, cor) in partes)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    rotulo,
                    style: AppText.labelM.c(AppColors.textSecondary),
                  ),
                  Text('$pct%', style: AppText.labelL),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _Frequencia extends StatelessWidget {
  const _Frequencia();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      gap: 14,
      children: [
        Row(
          children: [
            Expanded(child: Text('Frequência semanal', style: AppText.titleM)),
            Text(
              '${Mock.dashDiasTreinados} de 7 dias',
              style: AppText.labelL.c(AppColors.textBrand),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < 7; i++)
              Column(
                spacing: 6,
                children: [
                  DayDot(
                    letter: kWeekLetters[i],
                    active: Mock.dashSemana[i],
                    size: 36,
                    showCheck: true,
                  ),
                  Text(
                    kWeekLetters[i],
                    style: AppText.labelM.c(AppColors.textSecondary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
