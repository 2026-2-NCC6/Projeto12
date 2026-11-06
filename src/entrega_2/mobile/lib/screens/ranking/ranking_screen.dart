import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/models.dart';
import '../../data/ranking.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 7.1 Ranking (24:1316), com os dados do servidor (`GET /v1/ranking`).
///
/// Abas: Pontos, Frequência e Evolução. A "Consistência" do Figma foi
/// descartada. Os subtítulos dizem o período real de cada métrica.
class RankingScreen extends StatefulWidget {
  const RankingScreen({
    super.key,
    this.aba = MetricaRanking.pontos,
    this.api,
    this.lerToken,
  });

  /// Aba em que a tela abre.
  final MetricaRanking aba;

  /// Nos testes: API falsa e token fixo.
  final ApiClient? api;
  final Future<String?> Function()? lerToken;

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

sealed class _Estado {
  const _Estado();
}

class _Carregando extends _Estado {
  const _Carregando();
}

class _Erro extends _Estado {
  const _Erro(this.mensagem);
  final String mensagem;
}

class _Pronto extends _Estado {
  const _Pronto(this.resposta);
  final RespostaRanking resposta;
}

class _RankingScreenState extends State<RankingScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late var _metrica = widget.aba;
  _Estado _estado = const _Carregando();

