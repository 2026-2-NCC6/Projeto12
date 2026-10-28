import 'package:flutter/material.dart';

import '../../router.dart';
import '../../state/app_settings.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 6.4 Perfil · Acessibilidade (66:2285).
class AcessibilidadeScreen extends StatefulWidget {
  const AcessibilidadeScreen({super.key});

  @override
  State<AcessibilidadeScreen> createState() => _AcessibilidadeScreenState();
}

class _AcessibilidadeScreenState extends State<AcessibilidadeScreen> {
  var _led = true;
  var _falas = true;
  var _volume = 0.70;
  var _vibracao = true;

  @override
  Widget build(BuildContext context) {
    return StackedScreen(
      title: 'Acessibilidade',
      onBack: () => goBack(context, Routes.perfil),
      children: [
        SectionCard(
          title: 'Sinais do TOBIAS',
          gap: 14,
          children: [
            ToggleRow(
              icon: AppIcons.zap,
              title: 'LED de apoio',
              subtitle: 'Luzes que acompanham cada som',
              value: _led,
              onChanged: (v) => setState(() => _led = v),
            ),
            ToggleRow(
              icon: AppIcons.volume,
              title: 'Falas do TOBIAS',
              subtitle: 'Provocações e incentivos em áudio',
              value: _falas,
              onChanged: (v) => setState(() => _falas = v),
            ),
            SliderRow(
              label: 'Volume das falas',
              valueText: '${(_volume * 100).round()}%',
              fraction: _volume,
              onChanged: (v) => setState(() => _volume = v),
            ),
          ],
        ),
        SectionCard(
          title: 'No celular',
          gap: 14,
          children: [
            ToggleRow(
              icon: AppIcons.activity,
              title: 'Vibração',
              subtitle: 'Vibrar ao iniciar e finalizar a sessão',
              value: _vibracao,
              onChanged: (v) => setState(() => _vibracao = v),
            ),
            Text('Tamanho do texto', style: AppText.labelL),
            ValueListenableBuilder(
              valueListenable: AppSettings.textoGrande,
              builder: (context, grande, _) => Segmented(
                left: 'Padrão',
                right: 'Grande',
                leftActive: !grande,
                onLeft: () => AppSettings.textoGrande.value = false,
                onRight: () => AppSettings.textoGrande.value = true,
              ),
            ),
          ],
        ),
        const NoteRow(
          icon: AppIcons.info,
          text:
              'As escolhas de LED e de voz são enviadas ao TOBIAS por Bluetooth.',
        ),
      ],
    );
  }
}
