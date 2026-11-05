import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/format.dart';
import '../../data/models.dart';
import '../../router.dart';
import '../../state/device_state.dart';
import '../../state/sessao_ativa.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../transport/device_transport.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/layout.dart';

/// 4.1 Sessão · Seleção (21:601). Os treinos vêm de `GET /v1/drills`
/// (catálogo + pessoais), com a versão atual de cada um.
class SessaoSelecaoScreen extends StatefulWidget {
  const SessaoSelecaoScreen({super.key});

  @override
  State<SessaoSelecaoScreen> createState() => _SessaoSelecaoScreenState();
}

class _SessaoSelecaoScreenState extends State<SessaoSelecaoScreen> {
  final _api = ApiClient();

  /// Nulo enquanto a lista não chega.
  List<Drill>? _treinos;
  String? _erro;
  var _selecionado = 0;

  /// Começa ligado quando se veio do "Simulador pronto" (2.5).
  var _simulador = DeviceState.simulador.value;

  late Future<DeviceStatus> _status = DeviceState.transport.status();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _treinos = null;
      _erro = null;
    });

    final token = await AuthStore.lerToken();
    if (token == null) return _irParaLogin();

    try {
      // 100 é o máximo por página da API; mais que isso não cabe na escolha.
      final pagina = await _api.listarTreinos(token, limit: 100);
      if (!mounted) return;
      setState(() {
        // Só treinos com versão publicada podem virar sessão.
        _treinos = [
          for (final t in pagina.itens)
            if (t.versaoId != null) t,
        ];
        _selecionado = 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        await AuthStore.limparToken();
        return _irParaLogin();
      }
      setState(() => _erro = e.mensagem);
    }
  }

  void _irParaLogin() {
    if (mounted) context.go(Routes.login);
  }

  void _iniciar(Drill treino) {
    // Congela aqui, uma vez: versão, lances, intervalo e dificuldade.
    final sessao = SessaoAtiva.iniciar(
      treino,
      dificuldade: DeviceState.calibracao.value,
    );
    context.push(Routes.sessaoAndamento, extra: sessao);
  }

  @override
  Widget build(BuildContext context) {
    final treinos = _treinos;
    return StackedScreen(
      title: 'Nova sessão',
      onBack: () => goBack(context, Routes.treinos),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      gap: 14,
      children: [
        FutureBuilder<DeviceStatus>(
          future: _status,
          builder: (context, snap) {
            final s = snap.data;
            return DeviceCard(
              title: s == null
                  ? 'TOBIAS'
                  : s.conectado
                  ? '${s.nome} conectado'
                  : '${s.nome} desconectado',
              subtitle:
                  'Calibrado · ref. ${fmtDec(DeviceState.refG.value)} g'
                  '${s == null ? '' : ' · bateria ${s.bateria}%'}',
              badge: s?.conectado == true ? 'Pronto' : '—',
            );
          },
        ),
        Text('Escolha o treino', style: AppText.titleM),
        ..._lista(treinos),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Modo simulador', style: AppText.titleM),
                  Text(
                    'Eventos de teste. Não conta para o ranking.',
                    style: AppText.bodyS.c(AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            AppSwitch(
              value: _simulador,
              onChanged: (v) {
                setState(() {
                  _simulador = v;
                  DeviceState.simulador.value = v;
                  _status = DeviceState.transport.status();
                });
              },
            ),
          ],
        ),
        const Spacer(),
        AppButton(
          'Iniciar sessão',
          icon: AppIcons.play,
          onPressed: treinos == null || treinos.isEmpty
              ? null
              : () => _iniciar(treinos[_selecionado]),
        ),
      ],
    );
  }

  /// Os cartões, ou um dos estados: carregando, erro ou lista vazia.
  List<Widget> _lista(List<Drill>? treinos) {
    if (_erro != null) {
      return [
        Text(
          'Não foi possível carregar os treinos. $_erro',
          style: AppText.bodyM.c(AppColors.textSecondary),
        ),
        AppButton.outline(
          'Tentar de novo',
          icon: AppIcons.refreshCw,
          expand: false,
          onPressed: _carregar,
        ),
      ];
    }
    if (treinos == null) {
      return const [
        Center(child: CircularProgressIndicator(color: AppColors.bgBrand)),
      ];
    }
    if (treinos.isEmpty) {
      return [
        Text(
          'Nenhum treino disponível. Crie um em Treinos.',
          style: AppText.bodyM.c(AppColors.textSecondary),
        ),
      ];
    }
    return [
      for (var i = 0; i < treinos.length; i++)
        DrillCard(
          drill: treinos[i],
          selected: i == _selecionado,
          onTap: () => setState(() => _selecionado = i),
        ),
    ];
  }
}
