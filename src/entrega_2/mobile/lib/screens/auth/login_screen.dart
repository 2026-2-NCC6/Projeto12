import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/auth_validacao.dart';
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
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _api = ApiClient();

  /// Mensagens abaixo de cada campo: validação local ou, na senha, o erro
  /// devolvido pela API.
  String? _erroEmail;
  String? _erroSenha;

  /// 401: a API não diz qual campo está errado, então os dois ficam com
  /// borda de erro (a mensagem continua só abaixo da senha).
  var _credenciaisInvalidas = false;
  var _enviando = false;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  /// Valida localmente; se tudo estiver certo, faz login na API, salva o
  /// token e segue para o pareamento.
  Future<void> _entrar() async {
    if (_enviando) return;
    final email = _email.text.trim();
    final senha = _senha.text;
    final erroEmail = validarEmail(email);
    final erroSenha = validarSenhaLogin(senha);
    setState(() {
      _erroEmail = erroEmail;
      _erroSenha = erroSenha;
      _credenciaisInvalidas = false;
    });
    if (erroEmail != null || erroSenha != null) return;

    setState(() => _enviando = true);
    try {
      final token = await _api.login(email, senha);
      await AuthStore.salvarToken(token);
      if (!mounted) return;
      context.push(Routes.pareamento);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _erroSenha = e.mensagem;
          _credenciaisInvalidas = e.statusCode == 401;
        });
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

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
                        controller: _email,
                        leadingIcon: AppIcons.mail,
                        keyboardType: TextInputType.emailAddress,
                        error: _erroEmail != null || _credenciaisInvalidas,
                        helper: _erroEmail,
                      ),
                      AppField(
                        label: 'Senha',
                        controller: _senha,
                        obscure: true,
                        error: _erroSenha != null,
                        helper: _erroSenha,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextLink('Esqueci minha senha', onTap: () {}),
                      ),
                      AppButton(
                        'Entrar',
                        onPressed: _entrar,
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
