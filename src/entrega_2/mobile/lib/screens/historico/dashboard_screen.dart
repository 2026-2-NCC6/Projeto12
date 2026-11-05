import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/dashboard.dart';
import '../../data/fila_sessoes.dart';
import '../../data/format.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/charts.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 5.3 Histórico · Dashboard (49:1289), com os dados do SERVIDOR
/// (`GET /v1/sessions`): agregados de tudo o que ele conhece, sem o teto
/// de dez sessões da fila local. A aba Sessões é que é local e offline.
///
/// Sem rede não há o que mostrar, e a tela NÃO cai para o dado local: daria
/// números diferentes dos da outra aba, sem explicação.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.api,
    this.fila,
    this.lerToken,
    this.agora,
  });

  /// Nos testes: API falsa, fila isolada, token e relógio fixos.
  final ApiClient? api;
  final FilaSessoes? fila;
  final Future<String?> Function()? lerToken;
  final DateTime Function()? agora;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
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
  const _Pronto(this.atual, this.anterior);
  final AgregadoPeriodo atual;

  /// Nulo em "Tudo": não há período anterior.
  final AgregadoPeriodo? anterior;
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  FilaSessoes get _fila => widget.fila ?? FilaSessoes.doApp;
  DateTime _agora() => (widget.agora ?? DateTime.now)();

  var _periodo = PeriodoDashboard.trintaDias;
  _Estado _estado = const _Carregando();

  /// Sessões que ainda não chegaram ao servidor, logo fora dos números.
  var _naoEnviadas = 0;

  /// Descarta a resposta de uma consulta que ficou velha (o chip mudou no
  /// meio, ou outra consulta começou depois).
  var _consulta = 0;

  @override
  void initState() {
    super.initState();
    _fila.alteracoes.addListener(_filaMudou);
    _contarNaoEnviadas();
    _carregar();
  }

  @override
  void dispose() {
    _fila.alteracoes.removeListener(_filaMudou);
    super.dispose();
  }

  /// Pendentes que nunca chegaram ao servidor, mais as separadas por erro.
  /// Uma pendente que já foi enviada uma vez (e recebeu lance depois) está
  /// no servidor, só desatualizada: não conta.
  Future<int> _semServidor() async {
    final pendentes = await _fila.aguardandoEnvio();
    final separadas = await _fila.separadas();
    return pendentes.where((s) => s.pontuacaoServidor == null).length +
        separadas.length;
  }

  Future<void> _contarNaoEnviadas() async {
    final n = await _semServidor();
    if (mounted) setState(() => _naoEnviadas = n);
  }

  /// Um envio terminou: se alguma sessão chegou ao servidor, os números
  /// mudaram, e a consulta é refeita.
  Future<void> _filaMudou() async {
    final antes = _naoEnviadas;
    await _contarNaoEnviadas();
    if (_naoEnviadas < antes && _estado is _Pronto) _carregar();
  }

  Future<void> _carregar() async {
    final consulta = ++_consulta;
    setState(() => _estado = const _Carregando());
    final _Estado novo;
    try {
      novo = await _consultar();
    } on ApiException catch (e) {
      if (mounted && consulta == _consulta) {
        setState(() => _estado = _Erro(e.mensagem));
      }
      return;
    }
    if (mounted && consulta == _consulta) setState(() => _estado = novo);
  }

  Future<_Estado> _consultar() async {
    final token = await (widget.lerToken ?? AuthStore.lerToken)();
    if (token == null) {
      return const _Erro('Entre na sua conta para ver o Dashboard.');
    }
    // A API dorme quando ociosa: a primeira chamada pode levar até ~30 s.
    await _api.acordarApi();

    final j = janelas(_periodo, _agora());
    if (j == null) {
      return _Pronto(agregar(await _api.listarSessoes(token)), null);
    }
    final (atual, anterior) = j;
    final [a, b] = await Future.wait([
      _api.listarSessoes(token, de: atual.de, ate: atual.ate),
      _api.listarSessoes(token, de: anterior.de, ate: anterior.ate),
    ]);
    return _Pronto(agregar(a), agregar(b));
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
            child: Segmented(
              left: 'Sessões',
              right: 'Dashboard',
              leftActive: false,
              onLeft: () => context.go(Routes.historico),
            ),
          ),
          ChipBar(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            labels: [for (final p in PeriodoDashboard.values) p.rotulo],
            selected: _periodo.index,
            onSelected: (i) {
              if (i == _periodo.index) return;
              setState(() => _periodo = PeriodoDashboard.values[i]);
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
              _Pronto(:final atual, :final anterior) => ListView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                children: [
                  if (_naoEnviadas > 0) ...[
                    _AvisoNaoEnviadas(_naoEnviadas),
                    const SizedBox(height: 10),
                  ],
                  if (atual.vazio)
                    _TelaVazia(periodo: _periodo)
                  else ...[
                    _KpiPrincipal(
                      atual: atual,
                      variacao: variacaoPontuacao(atual, anterior),
                    ),
                    const SizedBox(height: 14),
                    _LinhaMetricas(
                      atual: atual,
                      variacaoPts: variacaoPrecisaoPts(atual, anterior),
                      periodo: _periodo,
                    ),
                    const SizedBox(height: 14),
                    _Distribuicao(atual.distribuicao),
                    const SizedBox(height: 14),
                    _Frequencia(frequenciaSemanal(atual.sessoes, _agora())),
                  ],
                ],
              ),
            },
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
          'Não foi possível carregar o Dashboard',
          style: AppText.titleM,
          textAlign: TextAlign.center,
        ),
        Text(
          '$mensagem\nAs suas sessões continuam na aba Sessões.',
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
  const _TelaVazia({required this.periodo});

  final PeriodoDashboard periodo;

  @override
  Widget build(BuildContext context) {
    final texto = switch (periodo) {
      PeriodoDashboard.tudo => 'Você ainda não tem sessões enviadas.',
      _ => 'Nenhuma sessão enviada nos últimos ${periodo.rotulo}.',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 16,
        children: [
          const Icon(AppIcons.activity, size: 40, color: AppColors.iconBrand),
          Text(texto, style: AppText.titleM, textAlign: TextAlign.center),
          AppButton.outline(
            'Nova sessão',
            onPressed: () => context.push(Routes.sessao),
          ),
        ],
      ),
    );
  }
}

