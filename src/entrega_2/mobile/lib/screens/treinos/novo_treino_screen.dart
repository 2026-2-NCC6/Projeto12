import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api_client.dart';
import '../../data/auth_store.dart';
import '../../data/models.dart';
import '../../router.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../widgets/buttons.dart';
import '../../widgets/cards.dart';
import '../../widgets/controls.dart';
import '../../widgets/field.dart';
import '../../widgets/layout.dart';

/// Faixas dos sliders de parâmetros de treino. Tempo da sessão =
/// lances × intervalo entre os lances.
abstract final class ParamTreino {
  /// 0–50 lances (40% → 20, 50% → 25).
  static const lancesMax = 50;

  /// 0–10 s (30% → 3 s, 40% → 4 s).
  static const intervaloMax = 10;

  /// Valores padrão de cada nível: (lances, intervalo em s).
  static const padrao = {
    Nivel.facil: (15, 4),
    Nivel.medio: (20, 3),
    Nivel.dificil: (30, 2),
    Nivel.infantil: (10, 5),
  };

  static int lances(double f) => math.max(1, (f * lancesMax).round());
  static int intervalo(double f) => math.max(1, (f * intervaloMax).round());
}

/// Sliders "Quantidade de lances" e "Intervalo entre os lances" + linha
/// "Tempo da sessão" (Novo treino e Edição de treino). [erroLances] e
/// [erroIntervalo] aparecem abaixo do slider correspondente.
List<Widget> parametrosTreino({
  required int lances,
  required int intervaloS,
  required ValueChanged<int> onLances,
  required ValueChanged<int> onIntervalo,
  String? erroLances,
  String? erroIntervalo,
}) => [
  SliderRow(
    label: 'Quantidade de lances',
    valueText: '$lances',
    fraction: lances / ParamTreino.lancesMax,
    divisions: ParamTreino.lancesMax,
    onChanged: (f) => onLances(ParamTreino.lances(f)),
  ),
  if (erroLances != null) _ErroParametro(erroLances),
  SliderRow(
    label: 'Intervalo entre os lances',
    valueText: '$intervaloS s',
    fraction: intervaloS / ParamTreino.intervaloMax,
    divisions: ParamTreino.intervaloMax,
    onChanged: (f) => onIntervalo(ParamTreino.intervalo(f)),
  ),
  if (erroIntervalo != null) _ErroParametro(erroIntervalo),
  SessionTimeRow(lances: lances, intervaloS: intervaloS),
];

class _ErroParametro extends StatelessWidget {
  const _ErroParametro(this.mensagem);

  final String mensagem;

  @override
  Widget build(BuildContext context) =>
      Text(mensagem, style: AppText.bodyS.c(AppColors.textError));
}

/// Validação local antes de enviar, nos limites da API. Devolvem a mensagem
/// de erro ou `null`. Com os sliders atuais (1–50 lances, 1–10 s) os erros de
/// lances e intervalo não disparam: ficam como proteção.
String? validarTituloTreino(String titulo) {
  if (titulo.isEmpty) return 'Dê um nome ao treino.';
  if (titulo.length < 3) return 'O nome precisa ter pelo menos 3 caracteres.';
  if (titulo.length > 120) return 'O nome pode ter no máximo 120 caracteres.';
  return null;
}

String? validarDescricaoTreino(String descricao) => descricao.length > 500
    ? 'A descrição pode ter no máximo 500 caracteres.'
    : null;

String? validarLances(int lances) => lances < 1 || lances > 200
    ? 'A quantidade de lances deve ficar entre 1 e 200.'
    : null;

String? validarIntervaloMs(int ms) => ms < 500 || ms > 60000
    ? 'O intervalo deve ficar entre 0,5 e 60 segundos.'
    : null;

/// 3.4 Novo treino (20:363) e 3.6 Novo treino · Personalizado (101:5516).
///
/// Mudar um slider em relação ao padrão do nível troca o nível para
/// Personalizado (guardando a base, ex.: Médio). Tocar em outro nível
/// restaura os valores padrão dele.
class NovoTreinoScreen extends StatefulWidget {
  const NovoTreinoScreen({super.key});

  @override
  State<NovoTreinoScreen> createState() => _NovoTreinoScreenState();
}

class _NovoTreinoScreenState extends State<NovoTreinoScreen> {
  var _nivel = Nivel.medio;

  /// Nível de onde saíram os valores (base do Personalizado).
  var _base = Nivel.medio;
  var _lances = ParamTreino.padrao[Nivel.medio]!.$1;
  var _intervalo = ParamTreino.padrao[Nivel.medio]!.$2;

