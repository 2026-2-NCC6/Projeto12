import 'dart:async';

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

enum FiltroTreinos { todos, catalogo, meus }

/// 3.1 Treinos (20:477), 3.2 Catálogo (58:1499), 3.3 Meus treinos (58:1722).
///
/// A lista vem de `GET /v1/drills` (só a primeira página).
class TreinosScreen extends StatefulWidget {
  const TreinosScreen({super.key, required this.filtro});

  final FiltroTreinos filtro;

  @override
  State<TreinosScreen> createState() => _TreinosScreenState();
}

class _TreinosScreenState extends State<TreinosScreen> {
  final _api = ApiClient();
  var _busca = '';
  Timer? _esperaBusca;

  /// Treinos recebidos; nulo enquanto a primeira carga do filtro não chega.
  List<Drill>? _itens;
  var _total = 0;
  var _carregando = false;
  String? _erro;

  /// Só a resposta da requisição mais recente é aplicada na tela.
  var _requisicao = 0;

  static const _rotas = [
    Routes.treinos,
    Routes.treinosCatalogo,
    Routes.treinosMeus,
  ];

  /// Valor do parâmetro `escopo` de cada aba ("Todos" não filtra).
  String? get _escopo => switch (widget.filtro) {
    FiltroTreinos.todos => null,
    FiltroTreinos.catalogo => 'catalogo',
    FiltroTreinos.meus => 'pessoal',
  };

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(TreinosScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filtro != widget.filtro) {
      _itens = null;
      _carregar();
    }
  }

  @override
  void dispose() {
    _esperaBusca?.cancel();
    super.dispose();
  }

  /// Espera o usuário parar de digitar antes de buscar na API.
  void _aoBuscar(String valor) {
    _busca = valor;
    _esperaBusca?.cancel();
    _esperaBusca = Timer(const Duration(milliseconds: 400), _carregar);
  }

  Future<void> _carregar() async {
    final requisicao = ++_requisicao;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    final token = await AuthStore.lerToken();
    if (token == null) return _irParaLogin();

    try {
      final pagina = await _api.listarTreinos(
        token,
        escopo: _escopo,
        busca: _busca.trim(),
      );
      if (!mounted || requisicao != _requisicao) return;
      setState(() {
        _itens = pagina.itens;
        _total = pagina.total;
        _carregando = false;
      });
    } on ApiException catch (e) {
      if (!mounted || requisicao != _requisicao) return;
      if (e.statusCode == 401) {
        await AuthStore.limparToken();
        return _irParaLogin();
      }
      setState(() {
        _erro = e.mensagem;
        _carregando = false;
      });
    }
  }

  /// Abre a criação; se um treino foi salvo (a tela devolve `true`),
  /// recarrega a lista para ele aparecer.
  Future<void> _novoTreino() async {
    final criou = await context.push<bool>(Routes.treinosNovo);
    if (criou == true && mounted) _carregar();
  }

  /// Abre a edição; se o treino foi salvo, recarrega a lista.
  Future<void> _editarTreino(String id) async {
    final salvou = await context.push<bool>(
      Uri(path: Routes.treinosEditar, queryParameters: {'id': id}).toString(),
    );
    if (salvou == true && mounted) _carregar();
  }

  void _irParaLogin() {
    if (mounted) context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Treinos', style: AppText.headlineM),
                  CircleIconButton(
                    icon: AppIcons.plus,
                    size: 44,
                    color: AppColors.iconOnBrand,
                    background: AppColors.bgBrand,
                    shadow: AppShadows.raised,
                    tooltip: 'Novo treino',
                    onTap: _novoTreino,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
            child: AppField(
              placeholder: 'Buscar treino…',
              onChanged: _aoBuscar,
            ),
          ),
          ChipBar(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            labels: const ['Todos', 'Catálogo', 'Meus treinos'],
            selected: widget.filtro.index,
            onSelected: (i) => context.go(_rotas[i]),
          ),
          Expanded(child: _conteudo()),
        ],
      ),
    );
  }

  /// Lista, ou um dos estados: carregando, erro de rede ou lista vazia.
  Widget _conteudo() {
    final itens = _itens;
    if (_erro != null) {
      return _Aviso(
        titulo: 'Não foi possível carregar os treinos',
        texto: _erro!,
        acao: AppButton.outline(
          'Tentar de novo',
          icon: AppIcons.refreshCw,
          expand: false,
          onPressed: _carregar,
        ),
      );
    }
    if (itens == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.bgBrand),
      );
    }
    if (itens.isEmpty && !_carregando) {
      return _Aviso(
        titulo: 'Nenhum treino encontrado',
        texto: _busca.trim().isNotEmpty
            ? 'Tente buscar por outro nome.'
            : widget.filtro == FiltroTreinos.meus
            ? 'Toque em + para criar o seu primeiro treino.'
            : 'Ainda não há treinos aqui.',
      );
    }

    // Só a primeira página é carregada: avisa quando há mais treinos.
    final temMais = _total > itens.length;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      itemCount: itens.length + (temMais ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == itens.length) {
          return Text(
            'Mostrando ${itens.length} de $_total treinos',
            textAlign: TextAlign.center,
            style: AppText.labelM.c(AppColors.textSecondary),
          );
        }
        final drill = itens[i];
        return DrillCard(drill: drill, onTap: () => _editarTreino(drill.id));
      },
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.titulo, required this.texto, this.acao});

  final String titulo;
  final String texto;
  final Widget? acao;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Text(titulo, style: AppText.titleM, textAlign: TextAlign.center),
            Text(
              texto,
              style: AppText.bodyS.c(AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (acao != null) ...[const SizedBox(height: 8), acao!],
          ],
        ),
      ),
    );
  }
}