/// Discreto: sem isto, a pessoa treina sem rede, abre o Dashboard e não se
/// vê nos números.
class _AvisoNaoEnviadas extends StatelessWidget {
  const _AvisoNaoEnviadas(this.n);

  final int n;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 6,
    children: [
      const Icon(AppIcons.cloudOff, size: 16, color: AppColors.textSecondary),
      Expanded(
        child: Text(
          n == 1
              ? '1 sessão ainda não enviada não está incluída'
              : '$n sessões ainda não enviadas não estão incluídas',
          style: AppText.bodyS.c(AppColors.textSecondary),
        ),
      ),
    ],
  );
}

// ------------------------------------------------------------------ Blocos

/// "+18%", "−5%" ou "0%". Sinal em texto, e não "▲"/"▼": a Roboto do app
/// não tem as setas, e o mesmo formato da comparação do resumo ("+193 em
/// relação à sessão anterior").
String _seta(int v, String sufixo) =>
    v > 0 ? '+$v$sufixo' : (v < 0 ? '−${-v}$sufixo' : '0$sufixo');

class _KpiPrincipal extends StatelessWidget {
  const _KpiPrincipal({required this.atual, required this.variacao});

  final AgregadoPeriodo atual;

  /// Nula em "Tudo" (sem período anterior) ou com base zero: sem selo.
  final int? variacao;

  /// Mais que isso vira fio de cabelo na largura do cartão.
  static const _maxBarras = 40;

