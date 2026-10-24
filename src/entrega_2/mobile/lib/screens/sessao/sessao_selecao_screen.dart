import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/format.dart';
import '../../data/mock_data.dart';
import '../../router.dart';
import '../../state/device_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 4.1 Sessão · Seleção (21:601).
class SessaoSelecaoScreen extends StatefulWidget {
  const SessaoSelecaoScreen({super.key});

  @override
  State<SessaoSelecaoScreen> createState() => _SessaoSelecaoScreenState();
}

class _SessaoSelecaoScreenState extends State<SessaoSelecaoScreen> {
  var _selecionado = 0;

  /// Começa ligado quando se veio do "Simulador pronto" (2.5).
  var _simulador = DeviceState.simulador.value;

  @override
  Widget build(BuildContext context) {
    const treinos = Mock.treinosTodos;
    return StackedScreen(
      title: 'Nova sessão',
      onBack: () => goBack(context, Routes.treinos),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      gap: 14,
      children: [
        DeviceCard(
          title: '${Mock.deviceName} conectado',
          subtitle:
              'Calibrado · ref. ${fmtDec(DeviceState.refG.value)} g · bateria ${Mock.deviceBateria}%',
          badge: 'Pronto',
        ),
        Text('Escolha o treino', style: AppText.titleM),
        for (var i = 0; i < treinos.length; i++)
          DrillCard(
            drill: treinos[i],
            selected: i == _selecionado,
            onTap: () => setState(() => _selecionado = i),
          ),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modo simulador', style: AppText.titleM),
                  Text(
                    'Eventos de teste. Não conta para o ranking.',
                    style: AppText.bodyS.c(AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            AppSwitch(
              value: _simulador,
              onChanged: (v) {
                setState(() => _simulador = v);
                DeviceState.simulador.value = v;
              },
            ),
          ],
        ),
        const Spacer(),
        AppButton(
          'Iniciar sessão',
          icon: AppIcons.play,
          onPressed: () => context.push(
            Uri(
              path: Routes.sessaoAndamento,
              queryParameters: {'treino': treinos[_selecionado].titulo},
            ).toString(),
          ),
        ),
      ],
    );
  }
}
