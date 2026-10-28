import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/cpf.dart';
import '../../data/format.dart';
import '../../data/mock_data.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/controls.dart';
import '../../widgets/field.dart';
import '../../widgets/layout.dart';
import 'login_screen.dart';

enum PerfilJogador {
  casual('Casual'),
  iniciante('Iniciante'),
  infantil('Modo infantil');

  const PerfilJogador(this.label);
  final String label;

  static PerfilJogador fromQuery(String? v) =>
      values.firstWhere((p) => p.name == v, orElse: () => casual);
}

/// 1.2 Cadastro (13:259), 1.3 Iniciante (58:1271), 1.4 Modo infantil (58:1373).
/// Uma tela só; a variante é escolhida pelos chips.
class CadastroScreen extends StatefulWidget {
  const CadastroScreen({super.key, this.perfil = PerfilJogador.casual});

  final PerfilJogador perfil;

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  late var _perfil = widget.perfil;
  var _aceito = true;

  // CPF do jogador (Casual/Iniciante) e do responsável (Modo infantil).
  final _cpf = TextEditingController();
  final _cpfResponsavel = TextEditingController();
  var _tentouEnviar = false;

  // Datas de nascimento de exemplo (fictícias).
  var _nascimento = DateTime(1998, 5, 12);
  var _nascimentoInfantil = DateTime(2016, 5, 12);
  late final _nascimentoCtrl = TextEditingController(
    text: fmtData(_nascimento),
  );
  late final _nascimentoInfantilCtrl = TextEditingController(
    text: fmtData(_nascimentoInfantil),
  );

  bool get _infantil => _perfil == PerfilJogador.infantil;

  TextEditingController get _cpfAtual => _infantil ? _cpfResponsavel : _cpf;

  @override
  void dispose() {
    _cpf.dispose();
    _cpfResponsavel.dispose();
    _nascimentoCtrl.dispose();
    _nascimentoInfantilCtrl.dispose();
    super.dispose();
  }

  /// Erro quando o CPF tem 11 dígitos e não confere, ou quando se tentou
  /// criar a conta com ele incompleto.
  bool _cpfErro(TextEditingController c) {
    final d = cpfDigitos(c.text);
    if (d.isEmpty) return false;
    return d.length < 11 ? _tentouEnviar : !cpfValido(d);
  }

