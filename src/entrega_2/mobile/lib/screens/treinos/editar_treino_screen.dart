import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/models.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/field.dart';
import '../../widgets/layout.dart';
import 'novo_treino_screen.dart';

/// 3.5 Edição de treino (20:643). O treino vem de `GET /v1/drills/{id}`.
///
/// Treino pessoal: salvar edita o próprio treino (PUT). Treino do catálogo é
/// só leitura: salvar cria uma cópia em "Meus treinos" (POST /copy) e aplica
/// nela os valores da tela (PUT).
class EditarTreinoScreen extends StatefulWidget {
  const EditarTreinoScreen({super.key, this.drillId});

  final String? drillId;

  @override
  State<EditarTreinoScreen> createState() => _EditarTreinoScreenState();
}

class _EditarTreinoScreenState extends State<EditarTreinoScreen> {
  final _api = ApiClient();
  final _nome = TextEditingController();

  /// Treino carregado; nulo enquanto carrega ou se a carga falhou.
  Drill? _drill;
  var _carregando = true;
  String? _erroCarga;
  var _naoEncontrado = false;

  /// Admin também pode excluir treino do catálogo (papel salvo no login).
  var _admin = false;

  var _lances = 0;
  var _intervalo = 0;
  var _falas = true;

  /// Enquanto o usuário não mexe num slider, o valor original exato é que
  /// é enviado (o slider só mostra 1–50 lances e segundos inteiros de 1–10).
  var _mexeuLances = false;
  var _mexeuIntervalo = false;

  String? _erroNome;
  String? _erroLances;
  String? _erroIntervalo;

  /// Erro de salvar ou excluir (rede, 403, 404 ou 422), mostrado acima do
  /// botão. [_erroAoExcluir] diz de qual das duas ações veio.
  String? _erroEnvio;
  var _erroAoExcluir = false;

  /// Salvando ou excluindo: trava todos os botões da tela.
  var _enviando = false;

