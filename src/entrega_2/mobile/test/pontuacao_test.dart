import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tennis_arena_mobile/data/pontuacao.dart';

/// Os golden fixtures são lidos DIRETO do backend, de propósito.
///
/// É o mesmo arquivo que o pytest usa. Uma cópia dentro do pacote Flutter
/// divergiria na primeira alteração, e aí os dois testes passariam enquanto
/// as implementações discordam — o problema que os fixtures existem para
/// impedir. Não copie.
///
/// O caminho é relativo à raiz do pacote (`mobile/`), e não ao arquivo do
/// teste, porque o `flutter test` sempre roda com a raiz do pacote como
/// diretório atual, enquanto o caminho do arquivo do teste não é confiável
/// (`Platform.script` aponta para um arquivo temporário gerado pelo runner).
/// De `mobile/`: sobe para `entrega_2/` e entra em `backend/contracts/`.
final _golden = File('../backend/contracts/pontuacao/golden.json');

void main() {
  if (!_golden.existsSync()) {
    throw StateError(
      'Golden fixtures não encontrados em ${_golden.absolute.path}. '
      'Rode `flutter test` a partir de src/entrega_2/mobile.',
    );
  }
  final golden = jsonDecode(_golden.readAsStringSync()) as Map<String, dynamic>;
  final casos = (golden['casos'] as List).cast<Map<String, dynamic>>();

  List<LanceBruto> lancesDo(Map<String, dynamic> caso) => [
    for (final l in (caso['lances'] as List).cast<Map<String, dynamic>>())
      LanceBruto(
        bola: l['bola'] as int,
        resultado: ResultadoLance.values.byName(l['resultado'] as String),
        anguloDecimos: decimos(l['angulo'] as num),
      ),
  ];

  test('fixtures são da versão atual da regra', () {
    expect(golden['versao_regra'], versaoRegraPontuacao);
  });

  test('fixtures trazem os 15 casos', () {
    // Se alguém acrescentar casos, atualize este número de propósito.
    expect(casos, hasLength(15));
  });

  group('golden', () {
    for (final caso in casos) {
      test(caso['id'], () {
        final r = calcularPontuacao(
          lancesDo(caso),
          dificuldadeDecimos: decimos(caso['dificuldade'] as num),
        );
        final esperado = caso['esperado'] as Map<String, dynamic>;

        expect(r.pontosPorLance, (esperado['pontos_por_lance'] as List).cast<int>());
        expect(r.pontuacaoTotal, esperado['pontuacao_total']);
        expect(r.melhorSequencia, esperado['melhor_sequencia']);
        expect(r.kos, esperado['kos']);
      });
    }
  });

  test('ko é verdadeiro exatamente quando I == 1000', () {
    for (final dificuldade in [0, 1, 55, 100, 125, 450]) {
      final teto = tetoDaSessao(dificuldade);
      for (var angulo = 0; angulo <= 1800; angulo++) {
        final r = calcularPontuacao([
          LanceBruto(bola: 1, resultado: ResultadoLance.acerto, anguloDecimos: angulo),
        ], dificuldadeDecimos: dificuldade);
        expect(
          r.koPorLance.single,
          intensidade(angulo, teto) == 1000,
          reason: 'angulo=$angulo dificuldade=$dificuldade',
        );
      }
    }
  });

  test('decimos é exato para os 1801 valores de 0,0 a 180,0', () {
    // Mesma verificação citada na seção 3 da spec, agora no Dart.
    for (var d = 0; d <= 1800; d++) {
      expect(decimos(double.parse((d / 10).toStringAsFixed(1))), d);
    }
  });

  test('decimos recusa mais de uma casa decimal', () {
    expect(() => decimos(61.45), throwsArgumentError);
  });

  test('empate de bola mantém a ordem de entrada (como o sorted do Python)', () {
    // Dois lances com bola 1: acerto e depois erro. Ordem estável dá
    // [20, -20]; uma ordenação instável poderia trocar para [-20, 20].
    final lances = [
      for (var i = 0; i < 40; i++)
        LanceBruto(
          bola: 1,
          resultado: i.isEven ? ResultadoLance.acerto : ResultadoLance.erro,
          anguloDecimos: i.isEven ? 250 : 0,
        ),
    ];
    final r = calcularPontuacao(lances, dificuldadeDecimos: 0);
    expect(r.pontosPorLance, [for (var i = 0; i < 40; i++) i.isEven ? 20 : -20]);
  });
}
