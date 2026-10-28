import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/field.dart';
import '../../widgets/layout.dart';

/// Faixas dos sliders de parâmetros de treino. Tempo da sessão =
/// lances × intervalo entre os lances.
abstract final class ParamTreino {
  /// 0–50 lances (40% → 20, 50% → 25).
  static const lancesMax = 50;

  /// 0–10 s (30% → 3 s, 40% → 4 s).
  static const intervaloMax = 10;

  /// Valores padrão de cada nível: (lances, intervalo em s).
  static const padrao = {
    Nivel.facil: (15, 4),
    Nivel.medio: (20, 3),
    Nivel.dificil: (30, 2),
    Nivel.infantil: (10, 5),
  };

  static int lances(double f) => math.max(1, (f * lancesMax).round());
  static int intervalo(double f) => math.max(1, (f * intervaloMax).round());
}

/// Sliders "Quantidade de lances" e "Intervalo entre os lances" + linha
/// "Tempo da sessão" (Novo treino e Edição de treino).
List<Widget> parametrosTreino({
  required int lances,
  required int intervaloS,
  required ValueChanged<int> onLances,
  required ValueChanged<int> onIntervalo,
}) => [
  SliderRow(
    label: 'Quantidade de lances',
    valueText: '$lances',
    fraction: lances / ParamTreino.lancesMax,
    divisions: ParamTreino.lancesMax,
    onChanged: (f) => onLances(ParamTreino.lances(f)),
  ),
  SliderRow(
    label: 'Intervalo entre os lances',
    valueText: '$intervaloS s',
    fraction: intervaloS / ParamTreino.intervaloMax,
    divisions: ParamTreino.intervaloMax,
    onChanged: (f) => onIntervalo(ParamTreino.intervalo(f)),
  ),
  SessionTimeRow(lances: lances, intervaloS: intervaloS),
];

/// 3.4 Novo treino (20:363) e 3.6 Novo treino · Personalizado (101:5516).
///
/// Mudar um slider em relação ao padrão do nível troca o nível para
/// Personalizado (guardando a base, ex.: Médio). Tocar em outro nível
/// restaura os valores padrão dele.
class NovoTreinoScreen extends StatefulWidget {
  const NovoTreinoScreen({super.key});

  @override
  State<NovoTreinoScreen> createState() => _NovoTreinoScreenState();
}

class _NovoTreinoScreenState extends State<NovoTreinoScreen> {
  var _nivel = Nivel.medio;

  /// Nível de onde saíram os valores (base do Personalizado).
  var _base = Nivel.medio;
  var _lances = ParamTreino.padrao[Nivel.medio]!.$1;
  var _intervalo = ParamTreino.padrao[Nivel.medio]!.$2;

  void _escolherNivel(Nivel n) => setState(() {
    if (n == Nivel.personalizado) {
      _nivel = n;
      return;
    }
    _nivel = _base = n;
    final (lances, intervalo) = ParamTreino.padrao[n]!;
    _lances = lances;
    _intervalo = intervalo;
  });

  void _mudar({int? lances, int? intervalo}) => setState(() {
    _lances = lances ?? _lances;
    _intervalo = intervalo ?? _intervalo;
    if (_nivel != Nivel.personalizado &&
        (_lances, _intervalo) != ParamTreino.padrao[_nivel]) {
      _base = _nivel;
      _nivel = Nivel.personalizado;
    }
  });

  @override
  Widget build(BuildContext context) {
    void voltar() => goBack(context, Routes.treinos);
    return StackedScreen(
      title: 'Novo treino',
      onBack: voltar,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      gap: 16,
      children: [
        const AppField(label: 'Nome do treino', initialValue: 'Reação turbo'),
        const AppField(
          label: 'Descrição',
          initialValue: 'Sequência rápida para aquecer',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text('Nível', style: AppText.labelM.c(AppColors.textSecondary)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in Nivel.values)
                  AppChip(
                    n.label,
                    selected: n == _nivel,
                    onTap: () => _escolherNivel(n),
                  ),
              ],
            ),
          ],
        ),
        if (_nivel == Nivel.personalizado)
          InfoBanner(
            icon: AppIcons.sliders,
            title: 'Treino personalizado',
            body:
                'Você mudou os valores do nível ${_base.label}. Este treino será salvo como Personalizado.',
          ),
        SectionCard(
          title: 'Parâmetros do treino',
          gap: 16,
          children: parametrosTreino(
            lances: _lances,
            intervaloS: _intervalo,
            onLances: (v) => _mudar(lances: v),
            onIntervalo: (v) => _mudar(intervalo: v),
          ),
        ),
        const Spacer(),
        AppButton('Salvar treino', onPressed: voltar),
      ],
    );
  }
}
