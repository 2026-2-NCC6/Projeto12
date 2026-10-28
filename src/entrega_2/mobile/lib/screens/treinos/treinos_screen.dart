import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
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
class TreinosScreen extends StatefulWidget {
  const TreinosScreen({super.key, required this.filtro});

  final FiltroTreinos filtro;

  @override
  State<TreinosScreen> createState() => _TreinosScreenState();
}

class _TreinosScreenState extends State<TreinosScreen> {
  var _busca = '';

  static const _rotas = [
    Routes.treinos,
    Routes.treinosCatalogo,
    Routes.treinosMeus,
  ];

  List<Drill> get _lista => switch (widget.filtro) {
    FiltroTreinos.todos => Mock.treinosTodos,
    FiltroTreinos.catalogo => Mock.treinosCatalogo,
    FiltroTreinos.meus => Mock.treinosMeus,
  };

  @override
  Widget build(BuildContext context) {
    final termo = _busca.trim().toLowerCase();
    final lista = termo.isEmpty
        ? _lista
        : _lista.where((d) => d.titulo.toLowerCase().contains(termo)).toList();

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
                    onTap: () => context.push(Routes.treinosNovo),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
            child: AppField(
              placeholder: 'Buscar treino…',
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          ChipBar(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            labels: const ['Todos', 'Catálogo', 'Meus treinos'],
            selected: widget.filtro.index,
            onSelected: (i) => context.go(_rotas[i]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              itemCount: lista.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final drill = lista[i];
                return DrillCard(
                  drill: drill,
                  // Na aba "Todos", o primeiro treino aparece selecionado.
                  selected:
                      widget.filtro == FiltroTreinos.todos &&
                      drill.id == Mock.reacaoRapida.id,
                  onTap: () => context.push(
                    Uri(
                      path: Routes.treinosEditar,
                      queryParameters: {'id': drill.id},
                    ).toString(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
