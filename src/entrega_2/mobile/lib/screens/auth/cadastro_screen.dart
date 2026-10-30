import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_validacao.dart';
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

  // Nome e apelido do jogador (no Modo infantil, os da criança).
  final _nome = TextEditingController();
  final _apelido = TextEditingController();
  final _nomeInfantil = TextEditingController();
  final _apelidoInfantil = TextEditingController();

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

  /// Mensagens abaixo dos campos: validação local ou o erro devolvido pela
  /// API.
  String? _erroNome;
  String? _erroApelido;
  String? _erroNascimento;
  String? _erroEmail;
  String? _erroSenha;
  var _enviando = false;

  bool get _infantil => _perfil == PerfilJogador.infantil;

  TextEditingController get _nomeAtual => _infantil ? _nomeInfantil : _nome;
  TextEditingController get _apelidoAtual =>
      _infantil ? _apelidoInfantil : _apelido;
  DateTime? get _nascimentoAtual => _infantil ? _nascimentoInfantil : _nascimento;
  TextEditingController get _emailAtual => _infantil ? _emailResponsavel : _email;
  TextEditingController get _senhaAtual => _infantil ? _senhaInfantil : _senha;

  @override
  void dispose() {
    _nome.dispose();
    _apelido.dispose();
    _nomeInfantil.dispose();
    _apelidoInfantil.dispose();
    _nascimentoCtrl.dispose();
    _nascimentoInfantilCtrl.dispose();
    _email.dispose();
    _senha.dispose();
    _emailResponsavel.dispose();
    _senhaInfantil.dispose();
    super.dispose();
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
      _erroNascimento = null;
      if (_infantil) {
        _nascimentoInfantil = data;
        _nascimentoInfantilCtrl.text = fmtData(data);
      } else {
        _nascimento = data;
        _nascimentoCtrl.text = fmtData(data);
      }
    });
  }

  /// Valida tudo localmente (marcando todos os campos inválidos de uma vez);
  /// se estiver certo, cadastra na API e volta para o Login, onde o usuário
  /// entra com a conta criada.
  Future<void> _criarConta() async {
    if (_enviando) return;
    final nome = _nomeAtual.text.trim();
    final apelido = _apelidoAtual.text.trim();
    final nascimento = _nascimentoAtual;
    final email = _emailAtual.text.trim();
    final senha = _senhaAtual.text;
    setState(() {
      _erroNome = validarNome(nome);
      _erroApelido = validarApelido(apelido);
      _erroNascimento = validarNascimento(nascimento);
      _erroEmail = validarEmail(email);
      _erroSenha = validarSenhaCadastro(senha);
    });
    if (_erroNome != null ||
        _erroApelido != null ||
        _erroNascimento != null ||
        _erroEmail != null ||
        _erroSenha != null) {
      return;
    }

    setState(() => _enviando = true);
    try {
      await _api.cadastro(
        email: email,
        senha: senha,
        nome: nome,
        apelido: apelido,
        // A tela mostra DD/MM/AAAA; a API espera AAAA-MM-DD.
        dataNascimento: fmtDataIso(nascimento!),
        // Os nomes do enum são os valores da API: casual, iniciante, infantil.
        perfil: _perfil.name,
      );
      if (!mounted) return;
      context.go(Routes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.statusCode == 409) {
          _mostrarConflito(e.mensagem);
        } else {
          _erroSenha = e.mensagem;
        }
      });
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// 409 do cadastro: o `detail` da API diz qual dado já está em uso
  /// ("E-mail ja cadastrado" ou "Apelido ja em uso") e a mensagem vai para o
  /// campo correspondente.
  void _mostrarConflito(String detail) {
    final d = detail.toLowerCase();
    if (d.contains('apelido')) {
      _erroApelido = 'Este apelido já está em uso. Escolha outro.';
    } else if (d.contains('mail')) {
      _erroEmail = 'Este e-mail já está cadastrado.';
    } else {
      _erroEmail = detail;
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

  Widget _campoNascimento(TextEditingController c, String key) => AppField(
    key: ValueKey(key),
    label: 'Data de nascimento',
    controller: c,
    placeholder: 'DD/MM/AAAA',
    leadingIcon: AppIcons.calendar,
    readOnly: true,
    onTap: _escolherNascimento,
    error: _erroNascimento != null,
    helper: _erroNascimento,
  );

  List<Widget> _campos() {
    if (_infantil) {
      return [
        AppField(
          key: const ValueKey('nome-jogador'),
          label: 'Nome do jogador',
          controller: _nomeInfantil,
          placeholder: 'Nome completo da criança',
          error: _erroNome != null,
          helper: _erroNome,
        ),
        AppField(
          key: const ValueKey('apelido-divertido'),
          label: 'Apelido divertido (sem nome real)',
          controller: _apelidoInfantil,
          placeholder: 'Ex.: Raquete Veloz',
          error: _erroApelido != null,
          helper: _erroApelido,
        ),
        _campoNascimento(_nascimentoInfantilCtrl, 'nascimento-infantil'),
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
      AppField(
        key: const ValueKey('nome'),
        label: 'Nome completo',
        controller: _nome,
        placeholder: 'Seu nome completo',
        error: _erroNome != null,
        helper: _erroNome,
      ),
      AppField(
        key: const ValueKey('apelido'),
        label: 'Apelido (aparece no ranking)',
        controller: _apelido,
        placeholder: 'Como você quer aparecer',
        leadingIcon: AppIcons.star,
        error: _erroApelido != null,
        helper: _erroApelido,
      ),
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
