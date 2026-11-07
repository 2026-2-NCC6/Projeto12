import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/format.dart';
import '../../data/perfil.dart';
import '../../router.dart';
import '../../state/device_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../transport/device_transport.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 6.1 Perfil (24:1127), com os dados reais.
///
/// A identidade vem do aparelho (guardada no login) e aparece mesmo sem rede;
/// por trás, o `/v1/auth/eu` a atualiza. Só as três estatísticas dependem da
/// rede, e só elas mostram erro: a tela inteira não vira um estado de erro.
class PerfilScreen extends StatefulWidget {
  const PerfilScreen({
    super.key,
    this.api,
    this.lerToken,
    this.lerUsuario,
    this.transport,
    this.agora,
  });

  /// Nos testes: API falsa, token, usuário guardado, transporte e relógio.
  final ApiClient? api;
  final Future<String?> Function()? lerToken;
  final Future<UsuarioApi?> Function()? lerUsuario;
  final DeviceTransport? transport;
  final DateTime Function()? agora;

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

sealed class _Estatisticas {
  const _Estatisticas();
}

class _Carregando extends _Estatisticas {
  const _Carregando();
}

class _Erro extends _Estatisticas {
  const _Erro(this.mensagem);
  final String mensagem;
}

class _Prontas extends _Estatisticas {
  const _Prontas(this.e);
  final EstatisticasPerfil e;
}

class _PerfilScreenState extends State<PerfilScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  Future<String?> _token() => (widget.lerToken ?? AuthStore.lerToken)();
  DateTime _agora() => (widget.agora ?? DateTime.now)();

  UsuarioApi? _usuario;
  var _identidadeCarregada = false;
  _Estatisticas _estatisticas = const _Carregando();
  DeviceStatus? _tobias;

  @override
  void initState() {
    super.initState();
    _carregarIdentidade();
    _carregarEstatisticas();
    (widget.transport ?? DeviceState.transport).status().then((s) {
      if (mounted) setState(() => _tobias = s);
    });
  }

  /// Primeiro o que está guardado (aparece sem rede); depois o `/eu`, que
  /// atualiza a tela e o guardado. Sem rede, fica o guardado, sem aviso.
  Future<void> _carregarIdentidade() async {
    final guardado = await (widget.lerUsuario ?? AuthStore.lerUsuario)();
    if (!mounted) return;
    setState(() {
      _usuario = guardado ?? _usuario;
      _identidadeCarregada = true;
    });
    final token = await _token();
    if (token == null) return;
    try {
      final atual = await _api.eu(token);
      await AuthStore.salvarUsuario(atual);
      if (mounted) setState(() => _usuario = atual);
    } on ApiException {
      // Sem rede: a identidade guardada basta.
    }
  }

  Future<void> _carregarEstatisticas() async {
    setState(() => _estatisticas = const _Carregando());
    _Estatisticas novo;
    try {
      final token = await _token();
      if (token == null) {
        novo = const _Erro('Entre na sua conta para ver suas estatísticas.');
      } else {
        // A API dorme quando ociosa: a primeira chamada pode demorar.
        await _api.acordarApi();
        final r = await _api.todasAsSessoes(token);
        novo = _Prontas(estatisticasPerfil(r.sessoes, r.total, _agora()));
      }
    } on ApiException catch (e) {
      novo = _Erro(e.mensagem);
    }
    if (mounted) setState(() => _estatisticas = novo);
  }

  Future<void> _abrir(String rota) async {
    await context.push(rota);
    // Voltou das configurações ou da recalibração: o guardado pode ter mudado.
    if (mounted) _carregarIdentidade();
  }

