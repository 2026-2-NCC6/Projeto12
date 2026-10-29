import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_validacao.dart';
import '../../data/cpf.dart';
import '../../data/format.dart';
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

  // Datas de nascimento: começam vazias (nulas) até o usuário escolher.
  DateTime? _nascimento;
  DateTime? _nascimentoInfantil;
  final _nascimentoCtrl = TextEditingController();
  final _nascimentoInfantilCtrl = TextEditingController();

  // E-mail e senha enviados à API (no Modo infantil, os do responsável).
  final _email = TextEditingController();
  final _senha = TextEditingController();
  final _emailResponsavel = TextEditingController();
  final _senhaInfantil = TextEditingController();

  final _api = ApiClient();

  /// Mensagens abaixo dos campos E-mail e Senha: validação local ou o erro
  /// devolvido pela API.
  String? _erroEmail;
  String? _erroSenha;
  var _enviando = false;

  bool get _infantil => _perfil == PerfilJogador.infantil;

  TextEditingController get _cpfAtual => _infantil ? _cpfResponsavel : _cpf;
  TextEditingController get _emailAtual => _infantil ? _emailResponsavel : _email;
  TextEditingController get _senhaAtual => _infantil ? _senhaInfantil : _senha;

  @override
  void dispose() {
    _cpf.dispose();
    _cpfResponsavel.dispose();
    _nascimentoCtrl.dispose();
    _nascimentoInfantilCtrl.dispose();
    _email.dispose();
    _senha.dispose();
    _emailResponsavel.dispose();
    _senhaInfantil.dispose();
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
    // Sem data escolhida, o calendário abre num ano plausível para o perfil.
    final atual = _infantil
        ? _nascimentoInfantil ?? DateTime(2016, 1, 1)
        : _nascimento ?? DateTime(2000, 1, 1);
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

  /// Valida tudo localmente (CPF, e-mail e senha, marcando todos os campos
  /// inválidos de uma vez); se estiver certo, cadastra na API (só e-mail e
  /// senha) e volta para o Login, onde o usuário entra com a conta criada.
  Future<void> _criarConta() async {
    if (_enviando) return;
    final email = _emailAtual.text.trim();
    final senha = _senhaAtual.text;
    final erroEmail = validarEmail(email);
    final erroSenha = validarSenhaCadastro(senha);
    setState(() {
      _tentouEnviar = true;
      _erroEmail = erroEmail;
      _erroSenha = erroSenha;
    });
    // Protótipo: CPF vazio passa (dados de exemplo); preenchido precisa ser válido.
    if (_cpfErro(_cpfAtual) || erroEmail != null || erroSenha != null) return;

    setState(() => _enviando = true);
    try {
      await _api.cadastro(email, senha);
      if (!mounted) return;
      context.go(Routes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      // 409 = e-mail já cadastrado: a mensagem vai para o campo E-mail.
      setState(() {
        if (e.statusCode == 409) {
          _erroEmail = e.mensagem;
        } else {
          _erroSenha = e.mensagem;
        }
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
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
    placeholder: 'DD/MM/AAAA',
    leadingIcon: AppIcons.calendar,
    readOnly: true,
    onTap: _escolherNascimento,
  );

  List<Widget> _campos() {
    if (_infantil) {
      return [
        const AppField(
          key: ValueKey('nome-jogador'),
          label: 'Nome do jogador',
          placeholder: 'Nome completo da criança',
        ),
        const AppField(
          key: ValueKey('apelido-divertido'),
          label: 'Apelido divertido (sem nome real)',
          placeholder: 'Ex.: Raquete Veloz',
        ),
        _campoNascimento(_nascimentoInfantilCtrl, 'nascimento-infantil'),
        _campoCpf('CPF do responsável', _cpfResponsavel, 'cpf-responsavel'),
        AppField(
          key: const ValueKey('email-responsavel'),
          label: 'E-mail do responsável',
          controller: _emailResponsavel,
          placeholder: 'responsavel@email.com',
          leadingIcon: AppIcons.mail,
          keyboardType: TextInputType.emailAddress,
          error: _erroEmail != null,
          helper: _erroEmail,
        ),
        AppField(
          key: const ValueKey('senha-infantil'),
          label: 'Senha',
          controller: _senhaInfantil,
          placeholder: 'Mínimo de 8 caracteres',
          obscure: true,
          error: _erroSenha != null,
          helper: _erroSenha,
        ),
      ];
    }
    return [
      const AppField(
        key: ValueKey('nome'),
        label: 'Nome completo',
        placeholder: 'Seu nome completo',
      ),
      const AppField(
        key: ValueKey('apelido'),
        label: 'Apelido (aparece no ranking)',
        placeholder: 'Como você quer aparecer',
        leadingIcon: AppIcons.star,
      ),
      _campoCpf('CPF', _cpf, 'cpf'),
      _campoNascimento(_nascimentoCtrl, 'nascimento'),
      AppField(
        key: const ValueKey('email'),
        label: 'E-mail',
        controller: _email,
        placeholder: 'seu@email.com',
        leadingIcon: AppIcons.mail,
        keyboardType: TextInputType.emailAddress,
        error: _erroEmail != null,
        helper: _erroEmail,
      ),
      AppField(
        key: const ValueKey('senha'),
        label: 'Senha',
        controller: _senha,
        placeholder: 'Mínimo de 8 caracteres',
        obscure: true,
        error: _erroSenha != null,
        helper: _erroSenha,
      ),
    ];
  }
}
