import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/layout.dart';

/// 6.7 Perfil · Conta excluída (73:2392).
class ContaExcluidaScreen extends StatelessWidget {
  const ContaExcluidaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: StatusBarStyle(
        light: false,
        child: Scaffold(
          backgroundColor: AppColors.bgApp,
          body: SafeArea(
            child: ScrollFill(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 16,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(
                      color: AppColors.bgBrandSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      AppIcons.checkCircle,
                      size: 48,
                      color: AppColors.iconBrand,
                    ),
                  ),
                  Text(
                    'Conta excluída',
                    textAlign: TextAlign.center,
                    style: AppText.headlineL,
                  ),
                  Text(
                    'Seus dados foram removidos. Sentiremos sua falta! Você pode criar uma nova conta quando quiser.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyL.c(AppColors.textSecondary),
                  ),
                  AppButton(
                    'Voltar ao início',
                    onPressed: () => context.go(Routes.login),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
