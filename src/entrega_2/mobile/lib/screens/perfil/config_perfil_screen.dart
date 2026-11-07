import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/auth_validacao.dart';
import '../../data/fila_sessoes.dart';
import '../../router.dart';
import '../../state/conta_local.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/field.dart';
import '../../widgets/layout.dart';

/// 6.5 Perfil · Configurações do perfil (69:2209).
///
/// O apelido é o único dado editável (`PATCH /v1/auth/eu`). A foto de perfil
/// ficou fora do escopo: sem botões que não levam a nada.
class ConfigPerfilScreen extends StatefulWidget {
  const ConfigPerfilScreen({
    super.key,
    this.api,
    this.lerToken,
    this.lerUsuario,
    this.fila,
  });

  /// Nos testes: API falsa, token, usuário guardado e fila isolada.
  final ApiClient? api;
  final Future<String?> Function()? lerToken;
  final Future<UsuarioApi?> Function()? lerUsuario;
  final FilaSessoes? fila;

  @override
  State<ConfigPerfilScreen> createState() => _ConfigPerfilScreenState();
}

class _ConfigPerfilScreenState extends State<ConfigPerfilScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  final _apelido = TextEditingController();
  UsuarioApi? _usuario;
  String? _erroApelido;
  var _salvando = false;

  @override
  void initState() {
    super.initState();
    (widget.lerUsuario ?? AuthStore.lerUsuario)().then((u) {
      if (!mounted || u == null) return;
      setState(() => _usuario = u);
      _apelido.text = u.apelido;
    });
  }

  @override
  void dispose() {
    _apelido.dispose();
    super.dispose();
  }

  Future<String?> _token() => (widget.lerToken ?? AuthStore.lerToken)();

  Future<void> _salvar() async {
    if (_salvando) return;
    final novo = _apelido.text.trim();
    final invalido = validarApelido(novo);
    if (invalido != null) {
      setState(() => _erroApelido = invalido);
      return;
    }
    if (novo == _usuario?.apelido) {
      goBack(context, Routes.perfil);
      return;
    }
    final token = await _token();
    if (token == null) {
      setState(() => _erroApelido = 'Entre na sua conta de novo para alterar o apelido.');
      return;
    }
    setState(() {
      _salvando = true;
      _erroApelido = null;
    });
    try {
      final atualizado = await _api.editarApelido(token, novo);
      await AuthStore.salvarUsuario(atualizado);
      if (mounted) goBack(context, Routes.perfil);
    } on ApiException catch (e) {
      // Apelido em uso (409) e qualquer outra falha: no campo, não num alerta.
      if (mounted) {
        setState(() {
          _erroApelido = e.statusCode == 409
              ? 'Esse apelido já está em uso. Escolha outro.'
              : e.mensagem;
        });
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _excluir() async {
    final excluida = await showConfirmarExclusao(
      context,
      excluir: (senha) async {
        final token = await _token();
        if (token == null) {
          throw const ApiException('Entre na sua conta de novo para excluir.');
        }
        await _api.excluirConta(token, senha);
        await esquecerContaNoAparelho(fila: widget.fila);
      },
    );
    if (excluida == true && mounted) context.go(Routes.contaExcluida);
  }

  @override
  Widget build(BuildContext context) {
    return StackedScreen(
      title: 'Configurações do perfil',
      onBack: () => goBack(context, Routes.perfil),
      children: [
        SectionCard(
          title: 'Apelido no ranking',
          children: [
            AppField(
              key: const ValueKey('campo-apelido'),
              label: 'Apelido',
              controller: _apelido,
              error: _erroApelido != null,
              helper:
                  _erroApelido ??
                  'É o nome que aparece no ranking. Use um apelido, não seu nome real.',
              onChanged: (_) {
                if (_erroApelido != null) setState(() => _erroApelido = null);
              },
            ),
          ],
        ),
        SectionCard(
          title: 'Excluir conta',
          titleStyle: AppText.titleM.c(AppColors.textError),
          border: Border.all(color: AppColors.borderError, width: 1.5),
          children: [
            Text(
              'Remove sua conta, seu histórico e suas pontuações. Essa ação não pode ser desfeita.',
              style: AppText.bodyM.c(AppColors.textSecondary),
            ),
            AppButton.danger(
              'Excluir minha conta',
              icon: AppIcons.trash,
              onPressed: _excluir,
            ),
          ],
        ),
        const Spacer(),
        AppButton(
          _salvando ? 'Salvando…' : 'Salvar alterações',
          onPressed: _salvando ? null : _salvar,
        ),
      ],
    );
  }
}

/// 6.6 Perfil · Confirmar exclusão (73:2347), com o campo de senha que o
/// endpoint exige. Devolve `true` se a conta foi excluída.
///
/// [excluir] chama a API e limpa o aparelho; um [ApiException] dele vira a
/// mensagem do diálogo (senha errada, sem rede), que fica aberto.
Future<bool?> showConfirmarExclusao(
  BuildContext context, {
  required Future<void> Function(String senha) excluir,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: AppColors.overlay,
    builder: (_) => _DialogoExclusao(excluir: excluir),
  );
}

class _DialogoExclusao extends StatefulWidget {
  const _DialogoExclusao({required this.excluir});

  final Future<void> Function(String senha) excluir;

  @override
  State<_DialogoExclusao> createState() => _DialogoExclusaoState();
}

class _DialogoExclusaoState extends State<_DialogoExclusao> {
  final _senha = TextEditingController();
  String? _erro;
  var _enviando = false;

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (_enviando) return;
    final senha = _senha.text;
    if (senha.isEmpty) {
      // Sem senha, nem chama a API.
      setState(() => _erro = 'Digite sua senha para confirmar.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      await widget.excluir(senha);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _erro = e.statusCode == 401 ? 'Senha incorreta.' : e.mensagem;
          _enviando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.bgErrorSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(AppIcons.alertOctagon, size: 32, color: AppColors.iconError),
              ),
            ),
            Text('Excluir sua conta?', textAlign: TextAlign.center, style: AppText.headlineM),
            Text(
              'Todo o seu histórico, suas pontuações e as sessões salvas serão apagados para sempre. Você não poderá recuperar nada depois.',
              textAlign: TextAlign.center,
              style: AppText.bodyM.c(AppColors.textSecondary),
            ),
            AppField(
              key: const ValueKey('campo-senha-exclusao'),
              label: 'Sua senha, para confirmar',
              controller: _senha,
              obscure: true,
              error: _erro != null,
              helper: _erro,
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
            ),
            AppButton(
              'Não, manter minha conta',
              onPressed: _enviando ? null : () => Navigator.of(context).pop(false),
            ),
            AppButton.danger(
              _enviando ? 'Excluindo…' : 'Sim, excluir',
              onPressed: _enviando ? null : _confirmar,
            ),
          ],
        ),
      ),
    );
  }
}