  /// Id da cópia já criada a partir do catálogo: se o PUT falhar, "tentar de
  /// novo" edita essa cópia em vez de criar outra.
  String? _copiaId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroCarga = null;
      _naoEncontrado = false;
    });

    final id = widget.drillId;
    if (id == null) {
      setState(() {
        _naoEncontrado = true;
        _carregando = false;
      });
      return;
    }

    final token = await AuthStore.lerToken();
    if (!mounted) return;
    if (token == null) return context.go(Routes.login);

    try {
      final drill = await _api.obterTreino(token, id);
      final admin = await AuthStore.ehAdmin();
      if (!mounted) return;
      setState(() {
        _drill = drill;
        _admin = admin;
        _lances = drill.lances;
        _intervalo = (drill.intervaloExatoMs / 1000).round();
        _falas = drill.falasTobias ?? true;
        _nome.text = drill.tipo == DrillType.catalogo
            ? '${drill.titulo} (minha)'
            : drill.titulo;
        _carregando = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) return _sessaoExpirada();
      setState(() {
        _naoEncontrado = e.statusCode == 404;
        _erroCarga = e.mensagem;
        _carregando = false;
      });
    }
  }

  Future<void> _sessaoExpirada() async {
    await AuthStore.limparToken();
    if (mounted) context.go(Routes.login);
  }

  Future<void> _salvar(Drill drill) async {
    if (_enviando) return;
    final titulo = _nome.text.trim();
    final lances = _mexeuLances ? _lances : drill.lances;
    final intervaloMs = _mexeuIntervalo
        ? _intervalo * 1000
        : drill.intervaloExatoMs;
    setState(() {
      _erroNome = validarTituloTreino(titulo);
      _erroLances = validarLances(lances);
      _erroIntervalo = validarIntervaloMs(intervaloMs);
      _erroEnvio = null;
      _erroAoExcluir = false;
    });
    if (_erroNome != null || _erroLances != null || _erroIntervalo != null) {
      return;
    }

    final token = await AuthStore.lerToken();
    if (!mounted) return;
    if (token == null) return context.go(Routes.login);

    // Sem descrição e chips de nível nesta tela: a descrição segue a do
    // treino, e o nível vira Personalizado se os parâmetros mudaram.
    final mudouParametros =
        lances != drill.lances || intervaloMs != drill.intervaloExatoMs;
    final nivel = mudouParametros ? Nivel.personalizado : drill.nivel;

    setState(() => _enviando = true);
    try {
      final id = drill.tipo == DrillType.catalogo
          ? _copiaId ??= (await _api.copiarTreino(token, drill.id)).id
          : drill.id;
      await _api.editarTreino(
        token,
        id,
        titulo: titulo,
        descricao: drill.descricao,
        nivel: nivel,
        qtdLances: lances,
        intervaloMs: intervaloMs,
        falasTobias: _falas,
      );
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) return _sessaoExpirada();
      setState(
        () => _erroEnvio = e.statusCode == 404
            ? 'Este treino não é seu ou não existe mais.'
            : e.mensagem,
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Pede confirmação e exclui o treino (pessoal, ou do catálogo se o
  /// usuário for admin). Com 204, volta para a
  /// listagem devolvendo `true`. Tocar na lixeira de novo após um erro pede
  /// a confirmação outra vez (depois de falha de rede, o usuário não sabe se
  /// a exclusão aconteceu).
  Future<void> _excluir(Drill drill) async {
    if (_enviando) return;
    final confirmou = await _confirmarExclusao(
      context,
      drill.titulo,
      catalogo: drill.tipo == DrillType.catalogo,
    );
    if (confirmou != true || !mounted) return;

    final token = await AuthStore.lerToken();
    if (!mounted) return;
    if (token == null) return context.go(Routes.login);

    setState(() {
      _enviando = true;
      _erroEnvio = null;
      _erroAoExcluir = true;
    });
    try {
      await _api.excluirTreino(token, drill.id);
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) return _sessaoExpirada();
      // O `detail` da API (sem acentos) não é mostrado: texto para o usuário.
      setState(
        () => _erroEnvio = switch (e.statusCode) {
          403 => 'Treinos do catálogo não podem ser excluídos.',
          404 => 'Este treino não é seu ou não existe mais.',
          _ => e.mensagem,
        },
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Se a cópia do catálogo já foi criada (mesmo com o PUT falhando), a
    // listagem precisa recarregar para mostrá-la.
    void voltar() {
      if (_enviando) return;
      _copiaId != null && context.canPop()
          ? context.pop(true)
          : goBack(context, Routes.treinos);
    }

    final drill = _drill;
    if (drill == null) {
      return StackedScreen(
        title: 'Editar treino',
        onBack: voltar,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        children: [
          const Spacer(),
          if (_carregando)
            const Center(
              child: CircularProgressIndicator(color: AppColors.bgBrand),
            )
          else if (_naoEncontrado)
            _Aviso(
              titulo: 'Treino não encontrado',
              texto: 'Ele pode ter sido removido ou não estar disponível.',
              acao: AppButton.outline(
                'Voltar',
                icon: AppIcons.arrowLeft,
                expand: false,
                onPressed: voltar,
              ),
            )
          else
            _Aviso(
              titulo: 'Não foi possível carregar o treino',
              texto: _erroCarga ?? '',
              acao: AppButton.outline(
                'Tentar de novo',
                icon: AppIcons.refreshCw,
                expand: false,
                onPressed: _carregar,
              ),
            ),
          const Spacer(),
        ],
      );
    }

    final catalogo = drill.tipo == DrillType.catalogo;
    return StackedScreen(
      title: 'Editar treino',
      onBack: voltar,
      // Treino pessoal sempre pode ser excluído; do catálogo, só por admin
      // (para o jogador, a ação no catálogo é copiar).
      trailing: catalogo && !_admin
          ? null
          : CircleIconButton(
              icon: AppIcons.trash,
              tooltip: 'Excluir',
              onTap: _enviando ? null : () => _excluir(drill),
            ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      gap: 14,
      children: [
        if (catalogo) ...[
          const InfoBanner(
            icon: AppIcons.copy,
            title: 'Você está editando o treino do catálogo',
            body:
                'Ao salvar, criamos uma cópia só sua em "Meus treinos". O original não muda.',
          ),
          Row(
            spacing: 8,
            children: [
              Text('Origem:', style: AppText.labelM.c(AppColors.textSecondary)),
              Flexible(child: AppBadge('${drill.titulo} · Catálogo')),
            ],
          ),
        ],
        AppField(
          key: ValueKey(drill.id),
          label: catalogo ? 'Nome da sua cópia' : 'Nome do treino',
          controller: _nome,
          error: _erroNome != null,
          helper: _erroNome,
        ),
        SectionCard(
          title: 'Parâmetros',
          gap: 16,
          children: [
            ...parametrosTreino(
              lances: _lances,
              intervaloS: _intervalo,
              onLances: (v) => setState(() {
                _lances = v;
                _mexeuLances = true;
              }),
              onIntervalo: (v) => setState(() {
                _intervalo = v;
                _mexeuIntervalo = true;
              }),
              erroLances: _erroLances,
              erroIntervalo: _erroIntervalo,
            ),
            ToggleRow(
              icon: AppIcons.volume,
              title: 'Falas do TOBIAS',
              subtitle: 'Provocações e incentivos',
              value: _falas,
              onChanged: (v) => setState(() => _falas = v),
            ),
          ],
        ),
        const Spacer(),
        if (_erroEnvio != null)
          InfoBanner(
            icon: AppIcons.alertOctagon,
            tone: InfoTone.warning,
            title: _erroAoExcluir
                ? 'Não foi possível excluir'
                : 'Não foi possível salvar',
            body: _erroAoExcluir
                ? '$_erroEnvio Toque na lixeira para tentar de novo.'
                : '$_erroEnvio Toque em salvar para tentar de novo.',
          ),
        AppButton(
          catalogo ? 'Salvar como meu treino' : 'Salvar alterações',
          onPressed: _enviando ? null : () => _salvar(drill),
        ),
        AppButton.outline('Cancelar', onPressed: _enviando ? null : voltar),
      ],
    );
  }
}

/// Confirmação de exclusão, no padrão visual de 6.6 Perfil · Confirmar
/// exclusão: a opção segura em destaque. Devolve `true` em "Excluir".
Future<bool?> _confirmarExclusao(
  BuildContext context,
  String titulo, {
  required bool catalogo,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: AppColors.overlay,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.bgErrorSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.alertOctagon,
                size: 32,
                color: AppColors.iconError,
              ),
            ),
            Text(
              'Excluir "$titulo"?',
              textAlign: TextAlign.center,
              style: AppText.headlineM,
            ),
            Text(
              catalogo
                  ? 'O treino sai do catálogo para todos os usuários e não pode ser recuperado.'
                  : 'O treino sai de "Meus treinos" e não pode ser recuperado.',
              textAlign: TextAlign.center,
              style: AppText.bodyM.c(AppColors.textSecondary),
            ),
            AppButton(
              'Cancelar',
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            AppButton.danger(
              'Excluir',
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.titulo, required this.texto, required this.acao});

  final String titulo;
  final String texto;
  final Widget acao;

  @override
  Widget build(BuildContext context) {
    return Column(
      spacing: 8,
      children: [
        Text(titulo, style: AppText.titleM, textAlign: TextAlign.center),
        Text(
          texto,
          style: AppText.bodyS.c(AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        acao,
      ],
    );
  }
}