  final _titulo = TextEditingController();
  final _descricao = TextEditingController();
  final _api = ApiClient();

  String? _erroTitulo;
  String? _erroDescricao;
  String? _erroLances;
  String? _erroIntervalo;

  /// Erro do envio (rede ou 422), mostrado acima do botão.
  String? _erroEnvio;
  var _enviando = false;

  @override
  void dispose() {
    _titulo.dispose();
    _descricao.dispose();
    super.dispose();
  }

  /// Valida localmente e cria o treino na API. Com 201, volta para a
  /// listagem devolvendo `true` para ela recarregar. Em erro, tocar no botão
  /// de novo tenta de novo.
  Future<void> _salvar() async {
    if (_enviando) return;
    final titulo = _titulo.text.trim();
    final descricao = _descricao.text.trim();
    final intervaloMs = _intervalo * 1000;
    setState(() {
      _erroTitulo = validarTituloTreino(titulo);
      _erroDescricao = validarDescricaoTreino(descricao);
      _erroLances = validarLances(_lances);
      _erroIntervalo = validarIntervaloMs(intervaloMs);
      _erroEnvio = null;
    });
    if (_erroTitulo != null ||
        _erroDescricao != null ||
        _erroLances != null ||
        _erroIntervalo != null) {
      return;
    }

    final token = await AuthStore.lerToken();
    if (!mounted) return;
    if (token == null) return context.go(Routes.login);

    setState(() => _enviando = true);
    try {
      await _api.criarTreino(
        token,
        titulo: titulo,
        descricao: descricao,
        nivel: _nivel,
        qtdLances: _lances,
        intervaloMs: intervaloMs,
        // A tela de criação não tem o controle "Falas do TOBIAS" (a de
        // edição tem), então todo treino novo é criado com as falas ligadas.
        falasTobias: true,
      );
      if (mounted) context.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 401) {
        await AuthStore.limparToken();
        if (mounted) context.go(Routes.login);
        return;
      }
      setState(() => _erroEnvio = e.mensagem);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _escolherNivel(Nivel n) => setState(() {
    if (n == Nivel.personalizado) {
      _nivel = n;
      return;
    }
    _nivel = _base = n;
    final (lances, intervalo) = ParamTreino.padrao[n]!;
    _lances = lances;
    _intervalo = intervalo;
  });

  void _mudar({int? lances, int? intervalo}) => setState(() {
    _lances = lances ?? _lances;
    _intervalo = intervalo ?? _intervalo;
    if (_nivel != Nivel.personalizado &&
        (_lances, _intervalo) != ParamTreino.padrao[_nivel]) {
      _base = _nivel;
      _nivel = Nivel.personalizado;
    }
  });

  @override
  Widget build(BuildContext context) {
    void voltar() => goBack(context, Routes.treinos);
    return StackedScreen(
      title: 'Novo treino',
      onBack: voltar,
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      gap: 16,
      children: [
        AppField(
          label: 'Nome do treino',
          controller: _titulo,
          placeholder: 'Ex.: Reação turbo',
          error: _erroTitulo != null,
          helper: _erroTitulo,
        ),
        AppField(
          label: 'Descrição',
          controller: _descricao,
          placeholder: 'Ex.: Sequência rápida para aquecer',
          error: _erroDescricao != null,
          helper: _erroDescricao,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text('Nível', style: AppText.labelM.c(AppColors.textSecondary)),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final n in Nivel.values)
                  AppChip(
                    n.label,
                    selected: n == _nivel,
                    onTap: () => _escolherNivel(n),
                  ),
              ],
            ),
          ],
        ),
        if (_nivel == Nivel.personalizado)
          InfoBanner(
            icon: AppIcons.sliders,
            title: 'Treino personalizado',
            body:
                'Você mudou os valores do nível ${_base.label}. Este treino será salvo como Personalizado.',
          ),
        SectionCard(
          title: 'Parâmetros do treino',
          gap: 16,
          children: parametrosTreino(
            lances: _lances,
            intervaloS: _intervalo,
            onLances: (v) => _mudar(lances: v),
            onIntervalo: (v) => _mudar(intervalo: v),
            erroLances: _erroLances,
            erroIntervalo: _erroIntervalo,
          ),
        ),
        const Spacer(),
        if (_erroEnvio != null)
          InfoBanner(
            icon: AppIcons.alertOctagon,
            tone: InfoTone.warning,
            title: 'Não foi possível salvar',
            body: '$_erroEnvio Toque em "Salvar treino" para tentar de novo.',
          ),
        AppButton('Salvar treino', onPressed: _enviando ? null : _salvar),
      ],
    );
  }
}
