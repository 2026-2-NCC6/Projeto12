import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';

/// Estado de "sessão não encontrada": o `uuid_sessao` pedido não está (mais)
/// na fila deste aparelho. Usado pelo resumo e pelo detalhe.
class SessaoNaoEncontrada extends StatelessWidget {
  const SessaoNaoEncontrada({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          Text(
            'Sessão não encontrada neste aparelho.',
            style: AppText.titleM,
            textAlign: TextAlign.center,
          ),
          AppButton(
            'Nova sessão',
            onPressed: () => context.go(Routes.sessao),
          ),
        ],
      ),
    ),
  );
}