  /// Descarta a resposta de uma aba que já não está na tela.
  var _consulta = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final consulta = ++_consulta;
    setState(() => _estado = const _Carregando());
    _Estado novo;
    try {
      novo = await _consultar(_metrica);
    } on ApiException catch (e) {
      novo = _Erro(e.mensagem);
    }
    if (mounted && consulta == _consulta) setState(() => _estado = novo);
  }

  Future<_Estado> _consultar(MetricaRanking metrica) async {
    final token = await (widget.lerToken ?? AuthStore.lerToken)();
    if (token == null) {
      return const _Erro('Entre na sua conta para ver o ranking.');
    }
    // A API dorme quando ociosa: a primeira chamada pode levar até ~30 s.
    await _api.acordarApi();
    return _Pronto(await _api.ranking(token, metrica));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text('Ranking', style: AppText.headlineM),
                Text(
                  _metrica.subtitulo,
                  style: AppText.bodyM.c(AppColors.textSecondary),
                ),
              ],
            ),
          ),
          ChipBar(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
            labels: [for (final m in MetricaRanking.values) m.rotulo],
            selected: _metrica.index,
            onSelected: (i) {
              if (i == _metrica.index) return;
              setState(() => _metrica = MetricaRanking.values[i]);
              _carregar();
            },
          ),
          Expanded(
            child: switch (_estado) {
              _Carregando() => const _TelaCarregando(),
              _Erro(:final mensagem) => _TelaErro(
                mensagem: mensagem,
                onTentarDeNovo: _carregar,
              ),
              _Pronto(:final resposta) => _Classificacao(resposta),
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- Classificação

class _Classificacao extends StatelessWidget {
  const _Classificacao(this.r);

  final RespostaRanking r;

  @override
  Widget build(BuildContext context) {
    final voce = r.voce;
    final podio = r.itens.take(3).toList();
    final resto = r.itens.skip(3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            children: [
              if (r.itens.isEmpty)
                _TelaVazia(r.metrica.semNinguem)
              else ...[
                _Podio(podio: podio, metrica: r.metrica, voce: voce),
                for (final item in resto) ...[
                  const SizedBox(height: 10),
                  _linha(item, r.metrica, voce: item.apelido == voce?.apelido),
                ],
              ],
              const SizedBox(height: 12),
              const Row(
                spacing: 8,
                children: [
                  Icon(AppIcons.shield, size: 16, color: AppColors.iconDefault),
                  Expanded(child: _Nota()),
                ],
              ),
            ],
          ),
        ),
        // A linha de quem usa o app: no lugar dela quando está na lista (acima);
        // fixada aqui quando não está, sem nunca aparecer duas vezes.
        if (voce == null)
          _Rodape(child: _Convite(r.metrica))
        else if (!r.voceNaLista)
          _Rodape(
            child: Column(
              key: const ValueKey('voce-fixado'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 6,
              children: [
                // Dois casos, duas mensagens:
                // - oculto (menor, sem data de nascimento): fora da lista POR
                //   REGRA. O número pode coincidir com o de alguém visível
                //   (é calculado contra os adultos), e sem o aviso parece
                //   defeito;
                // - não oculto: só abaixo dos 20. A pessoa ESTÁ no ranking
                //   público, e dizer que não aparece seria falso.
                // Numa linha própria, com a largura toda: espremido ao lado
                // do valor, quebrava em várias linhas e engolia a lista.
                Text(
                  voce.oculto
                      ? 'Sua posição · você não aparece no ranking público'
                      : 'Sua posição',
                  style: AppText.bodyS.c(AppColors.textSecondary),
                ),
                RankRow(
                  posicao: voce.posicao,
                  entry: RankEntry(
                    apelido: voce.apelido,
                    valor: fmtValorRanking(r.metrica, voce.valor),
                    voce: true,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Widget _linha(ItemRanking item, MetricaRanking metrica, {required bool voce}) =>
    KeyedSubtree(
      key: ValueKey(voce ? 'voce-na-lista' : 'linha-${item.posicao}'),
      child: RankRow(
        posicao: item.posicao,
        entry: RankEntry(
          apelido: item.apelido,
          valor: fmtValorRanking(metrica, item.valor),
          detalhe: voce ? 'Você · ${_sessoes(item.sessoes)}' : _sessoes(item.sessoes),
          voce: voce,
        ),
      ),
    );

String _sessoes(int n) => n == 1 ? '1 sessão' : '$n sessões';

/// Faixa fixa no fim da tela, separada da lista por uma borda.
class _Rodape extends StatelessWidget {
  const _Rodape({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: AppColors.bgApp,
      border: Border(top: BorderSide(color: AppColors.borderDefault)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
      child: child,
    ),
  );
}

/// `voce` nulo: em vez de uma posição vazia, o motivo e o convite.
class _Convite extends StatelessWidget {
  const _Convite(this.metrica);

  final MetricaRanking metrica;

  @override
  Widget build(BuildContext context) {
    final (titulo, texto) = switch (metrica) {
      MetricaRanking.pontos => (
        'Você ainda não pontuou nos últimos 30 dias',
        'Faça uma sessão para aparecer aqui.',
      ),
      MetricaRanking.frequencia => (
        'Você não treinou nos últimos 7 dias',
        'Faça uma sessão para aparecer aqui.',
      ),
      // Na evolução, `voce` nulo também é quem não atinge o mínimo: a regra
      // precisa estar dita, senão a pessoa some sem motivo aparente.
      MetricaRanking.evolucao => (
        'Você ainda não entra na evolução',
        'É preciso ter ao menos 3 sessões nos últimos 30 dias e 3 nos 30 '
            'anteriores para comparar.',
      ),
    };
    return Row(
      key: const ValueKey('convite'),
      spacing: 12,
      children: [
        const Icon(AppIcons.tennisBall, size: 28, color: AppColors.iconBrand),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(titulo, style: AppText.titleM),
              Text(texto, style: AppText.bodyS.c(AppColors.textSecondary)),
            ],
          ),
        ),
        AppButton.outline(
          'Treinar',
          compact: true,
          expand: false, // dentro de uma Row: largura do próprio texto
          onPressed: () => context.push(Routes.sessao),
        ),
      ],
    );
  }
}

class _Nota extends StatelessWidget {
  const _Nota();

  // Transparência sobre uma decisão de privacidade real, não enfeite.
  @override
  Widget build(BuildContext context) => Text(
    'Só apelidos. Menores de idade ficam fora do ranking global por padrão.',
    style: AppText.bodyS.c(AppColors.textSecondary),
  );
}

// ------------------------------------------------------------------- Pódio

class _Podio extends StatelessWidget {
  const _Podio({required this.podio, required this.metrica, this.voce});

  /// [1º, 2º, 3º], podendo ter menos de três.
  final List<ItemRanking> podio;
  final MetricaRanking metrica;
  final ItemRanking? voce;

  @override
  Widget build(BuildContext context) {
    Widget degrau(int i, double altura) => Expanded(
      child: i < podio.length
          ? _Degrau(
              item: podio[i],
              valor: fmtValorRanking(metrica, podio[i].valor),
              altura: altura,
              primeiro: i == 0,
              voce: podio[i].apelido == voce?.apelido,
            )
          : const SizedBox.shrink(),
    );

    // O primeiro ao centro, mais alto.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      spacing: 10,
      children: [degrau(1, 112), degrau(0, 144), degrau(2, 96)],
    );
  }
}

class _Degrau extends StatelessWidget {
  const _Degrau({
    required this.item,
    required this.valor,
    required this.altura,
    this.primeiro = false,
    this.voce = false,
  });

  final ItemRanking item;
  final String valor;
  final double altura;
  final bool primeiro;
  final bool voce;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(voce ? 'voce-no-podio' : 'podio-${item.posicao}'),
      constraints: BoxConstraints(minHeight: altura),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: primeiro ? AppColors.bgBrand : AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.r20),
        boxShadow: AppShadows.card,
        border: voce ? Border.all(color: AppColors.bgAccent, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 2,
        children: [
          if (primeiro)
            const Icon(AppIcons.crown, size: 20, color: AppColors.iconAccent),
          Avatar(
            letter: item.inicial,
            size: 36,
            background: primeiro ? AppColors.bgAccent : AppColors.bgTertiarySoft,
            style: AppText.titleM.c(
              primeiro ? AppColors.textOnAccent : AppColors.textBrand,
            ),
          ),
          Text(
            item.apelido,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.labelL.c(
              primeiro ? AppColors.textOnBrand : AppColors.textPrimary,
            ),
          ),
          Text(
            valor,
            style: AppText.titleM.c(
              primeiro ? AppColors.textOnBrand : AppColors.textBrand,
            ),
          ),
          Text(
            voce ? '${item.posicao}º · você' : '${item.posicao}º',
            style: AppText.labelM.c(
              primeiro ? AppColors.textOnBrandMuted : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- Estados

class _TelaCarregando extends StatelessWidget {
  const _TelaCarregando();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        const CircularProgressIndicator(color: AppColors.bgBrand),
        Text(
          'Carregando… a primeira consulta pode levar até 30 s.',
          style: AppText.bodyS.c(AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _TelaErro extends StatelessWidget {
  const _TelaErro({required this.mensagem, required this.onTentarDeNovo});

  final String mensagem;
  final VoidCallback onTentarDeNovo;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        const Icon(AppIcons.cloudOff, size: 40, color: AppColors.iconBrand),
        Text(
          'Não foi possível carregar o ranking',
          style: AppText.titleM,
          textAlign: TextAlign.center,
        ),
        Text(
          mensagem,
          style: AppText.bodyS.c(AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        AppButton(
          'Tentar de novo',
          icon: AppIcons.refreshCw,
          onPressed: onTentarDeNovo,
        ),
      ],
    ),
  );
}

class _TelaVazia extends StatelessWidget {
  const _TelaVazia(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('ranking-vazio'),
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      spacing: 12,
      children: [
        const Icon(AppIcons.trophy, size: 40, color: AppColors.iconBrand),
        Text(texto, style: AppText.titleM, textAlign: TextAlign.center),
      ],
    ),
  );
}
