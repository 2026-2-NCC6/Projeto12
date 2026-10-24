import 'package:flutter/material.dart';

import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 6.3 Perfil · Notificações (66:2158).
class NotificacoesScreen extends StatefulWidget {
  const NotificacoesScreen({super.key});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen> {
  var _lembrar = true;
  // D S T Q Q S S — ativos: segunda, quarta e sexta.
  final _dias = [false, true, false, true, false, true, false];
  var _pendentes = true;
  var _recordes = true;
  var _novosTreinos = false;

  @override
  Widget build(BuildContext context) {
    return StackedScreen(
      title: 'Notificações',
      onBack: () => goBack(context, Routes.perfil),
      children: [
        SectionCard(
          title: 'Lembretes de treino',
          gap: 14,
          children: [
            ToggleRow(
              icon: AppIcons.bell,
              title: 'Lembrar de treinar',
              subtitle: 'Aviso nos dias e horário escolhidos',
              value: _lembrar,
              onChanged: (v) => setState(() => _lembrar = v),
            ),
            Text(
              'Dias da semana',
              style: AppText.labelM.c(AppColors.textSecondary),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 7; i++)
                  DayDot(
                    letter: kWeekLetters[i],
                    active: _dias[i],
                    size: 38,
                    onTap: () => setState(() => _dias[i] = !_dias[i]),
                  ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgSurfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.r12),
              ),
              child: Row(
                spacing: 8,
                children: [
                  const Icon(
                    AppIcons.clock,
                    size: 18,
                    color: AppColors.iconDefault,
                  ),
                  Expanded(
                    child: Text(
                      'Horário do lembrete',
                      style: AppText.bodyM.c(AppColors.textSecondary),
                    ),
                  ),
                  Text('18:30', style: AppText.titleM.c(AppColors.textBrand)),
                ],
              ),
            ),
          ],
        ),
        SectionCard(
          title: 'Avisos do app',
          gap: 14,
          children: [
            ToggleRow(
              icon: AppIcons.cloudUpload,
              title: 'Sessões pendentes de envio',
              subtitle: 'Avisa quando há sessões sem sincronizar',
              value: _pendentes,
              onChanged: (v) => setState(() => _pendentes = v),
            ),
            ToggleRow(
              icon: AppIcons.trophy,
              title: 'Recordes e conquistas',
              subtitle: 'Quando você bater um recorde pessoal',
              value: _recordes,
              onChanged: (v) => setState(() => _recordes = v),
            ),
            ToggleRow(
              icon: AppIcons.target,
              title: 'Novos treinos no catálogo',
              subtitle: 'Quando a equipe publicar um treino',
              value: _novosTreinos,
              onChanged: (v) => setState(() => _novosTreinos = v),
            ),
          ],
        ),
        const NoteRow(
          icon: AppIcons.info,
          text:
              'No Android 13 ou superior, o app pede permissão para enviar notificações.',
        ),
      ],
    );
  }
}
