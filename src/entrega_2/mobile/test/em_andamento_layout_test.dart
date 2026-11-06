import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/api_client.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/screens/sessao/em_andamento_screen.dart';
import 'package:smart_tennis_arena_mobile/state/app_settings.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/transport/device_transport.dart';
import 'package:smart_tennis_arena_mobile/widgets/buttons.dart';

/// Tobias que nunca confirma: toda pausa falha e a mensagem aparece.
class _TobiasMudo implements DeviceTransport {
  final comandos = <String>[];

  @override
  Stream<ImpactEvent> get events => const Stream.empty();
  @override
  Stream<StatusTobias> get estados => const Stream.empty();
  @override
  Future<void> send(
    DeviceCommand cmd, {
    int lances = 15,
    int intervaloMs = 3000,
    double calibracao = 0.0,
  }) async => comandos.add(montarComando(cmd).trim());
  @override
  Future<DeviceStatus> status() async =>
      const DeviceStatus(nome: 'TOBIAS', conectado: true, bateria: 90);
  @override
  Future<void> disconnect() async {}
}

Future<void> _carregarRoboto() async {
  final loader = FontLoader('Roboto');
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/Roboto-$peso.ttf'));
  }
  await loader.load();
}

SessaoAtiva _sessao() => SessaoAtiva.iniciar(
  PaginaTreinos.fromJson({
    'items': [
      {
        'id': 7,
        // Título longo de propósito: é o pior caso do cabeçalho.
        'titulo': 'Treino de resistência no fundo de quadra',
        'descricao': '',
        'escopo': 'pessoal',
        'versao_atual': {
          'id': 321,
          'numero': 1,
          'nivel': 'medio',
          'qtd_lances': 10,
          'intervalo_ms': 3000,
          'falas_tobias': true,
        },
      },
    ],
    'total': 1,
  }).itens.single,
  dificuldade: 0,
);

// Celular pequeno real, com barra de status (24) e navegação por gestos (16).
const _tela = Size(360, 640);
const _barraStatus = 24.0;
const _barraNavegacao = 16.0;

bool _falhaVisivel(WidgetTester tester) => tester
    .widget<Visibility>(find.byKey(const ValueKey('cartao-falha')))
    .visible;

Rect _botao(WidgetTester tester, String texto, Type tipo) => tester.getRect(
  find.ancestor(of: find.text(texto), matching: find.byType(tipo)).first,
);

void main() {
  setUpAll(_carregarRoboto);

  // O texto da falha está sempre na árvore de widgets (reserva a altura do
  // cartão). Na de semântica, não pode estar: o TalkBack anunciaria "O TOBIAS
  // não respondeu" numa sessão em que nada deu errado.
  testWidgets('leitor de tela só ouve a mensagem que está à vista', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: EmAndamentoScreen(
          sessao: _sessao(),
          fila: FilaSessoes(),
          transport: _TobiasMudo(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    // Percorre a árvore de semântica VIVA, a que o TalkBack recebe. O
    // find.bySemanticsLabel não serve aqui: ele olha o último nó guardado em
    // cada texto, que fica desatualizado quando o texto sai da semântica.
    List<String> rotulos() {
      final achados = <String>[];
      bool visitar(SemanticsNode n) {
        if (n.label.isNotEmpty) achados.add(n.label);
        n.visitChildren(visitar);
        return true;
      }

      visitar(tester.getSemantics(find.byType(EmAndamentoScreen)));
      return achados;
    }

    int quantos(String trecho) =>
        rotulos().where((r) => r.contains(trecho)).length;

    // Rodando normal: nada de falha, nem a reserva invisível.
    expect(quantos('não respondeu'), 0, reason: '${rotulos()}');
    expect(quantos('não foi confirmado'), 0);
    expect(quantos('TOBIAS conectado'), 1);

    await tester.tap(find.text('Pausar'));
    await tester.pump(const Duration(milliseconds: 1600));

    // Com a falha: só a mensagem real (pausa), não a reserva (retomada), e
    // o "conectado" escondido sai da semântica.
    expect(quantos('não respondeu'), 1, reason: '${rotulos()}');
    expect(quantos('comando de pausa não foi confirmado'), 1);
    expect(quantos('retomada'), 0);
    expect(quantos('TOBIAS conectado'), 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    semantica.dispose();
  });

  for (final grande in [false, true]) {
    testWidgets(
      'em 360x640${grande ? ' · texto grande' : ''}, a mensagem de falha '
      'não desloca os botões e os dois seguem alcançáveis sem rolagem',
      (tester) async {
        tester.view.physicalSize = _tela * 3;
        tester.view.devicePixelRatio = 3;
        tester.view.padding = const FakeViewPadding(
          top: _barraStatus * 3,
          bottom: _barraNavegacao * 3,
        );
        addTearDown(tester.view.reset);
        // Sem rolagem nenhuma: um toque que erre o alvo derruba o teste.
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
        SharedPreferences.resetStatic();
        SharedPreferences.setMockInitialValues({});

        final tobias = _TobiasMudo();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            // Mesma escala que o app aplica com "Texto grande".
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  grande ? AppSettings.escalaGrande : 1.0,
                ),
              ),
              child: child!,
            ),
            home: EmAndamentoScreen(
              sessao: _sessao(),
              fila: FilaSessoes(),
              transport: tobias,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(Scrollable), findsNothing);

        final pausarAntes = _botao(tester, 'Pausar', InkWell);
        final finalizarAntes = _botao(tester, 'Finalizar sessão', AppButton);

        // A pausa falha: 1,5 s sem resposta.
        await tester.tap(find.text('Pausar'));
        await tester.pump(const Duration(milliseconds: 1600));
        expect(_falhaVisivel(tester), isTrue);
        expect(tester.takeException(), isNull, reason: 'overflow');

        // Nada se mexeu.
        expect(_botao(tester, 'Pausar', InkWell), pausarAntes);
        expect(_botao(tester, 'Finalizar sessão', AppButton), finalizarAntes);

        // Os dois inteiros dentro da área útil, fora das barras do sistema.
        const util = Rect.fromLTRB(
          0,
          _barraStatus,
          360,
          640 - _barraNavegacao,
        );
        for (final r in [pausarAntes, finalizarAntes]) {
          expect(
            util.top <= r.top && r.bottom <= util.bottom,
            isTrue,
            reason: '$r fora de $util',
          );
        }
        expect(find.text('Finalizar sessão').hitTestable(), findsOneWidget);

        // "Tentar de novo" é um toque direto, sem rolar.
        await tester.tap(find.text('Pausar'));
        await tester.pump();
        expect(tobias.comandos.where((c) => c == 'PAUSAR'), hasLength(2));
        await tester.pump(const Duration(milliseconds: 1600));

        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}
