import 'package:flutter/material.dart';

import '../../data/format.dart';
import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 5.2 Histórico · Detalhe (22:978). Voltar = pop para quem chamou.
class DetalheScreen extends StatefulWidget {
  const DetalheScreen({super.key});

  @override
  State<DetalheScreen> createState() => _DetalheScreenState();
}

class _DetalheScreenState extends State<DetalheScreen> {
  /// 0 = Todos, 1 = Erros, 2 = KO.
  var _filtro = 0;

  @override
  Widget build(BuildContext context) {
    const s = Mock.ultimaSessao;
    final lances = switch (_filtro) {
      1 => Mock.lances.where((l) => l.resultado == ShotResult.erro).toList(),
      2 => Mock.lances.where((l) => l.resultado == ShotResult.ko).toList(),
      _ => Mock.lances,
    };

    return StatusBarStyle(
      light: false,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        body: SafeArea(
          child: Column(
            children: [
              AppBarX(
                title: 'Sessão de ${s.dia} set',
                onBack: () => goBack(context, Routes.historico),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  children: [
                    const _Resumo(),
                    const SizedBox(height: 12),
                    Row(
                      spacing: 8,
                      children: [
                        Expanded(
                          child: Text(
                            'Lances (${Mock.lances.length})',
                            style: AppText.titleM,
                          ),
                        ),
                        Row(
                          spacing: 6,
                          children: [
                            for (final (i, label) in const [
                              'Todos',
                              'Erros',
                              'KO',
                            ].indexed)
                              AppChip(
                                label,
                                compact: true,
                                selected: _filtro == i,
                                onTap: () => setState(() => _filtro = i),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    for (final (i, l) in lances.indexed) ...[
                      if (i > 0) const SizedBox(height: 8),
                      ShotRow(shot: l),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  const _Resumo();

  @override
  Widget build(BuildContext context) {
    const s = Mock.ultimaSessao;
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
                      s.drillTitulo,
                      style: AppText.labelL.c(AppColors.textOnBrandMuted),
                    ),
                    Text(
                      fmtInt(s.pontos),
                      style: AppText.displayLarge.c(AppColors.textOnBrand),
                    ),
                  ],
                ),
              ),
              const AppBadge('Pendente de sync', tone: BadgeTone.warning),
            ],
          ),
          Row(
            spacing: 8,
            children: [
              metrica('${s.precisao}%', 'Precisão'),
              metrica('${Mock.ultimaSessaoMelhorSequencia}', 'Sequência'),
            ],
          ),
        ],
      ),
    );
  }
}