  Future<void> _escolherNascimento() async {
    final atual = _infantil ? _nascimentoInfantil : _nascimento;
    final hoje = DateTime.now();
    final data = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(1900),
      lastDate: hoje,
      helpText: 'Data de nascimento',
    );
    if (data == null || !mounted) return;
    setState(() {
      if (_infantil) {
        _nascimentoInfantil = data;
        _nascimentoInfantilCtrl.text = fmtData(data);
      } else {
        _nascimento = data;
        _nascimentoCtrl.text = fmtData(data);
      }
    });
  }

  void _criarConta() {
    setState(() => _tentouEnviar = true);
    // Protótipo: CPF vazio passa (dados de exemplo); preenchido precisa ser válido.
    if (_cpfErro(_cpfAtual)) return;
    context.pushReplacement(Routes.pareamento);
  }

  void _voltar() => goBack(context, Routes.login);

  @override
  Widget build(BuildContext context) {
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
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      Transform.translate(
                        offset: const Offset(-8, 0),
                        child: CircleIconButton(
                          icon: AppIcons.arrowLeft,
                          color: AppColors.iconOnBrand,
                          onTap: _voltar,
                          tooltip: 'Voltar',
                        ),
                      ),
                      Text(
                        'Crie sua conta',
                        style: AppText.headlineM.c(AppColors.textOnBrand),
                      ),
                      Text(
                        _infantil
                            ? 'Um responsável precisa criar a conta do jogador.'
                            : 'Leva menos de 1 minuto para começar a jogar.',
                        style: AppText.bodyM.c(AppColors.textOnBrandMuted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: AuthSheet(
                    gap: 14,
                    children: [
                      Segmented(
                        left: 'Entrar',
                        right: 'Criar conta',
                        leftActive: false,
                        onLeft: _voltar,
                      ),
                      ..._campos(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 8,
                        children: [
                          Text(
                            'Seu perfil de jogador',
                            style: AppText.labelM.c(AppColors.textSecondary),
                          ),
                          ChipBar(
                            labels: [
                              for (final p in PerfilJogador.values) p.label,
                            ],
                            selected: _perfil.index,
                            onSelected: (i) => setState(
                              () => _perfil = PerfilJogador.values[i],
                            ),
                          ),
                        ],
                      ),
                      // Texto do "Modo casual" é provisório: confirmar com o time.
                      if (_perfil == PerfilJogador.casual)
                        const InfoBanner(
                          icon: AppIcons.smile,
                          title: 'Modo casual',
                          body:
                              'Para quem joga por diversão: treinos no ritmo padrão e pontuação normal, sem pressão e sem dicas durante o treino.',
                        ),
                      if (_perfil == PerfilJogador.iniciante)
                        const InfoBanner(
                          icon: AppIcons.smile,
                          title: 'Modo iniciante',
                          body:
                              'Intervalos maiores entre os lances, menos lances por sessão e dicas durante o treino.',
                        ),
                      if (_infantil)
                        const InfoBanner(
                          icon: AppIcons.shield,
                          tone: InfoTone.warning,
                          title: 'Modo infantil',
                          body:
                              'Precisamos do e-mail de um responsável. O apelido nunca é o nome real e o jogador fica fora do ranking global.',
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 12,
                        children: [
                          AppCheckbox(
                            value: _aceito,
                            onChanged: (v) => setState(() => _aceito = v),
                          ),
                          Expanded(
                            child: Text(
                              _infantil
                                  ? 'Sou o responsável e aceito os Termos de Uso e a Política de Privacidade (LGPD).'
                                  : 'Li e aceito os Termos de Uso e a Política de Privacidade (LGPD).',
                              style: AppText.bodyS.c(AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      AppButton('Criar conta', onPressed: _criarConta),
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

  Widget _campoCpf(String label, TextEditingController c, String key) {
    final erro = _cpfErro(c);
    return AppField(
      key: ValueKey(key),
      label: label,
      controller: c,
      placeholder: '000.000.000-00',
      leadingIcon: AppIcons.shield,
      keyboardType: TextInputType.number,
      inputFormatters: [CpfInputFormatter()],
      error: erro,
      helper: erro ? 'CPF inválido. Confira os números.' : null,
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _campoNascimento(TextEditingController c, String key) => AppField(
    key: ValueKey(key),
    label: 'Data de nascimento',
    controller: c,
    leadingIcon: AppIcons.calendar,
    readOnly: true,
    onTap: _escolherNascimento,
  );

  List<Widget> _campos() {
    if (_infantil) {
      return [
        AppField(
          key: const ValueKey('nome-jogador'),
          label: 'Nome do jogador',
          initialValue: Mock.user.nome,
        ),
        AppField(
          key: const ValueKey('apelido-divertido'),
          label: 'Apelido divertido (sem nome real)',
          initialValue: Mock.user.apelido,
        ),
        _campoNascimento(_nascimentoInfantilCtrl, 'nascimento-infantil'),
        _campoCpf('CPF do responsável', _cpfResponsavel, 'cpf-responsavel'),
        const AppField(
          key: ValueKey('email-responsavel'),
          label: 'E-mail do responsável',
          initialValue: 'responsavel@email.com',
          leadingIcon: AppIcons.mail,
          keyboardType: TextInputType.emailAddress,
        ),
        const AppField(
          key: ValueKey('senha-infantil'),
          label: 'Senha',
          initialValue: Mock.senha,
          obscure: true,
        ),
      ];
    }
    return [
      AppField(
        key: const ValueKey('nome'),
        label: 'Nome completo',
        initialValue: Mock.user.nome,
      ),
      AppField(
        key: const ValueKey('apelido'),
        label: 'Apelido (aparece no ranking)',
        initialValue: Mock.user.apelido,
        leadingIcon: AppIcons.star,
      ),
      _campoCpf('CPF', _cpf, 'cpf'),
      _campoNascimento(_nascimentoCtrl, 'nascimento'),
      AppField(
        key: const ValueKey('email'),
        label: 'E-mail',
        initialValue: Mock.user.email,
        leadingIcon: AppIcons.mail,
        keyboardType: TextInputType.emailAddress,
      ),
      const AppField(
        key: ValueKey('senha'),
        label: 'Senha',
        initialValue: Mock.senha,
        obscure: true,
      ),
    ];
  }
}
