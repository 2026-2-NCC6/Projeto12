import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// Ordem dos chips na tela: Evolução · Consistência · Frequência.
enum AbaRanking { evolucao, consistencia, frequencia }

/// 7.1 Ranking (24:1316), 7.2 Evolução (59:1845), 7.3 Frequência (59:1971).
class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key, required this.aba});

  final AbaRanking aba;

  static const _rotas = [
    Routes.rankingEvolucao,
    Routes.ranking,
    Routes.rankingFrequencia,
  ];

  @override
  Widget build(BuildContext context) {
    final (subtitulo, dados) = switch (aba) {
      AbaRanking.consistencia => (
        'Placar semanal por evolução, não por força bruta.',
        Mock.rankingConsistencia,
      ),
      AbaRanking.evolucao => (
        'Quem mais evoluiu nos últimos 30 dias.',
        Mock.rankingEvolucao,
      ),
      AbaRanking.frequencia => (
        'Quem mais treinou nesta semana.',
        Mock.rankingFrequencia,
      ),
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text('Ranking', style: AppText.headlineM),
                Text(
                  subtitulo,
                  style: AppText.bodyM.c(AppColors.textSecondary),
                ),
              ],
            ),
          ),
          ChipBar(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            labels: const ['Evolução', 'Consistência', 'Frequência'],
            selected: aba.index,
            onSelected: (i) => context.go(_rotas[i]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              children: [
                _Podio(podio: dados.podio),
                for (final (i, e) in dados.linhas.indexed) ...[
                  const SizedBox(height: 10),
                  RankRow(posicao: i + 4, entry: e),
                ],
                const SizedBox(height: 10),
                const Row(
                  spacing: 8,
                  children: [
                    Icon(
                      AppIcons.shield,
                      size: 16,
                      color: AppColors.iconDefault,
                    ),
                    Expanded(child: _Nota()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota();

  @override
  Widget build(BuildContext context) => Text(
    'Só apelidos. Menores de idade ficam fora do ranking global por padrão.',
    style: AppText.bodyS.c(AppColors.textSecondary),
  );
}

class _Podio extends StatelessWidget {
  const _Podio({required this.podio});

  /// [1º, 2º, 3º].
  final List<RankEntry> podio;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 10,
      children: [
        Expanded(child: _Degrau(entry: podio[1], altura: 112)),
        Expanded(child: _Degrau(entry: podio[0], altura: 144, primeiro: true)),
        Expanded(child: _Degrau(entry: podio[2], altura: 96)),
      ],
    );
  }
}

class _Degrau extends StatelessWidget {
  const _Degrau({
    required this.entry,
    required this.altura,
    this.primeiro = false,
  });

  final RankEntry entry;
  final double altura;
  final bool primeiro;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: altura),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: primeiro ? AppColors.bgBrand : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.r20),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          if (primeiro)
            const Icon(AppIcons.crown, size: 20, color: AppColors.iconAccent),
          Avatar(
            letter: entry.inicial,
            size: 36,
            background: primeiro
                ? AppColors.bgAccent
                : AppColors.bgTertiarySoft,
            style: AppText.titleM.c(
              primeiro ? AppColors.textOnAccent : AppColors.textBrand,
            ),
          ),
          Text(
            entry.apelido,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.labelL.c(
              primeiro ? AppColors.textOnBrand : AppColors.textPrimary,
            ),
          ),
          Text(
            entry.valor,
            style: AppText.titleM.c(
              primeiro ? AppColors.textOnBrand : AppColors.textBrand,
            ),
          ),
        ],
      ),
    );
  }
}
