import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/ranking.dart';
import 'screens/auth/cadastro_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/connect/calibracao_screen.dart';
import 'screens/connect/pareamento_screen.dart';
import 'screens/historico/dashboard_screen.dart';
import 'screens/historico/detalhe_screen.dart';
import 'screens/historico/historico_screen.dart';
import 'screens/perfil/acessibilidade_screen.dart';
import 'screens/perfil/config_perfil_screen.dart';
import 'screens/perfil/conta_excluida_screen.dart';
import 'screens/perfil/notificacoes_screen.dart';
import 'screens/perfil/perfil_screen.dart';
import 'screens/ranking/ranking_screen.dart';
import 'screens/sessao/em_andamento_screen.dart';
import 'screens/sessao/resumo_screen.dart';
import 'screens/sessao/sessao_selecao_screen.dart';
import 'screens/treinos/editar_treino_screen.dart';
import 'screens/treinos/novo_treino_screen.dart';
import 'screens/treinos/treinos_screen.dart';
import 'state/sessao_ativa.dart';
import 'theme/app_colors.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/layout.dart';

abstract final class Routes {
  static const login = '/login';
  static const cadastro = '/cadastro';
  static const pareamento = '/pareamento';
  static const calibracao = '/calibracao';

  // Abas (com BottomNav)
  static const treinos = '/treinos';
  static const treinosCatalogo = '/treinos/catalogo';
  static const treinosMeus = '/treinos/meus';
  static const historico = '/historico';
  static const historicoDashboard = '/historico/dashboard';
  static const ranking = '/ranking';
  static const rankingEvolucao = '/ranking/evolucao';
  static const rankingFrequencia = '/ranking/frequencia';
  static const perfil = '/perfil';

  // Telas empilhadas (sem BottomNav)
  static const treinosNovo = '/treinos/novo';
  static const treinosEditar = '/treinos/editar';
  static const sessao = '/sessao';
  static const sessaoAndamento = '/sessao/andamento';
  static const sessaoResumo = '/sessao/resumo';
  static const historicoDetalhe = '/historico/detalhe';
  static const perfilRecalibrar = '/perfil/recalibrar';
  static const perfilNotificacoes = '/perfil/notificacoes';
  static const perfilAcessibilidade = '/perfil/acessibilidade';
  static const perfilConfig = '/perfil/config';
  static const contaExcluida = '/perfil/conta-excluida';
}

/// Cria o roteador do app. [initialLocation] permite abrir direto numa tela
/// (útil em testes).
GoRouter createRouter({String initialLocation = Routes.login}) {
  final rootKey = GlobalKey<NavigatorState>();

  GoRoute stacked(String path, Widget Function(GoRouterState s) build) =>
      GoRoute(
        path: path,
        parentNavigatorKey: rootKey,
        builder: (context, state) => build(state),
      );

  GoRoute tab(String path, Widget child) => GoRoute(
    path: path,
    pageBuilder: (context, state) =>
        NoTransitionPage(key: state.pageKey, child: child),
  );

  String? q(GoRouterState s, String key) => s.uri.queryParameters[key];

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: initialLocation,
    routes: [
      // 1 · Login e Cadastro / 2 · Conectar
      stacked(Routes.login, (_) => const LoginScreen()),
      stacked(
        Routes.cadastro,
        (s) => CadastroScreen(perfil: PerfilJogador.fromQuery(q(s, 'perfil'))),
      ),
      stacked(
        Routes.pareamento,
        (s) => PareamentoScreen(
          estadoInicial: EstadoPareamento.fromQuery(q(s, 'estado')),
        ),
      ),
      stacked(Routes.calibracao, (_) => const CalibracaoScreen()),

      // Telas empilhadas acima das abas (listadas antes do Shell para que
      // "/treinos/novo" etc. não sejam confundidas com as abas).
      stacked(Routes.treinosNovo, (_) => const NovoTreinoScreen()),
      stacked(
        Routes.treinosEditar,
        (s) => EditarTreinoScreen(drillId: q(s, 'id')),
      ),
      stacked(Routes.sessao, (_) => const SessaoSelecaoScreen()),
      GoRoute(
        path: Routes.sessaoAndamento,
        parentNavigatorKey: rootKey,
        // A sessão congelada chega em `extra`, vinda da Seleção. Sem ela
        // (link direto, app restaurado) não há o que treinar: volta para
        // a escolha do treino em vez de inventar um.
        redirect: (context, state) =>
            state.extra is SessaoAtiva ? null : Routes.sessao,
        builder: (context, state) =>
            EmAndamentoScreen(sessao: state.extra! as SessaoAtiva),
      ),
      stacked(
        Routes.sessaoResumo,
        (s) => ResumoScreen(
          uuidSessao: q(s, 'sessao'),
          treino: q(s, 'treino') ?? '',
        ),
      ),
      stacked(
        Routes.historicoDetalhe,
        (s) => DetalheScreen(uuidSessao: q(s, 'sessao')),
      ),
      stacked(
        Routes.perfilRecalibrar,
        (_) => const CalibracaoScreen(recalibrar: true),
      ),
      stacked(Routes.perfilNotificacoes, (_) => const NotificacoesScreen()),
      stacked(Routes.perfilAcessibilidade, (_) => const AcessibilidadeScreen()),
      stacked(Routes.perfilConfig, (_) => const ConfigPerfilScreen()),
      stacked(Routes.contaExcluida, (_) => const ContaExcluidaScreen()),

      // Abas com BottomNav
      ShellRoute(
        builder: (context, state, child) =>
            TabShell(location: state.uri.path, child: child),
        routes: [
          tab(Routes.treinos, const TreinosScreen(filtro: FiltroTreinos.todos)),
          tab(
            Routes.treinosCatalogo,
            const TreinosScreen(filtro: FiltroTreinos.catalogo),
          ),
          tab(
            Routes.treinosMeus,
            const TreinosScreen(filtro: FiltroTreinos.meus),
          ),
          tab(Routes.historico, const HistoricoScreen()),
          tab(Routes.historicoDashboard, const DashboardScreen()),
          // /ranking abre em Pontos; as outras duas rotas abrem direto na aba.
          // Dentro da tela, os chips trocam de aba sem navegar.
          tab(Routes.ranking, const RankingScreen()),
          tab(
            Routes.rankingFrequencia,
            const RankingScreen(aba: MetricaRanking.frequencia),
          ),
          tab(
            Routes.rankingEvolucao,
            const RankingScreen(aba: MetricaRanking.evolucao),
          ),
          tab(Routes.perfil, const PerfilScreen()),
        ],
      ),
    ],
  );
}

/// Moldura das telas de aba: fundo `bg/app` + BottomNav fixa embaixo.
class TabShell extends StatelessWidget {
  const TabShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  AppTab get _active {
    if (location.startsWith(Routes.historico)) return AppTab.historico;
    if (location.startsWith(Routes.ranking)) return AppTab.ranking;
    if (location.startsWith(Routes.perfil)) return AppTab.perfil;
    return AppTab.treinos;
  }

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle(
      light: false,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        body: child,
        bottomNavigationBar: BottomNav(
          active: _active,
          onTap: (tab) => switch (tab) {
            AppTab.treinos => context.go(Routes.treinos),
            // "Sessão" abre a Sessão · Seleção por cima das abas.
            AppTab.sessao => context.push(Routes.sessao),
            AppTab.historico => context.go(Routes.historico),
            AppTab.ranking => context.go(Routes.ranking),
            AppTab.perfil => context.go(Routes.perfil),
          },
        ),
      ),
    );
  }
}