  @override
  Widget build(BuildContext context) {
    final todas = atual.sessoes;
    final barras = todas.length > _maxBarras
        ? todas.sublist(todas.length - _maxBarras)
        : todas;
    final maior = barras.fold(1, (m, s) => math.max(m, s.pontuacaoTotal ?? 0));
    final n = todas.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgBrand,
        borderRadius: BorderRadius.circular(AppRadius.r24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pontuação total · $n ${n == 1 ? 'sessão' : 'sessões'}',
                      style: AppText.labelL.c(AppColors.textOnBrandMuted),
                    ),
                    Text(
                      fmtInt(atual.pontuacaoTotal),
                      style: AppText.displayLarge.c(AppColors.textOnBrand),
                    ),
                  ],
                ),
              ),
              if (variacao case final v?)
                AppBadge(
                  _seta(v, '%'),
                  tone: v >= 0 ? BadgeTone.accent : BadgeTone.warning,
                ),
            ],
          ),
          // Uma barra por sessão, em ordem cronológica; a última destacada.
          SizedBox(
            height: 31,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: barras.length > 20 ? 2 : 4,
              children: [
                for (var i = 0; i < barras.length; i++)
                  Expanded(
                    child: Container(
                      height: math.max(
                        4,
                        31 * (barras[i].pontuacaoTotal ?? 0) / maior,
                      ),
                      constraints: const BoxConstraints(maxWidth: 16),
                      decoration: BoxDecoration(
                        color: i == barras.length - 1
                            ? AppColors.bgAccent
                            : AppColors.bgBrandStrong,
                        borderRadius: BorderRadius.circular(AppRadius.r8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (todas.length > _maxBarras)
            Text(
              'Últimas $_maxBarras sessões',
              style: AppText.labelS.c(AppColors.textOnBrandMuted),
            ),
        ],
      ),
    );
  }
}

class _LinhaMetricas extends StatelessWidget {
  const _LinhaMetricas({
    required this.atual,
    required this.variacaoPts,
    required this.periodo,
  });

  final AgregadoPeriodo atual;
  final int? variacaoPts;
  final PeriodoDashboard periodo;

  @override
  Widget build(BuildContext context) {
    final precisao = atual.precisao;

    // Os dois cartões com a mesma estrutura: título no topo, centralizado,
    // e o valor em destaque centralizado no espaço que sobra.
    Widget cartao({required Widget titulo, required Widget valor}) =>
        SurfaceCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: titulo),
              Expanded(child: Center(child: valor)),
            ],
          ),
        );

    // Altura de referência no Figma: 150. IntrinsicHeight iguala os dois
    // cartões e cresce com o texto grande, sem cortar.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 150),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Expanded(
              child: cartao(
                titulo: Text(
                  'Precisão',
                  style: AppText.labelL.c(AppColors.textSecondary),
                ),
                valor: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    ProgressRing(
                      size: 68,
                      fraction: precisao ?? 0,
                      child: Text(
                        precisao == null ? '—' : '${(precisao * 100).round()}%',
                        style: AppText.titleL,
                      ),
                    ),
                    // Em pontos percentuais, não % de %.
                    if (variacaoPts case final v?)
                      Text(
                        '${_seta(v, ' pts')} vs. ${periodo.rotulo} antes',
                        style: AppText.labelS.c(AppColors.textBrand),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: cartao(
                titulo: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    const Icon(
                      AppIcons.flame,
                      size: 16,
                      color: AppColors.iconBrand,
                    ),
                    Flexible(
                      child: Text(
                        'Melhor sequência',
                        style: AppText.labelL.c(AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                valor: Text(
                  '${atual.melhorSequencia}',
                  style: AppText.displayLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Distribuicao extends StatelessWidget {
  const _Distribuicao(this.d);

  final Distribuicao d;

  @override
  Widget build(BuildContext context) {
    final pct = d.porcentagens ?? (0, 0, 0);
    // DISJUNTOS e somam o total: o 1º segmento é "acertos que não foram
    // KO"; o KO é destacado de dentro dos acertos, não somado ao lado.
    final partes = [
      ('Acertos sem KO', d.acertosSemKo, pct.$1, AppColors.bgBrand),
      ('KO', d.kos, pct.$2, AppColors.bgWarning),
      ('Erros', d.erros, pct.$3, AppColors.bgError),
    ];

    return SectionCard(
      gap: 14,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Distribuição dos lances', style: AppText.titleM),
            ),
            Text(
              '${fmtInt(d.total)} lances',
              style: AppText.labelM.c(AppColors.textSecondary),
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.r7),
          child: SizedBox(
            height: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (_, n, _, cor) in partes)
                  if (n > 0)
                    Expanded(
                      flex: n,
                      child: ColoredBox(color: cor),
                    ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (rotulo, _, p, cor) in partes)
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    rotulo,
                    style: AppText.labelM.c(AppColors.textSecondary),
                  ),
                  Text('$p%', style: AppText.labelL),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// Três letras, e não a inicial: com a semana corrida, as iniciais davam
/// "S S D S T Q Q" (três dias diferentes com "S"). Cabe sob o círculo de 36.
const _diasDaSemana = ['Dom', 'Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb'];

class _Frequencia extends StatelessWidget {
  const _Frequencia(this.dias);

  /// Os últimos 7 dias locais, o mais antigo primeiro.
  final List<(DateTime, bool)> dias;

  @override
  Widget build(BuildContext context) {
    final treinados = dias.where((d) => d.$2).length;
    return SectionCard(
      gap: 14,
      children: [
        Row(
          children: [
            Expanded(child: Text('Frequência semanal', style: AppText.titleM)),
            Text(
              '$treinados de 7 dias',
              style: AppText.labelL.c(AppColors.textBrand),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final (i, (dia, ativo)) in dias.indexed)
              Column(
                spacing: 6,
                children: [
                  // Hoje (o último) leva um anel: a janela é corrida e termina
                  // no presente, e o anel é o ponto de ancoragem dela. Vale
                  // para dia treinado ou não; o rótulo fica normal. Todos
                  // reservam o espaço do anel, para continuarem alinhados.
                  Container(
                    key: i == dias.length - 1
                        ? const ValueKey('frequencia-hoje')
                        : null,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 2,
                        color: i == dias.length - 1
                            ? AppColors.bgBrand
                            : Colors.transparent,
                      ),
                    ),
                    child: DayDot(
                      letter: _diasDaSemana[dia.weekday % 7],
                      active: ativo,
                      size: 36,
                      showCheck: true,
                    ),
                  ),
                  Text(
                    _diasDaSemana[dia.weekday % 7],
                    style: AppText.labelM.c(AppColors.textSecondary),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
