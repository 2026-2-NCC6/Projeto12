import 'package:flutter/material.dart';

import '../../data/mock_data.dart';
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
import 'novo_treino_screen.dart';

/// 3.5 Edição de treino (20:643). Catálogo é só leitura: salvar cria uma
/// cópia em "Meus treinos".
class EditarTreinoScreen extends StatefulWidget {
  const EditarTreinoScreen({super.key, this.drillId});

  final String? drillId;

  @override
  State<EditarTreinoScreen> createState() => _EditarTreinoScreenState();
}

class _EditarTreinoScreenState extends State<EditarTreinoScreen> {
  late final Drill _drill = [
    ...Mock.treinosTodos,
    ...Mock.treinosCatalogo,
    ...Mock.treinosMeus,
  ].firstWhere((d) => d.id == widget.drillId, orElse: () => Mock.reacaoRapida);

  late var _lances = _drill.lances;
  late var _intervalo = _drill.intervaloS;
  var _led = true;
  var _falas = true;

  @override
  Widget build(BuildContext context) {
    void voltar() => goBack(context, Routes.treinos);
    final drill = _drill;
    final catalogo = drill.tipo == DrillType.catalogo;
    final origem = catalogo ? drill.titulo : (drill.origem ?? drill.titulo);
    final nomeCopia = catalogo ? '${drill.titulo} (minha)' : drill.titulo;

    return StackedScreen(
      title: 'Editar treino',
      onBack: voltar,
      trailing: CircleIconButton(
        icon: AppIcons.trash,
        tooltip: 'Excluir',
        onTap: voltar,
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      gap: 14,
      children: [
        const InfoBanner(
          icon: AppIcons.copy,
          title: 'Você está editando o treino do catálogo',
          body:
              'Ao salvar, criamos uma cópia só sua em "Meus treinos". O original não muda.',
        ),
        Row(
          spacing: 8,
          children: [
            Text('Origem:', style: AppText.labelM.c(AppColors.textSecondary)),
            Flexible(child: AppBadge('$origem · Catálogo')),
          ],
        ),
        AppField(
          key: ValueKey(drill.id),
          label: 'Nome da sua cópia',
          initialValue: nomeCopia,
        ),
        SectionCard(
          title: 'Parâmetros',
          gap: 16,
          children: [
            ...parametrosTreino(
              lances: _lances,
              intervaloS: _intervalo,
              onLances: (v) => setState(() => _lances = v),
              onIntervalo: (v) => setState(() => _intervalo = v),
            ),
            ToggleRow(
              icon: AppIcons.zap,
              title: 'LED de apoio',
              subtitle: 'Alternativa visual ao som',
              value: _led,
              onChanged: (v) => setState(() => _led = v),
            ),
            ToggleRow(
              icon: AppIcons.volume,
              title: 'Falas do TOBIAS',
              subtitle: 'Provocações e incentivos',
              value: _falas,
              onChanged: (v) => setState(() => _falas = v),
            ),
          ],
        ),
        const Spacer(),
        AppButton('Salvar como meu treino', onPressed: voltar),
        AppButton.outline('Cancelar', onPressed: voltar),
      ],
    );
  }
}
