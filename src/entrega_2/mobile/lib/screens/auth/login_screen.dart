import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/controls.dart';
import '../../widgets/field.dart';
import '../../widgets/layout.dart';

/// 1.1 Login (13:179).
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void criarConta() => context.push(Routes.cadastro);

    return StatusBarStyle(
      light: true,
      child: Scaffold(
        backgroundColor: AppColors.bgBrand,
        body: SafeArea(
          bottom: false,
          child: ScrollFill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.bgAccent,
                          borderRadius: BorderRadius.circular(AppRadius.r20),
                        ),
                        child: const Icon(
                          AppIcons.tennisBall,
                          size: 36,
                          color: AppColors.iconOnAccent,
                        ),
                      ),
                      Text(
                        'TOBIAS',
                        style: AppText.displayLarge.c(AppColors.textOnBrand),
                      ),
                      Text(
                        'Smart Tennis Arena',
                        style: AppText.labelL.c(AppColors.textOnBrandMuted),
                      ),
                      Text(
                        'Bata, ouça e ria. O boneco que implica com você, mas torce por você.',
                        style: AppText.bodyL.c(AppColors.textOnBrandMuted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AuthSheet(
                    gap: 16,
                    children: [
                      Segmented(
                        left: 'Entrar',
                        right: 'Criar conta',
                        leftActive: true,
                        onRight: criarConta,
                      ),
                      AppField(
                        label: 'E-mail',
                        initialValue: Mock.user.email,
                        leadingIcon: AppIcons.mail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const AppField(
                        label: 'Senha',
                        initialValue: Mock.senha,
                        obscure: true,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextLink('Esqueci minha senha', onTap: () {}),
                      ),
                      AppButton(
                        'Entrar',
                        onPressed: () => context.push(Routes.pareamento),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 4,
                        children: [
                          Text(
                            'Novo por aqui?',
                            style: AppText.bodyM.c(AppColors.textSecondary),
                          ),
                          TextLink('Criar conta', onTap: criarConta),
                        ],
                      ),
                      Text(
                        'Ao continuar, você concorda com os Termos de Uso e a Política de Privacidade (LGPD).',
                        textAlign: TextAlign.center,
                        style: AppText.bodyS.c(AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Folha branca com cantos superiores de 28 usada no Login e no Cadastro.
class AuthSheet extends StatelessWidget {
  const AuthSheet({super.key, required this.children, required this.gap});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.r28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: gap,
        children: children,
      ),
    );
  }
}
