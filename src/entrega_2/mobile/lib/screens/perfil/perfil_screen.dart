import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/format.dart';
import '../../data/mock_data.dart';
import '../../router.dart';
import '../../state/device_state.dart';
import '../../state/profile_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 6.1 Perfil (24:1127).
class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const u = Mock.user;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              spacing: 4,
              children: [
                ValueListenableBuilder(
                  valueListenable: ProfileState.foto,
                  builder: (context, foto, _) => Avatar(
                    letter: u.nome[0],
                    size: 64,
                    style: AppText.headlineL.c(AppColors.textOnBrand),
                    image: foto == null ? null : MemoryImage(foto),
                  ),
                ),
                Text(u.nome, style: AppText.headlineM),
                Text(
                  '@${u.apelido} · ${u.email}',
                  textAlign: TextAlign.center,
                  style: AppText.bodyM.c(AppColors.textSecondary),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 8,
                  children: [
                    AppBadge('Casual', tone: BadgeTone.accent),
                    AppBadge('Iniciante', tone: BadgeTone.brand),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                Row(
                  spacing: 12,
                  children: [
                    const Expanded(
                      child: StatCard(
                        icon: AppIcons.calendar,
                        value: '${Mock.perfilSessoes}',
                        label: 'Sessões',
                      ),
                    ),
                    Expanded(
                      child: StatCard(
                        icon: AppIcons.trophy,
                        value: fmtInt(Mock.perfilRecorde),
                        label: 'Recorde',
                      ),
                    ),
                    const Expanded(
                      child: StatCard(
                        icon: AppIcons.flame,
                        value: '${Mock.perfilSequenciaDias} dias',
                        label: 'Sequência',
                      ),
                    ),
                  ],
                ),
                DeviceCard(
                  title: Mock.deviceName,
                  subtitle:
                      'Calibrado em ${Mock.deviceCalibradoEm} · ref. ${fmtDec(DeviceState.refG.value)} g',
                  badge: 'Conectado',
                  iconBackground: AppColors.bgAccentSoft,
                  iconColor: AppColors.iconBrand,
                ),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SettingsRow(
                        icon: AppIcons.target,
                        title: 'Recalibrar o TOBIAS',
                        subtitle: 'Refaça as 5 batidas de referência',
                        onTap: () => context.push(Routes.perfilRecalibrar),
                      ),
                      SettingsRow(
                        icon: AppIcons.bell,
                        title: 'Notificações',
                        subtitle: 'Lembretes de treino',
                        onTap: () => context.push(Routes.perfilNotificacoes),
                      ),
                      SettingsRow(
                        icon: AppIcons.eye,
                        title: 'Acessibilidade',
                        subtitle: 'LED de apoio e alternativas ao som',
                        onTap: () => context.push(Routes.perfilAcessibilidade),
                      ),
                      SettingsRow(
                        icon: AppIcons.user,
                        title: 'Configurações do perfil',
                        subtitle: 'Apelido, foto e conta',
                        onTap: () => context.push(Routes.perfilConfig),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.go(Routes.login),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          const Icon(
                            AppIcons.logOut,
                            size: 20,
                            color: AppColors.iconError,
                          ),
                          Text(
                            'Sair da conta',
                            style: AppText.button.c(AppColors.textError),
                          ),
                        ],
                      ),
                    ),
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