  Future<void> _sair() async {
    await AuthStore.limparToken();
    if (mounted) context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final u = _usuario;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: u != null
                ? _Cabecalho(u)
                : _identidadeCarregada
                ? Text(
                    'Não foi possível carregar seus dados.',
                    textAlign: TextAlign.center,
                    style: AppText.bodyM.c(AppColors.textSecondary),
                  )
                : const SizedBox(height: 132),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [
                switch (_estatisticas) {
                  _Carregando() => const _LinhaEstatisticas(null),
                  _Prontas(:final e) => _LinhaEstatisticas(e),
                  _Erro(:final mensagem) => _ErroEstatisticas(
                    mensagem: mensagem,
                    onTentarDeNovo: _carregarEstatisticas,
                  ),
                },
                _CartaoTobias(
                  status: _tobias,
                  usuario: u,
                  agora: _agora(),
                  onCalibrar: () => _abrir(Routes.perfilRecalibrar),
                ),
                SurfaceCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SettingsRow(
                        icon: AppIcons.target,
                        title: 'Recalibrar o TOBIAS',
                        subtitle: 'Refaça as 5 batidas de referência',
                        onTap: () => _abrir(Routes.perfilRecalibrar),
                      ),
                      SettingsRow(
                        icon: AppIcons.user,
                        title: 'Configurações do perfil',
                        subtitle: 'Apelido e conta',
                        onTap: () => _abrir(Routes.perfilConfig),
                      ),
                    ],
                  ),
                ),
                Center(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _sair,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 8,
                        children: [
                          const Icon(AppIcons.logOut, size: 20, color: AppColors.iconError),
                          Text('Sair da conta', style: AppText.button.c(AppColors.textError)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.u);

  final UsuarioApi u;

  @override
  Widget build(BuildContext context) {
    final selo = rotuloPerfil(u.perfil);
    return Column(
      key: const ValueKey('identidade'),
      spacing: 4,
      children: [
        Avatar(
          letter: u.apelido.isEmpty ? '?' : u.apelido[0].toUpperCase(),
          size: 64,
          style: AppText.headlineL.c(AppColors.textOnBrand),
        ),
        Text(u.nome, style: AppText.headlineM, textAlign: TextAlign.center),
        Text(
          '@${u.apelido} · ${u.email}',
          textAlign: TextAlign.center,
          style: AppText.bodyM.c(AppColors.textSecondary),
        ),
        // Só o selo que a API devolve; o Figma mostra dois, mas não há um
        // segundo dado para mostrar.
        if (selo != null) AppBadge(selo, tone: BadgeTone.accent),
      ],
    );
  }
}

class _LinhaEstatisticas extends StatelessWidget {
  const _LinhaEstatisticas(this.e);

  /// Nulo enquanto carrega.
  final EstatisticasPerfil? e;

  @override
  Widget build(BuildContext context) {
    final e = this.e;
    final dias = e?.diasSeguidos;
    return Row(
      key: ValueKey(e == null ? 'estatisticas-carregando' : 'estatisticas'),
      spacing: 12,
      children: [
        Expanded(
          child: StatCard(
            icon: AppIcons.calendar,
            value: e == null ? '…' : '${e.sessoes}',
            label: 'Sessões',
          ),
        ),
        Expanded(
          child: StatCard(
            icon: AppIcons.trophy,
            value: e == null ? '…' : (e.recorde == null ? '—' : fmtInt(e.recorde!)),
            label: 'Recorde',
          ),
        ),
        Expanded(
          child: StatCard(
            icon: AppIcons.flame,
            // Dias seguidos treinando, NÃO a `melhor_sequencia` (acertos
            // seguidos numa sessão). Ver diasSeguidos().
            value: dias == null ? '…' : (dias == 1 ? '1 dia' : '$dias dias'),
            label: 'Sequência',
          ),
        ),
      ],
    );
  }
}

class _ErroEstatisticas extends StatelessWidget {
  const _ErroEstatisticas({required this.mensagem, required this.onTentarDeNovo});

  final String mensagem;
  final VoidCallback onTentarDeNovo;

  @override
  Widget build(BuildContext context) => SurfaceCard(
    key: const ValueKey('estatisticas-erro'),
    child: Row(
      spacing: 12,
      children: [
        const Icon(AppIcons.cloudOff, size: 24, color: AppColors.iconBrand),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text('Estatísticas indisponíveis', style: AppText.titleM),
              Text(mensagem, style: AppText.bodyS.c(AppColors.textSecondary)),
            ],
          ),
        ),
        AppButton.outline(
          'Tentar de novo',
          compact: true,
          expand: false,
          onPressed: onTentarDeNovo,
        ),
      ],
    ),
  );
}

class _CartaoTobias extends StatelessWidget {
  const _CartaoTobias({
    required this.status,
    required this.usuario,
    required this.agora,
    required this.onCalibrar,
  });

  final DeviceStatus? status;
  final UsuarioApi? usuario;
  final DateTime agora;
  final VoidCallback onCalibrar;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final conexao = s == null
        ? '…'
        : s.simulador
        ? 'Simulador'
        : s.conectado
        ? 'Conectado'
        : 'Desconectado';
    final calibracao = textoCalibracao(
      usuario?.calibradoEm,
      usuario?.calibracao ?? 0,
      agora: agora,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        DeviceCard(
          title: s?.nome ?? 'TOBIAS',
          subtitle: calibracao ?? 'Ainda não calibrado',
          badge: conexao,
          iconBackground: AppColors.bgAccentSoft,
          iconColor: AppColors.iconBrand,
        ),
        if (usuario != null && calibracao == null)
          AppButton.outline(
            'Calibrar o TOBIAS',
            icon: AppIcons.target,
            onPressed: onCalibrar,
          ),
      ],
    );
  }
}
