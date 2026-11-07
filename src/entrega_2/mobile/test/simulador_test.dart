/// O simulador precisa se parecer com a realidade: batidas de ~25° a 70°
/// que cubram as três faixas (fraco, médio, KO), com a regra de faixas e a
/// dificuldade de verdade do app. Sessão real medida no protótipo: média
/// 42,8°, máximo 66,6°.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tennis_arena_mobile/data/fila_sessoes.dart';
import 'package:smart_tennis_arena_mobile/data/mock_data.dart';
import 'package:smart_tennis_arena_mobile/data/models.dart';
import 'package:smart_tennis_arena_mobile/data/pontuacao.dart';
import 'package:smart_tennis_arena_mobile/data/resumo_sessao.dart';
import 'package:smart_tennis_arena_mobile/state/gravador_sessao.dart';
import 'package:smart_tennis_arena_mobile/state/sessao_ativa.dart';
import 'package:smart_tennis_arena_mobile/transport/mock_transport.dart';

double _mediana(List<double> v) {
  final s = List.of(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

Set<FaixaIntensidade> _faixas(List<double> angulos, double dificuldade) => {
  for (final a in angulos) faixaDoAcerto(decimos(a), decimos(dificuldade)),
};

void main() {
  const batidas = Mock.calibracaoBatidas;

  test('as batidas vão de ~25° a ~70°, perto da sessão real', () {
    final ordenadas = List.of(batidas)..sort();
    expect(ordenadas.first, inInclusiveRange(22.0, 30.0));
    expect(ordenadas.last, inInclusiveRange(65.0, 70.0));
    final media = batidas.reduce((a, b) => a + b) / batidas.length;
    expect(media, closeTo(42.8, 4.0), reason: 'média $media');
  });

  test('a calibração do simulador dá a referência e a dificuldade documentadas', () {
    expect(_mediana(batidas), Mock.deviceRefAngulo);
    expect(dificuldadeDaCalibracao(_mediana(batidas)), 4.0);
  });

  test('com a dificuldade da própria calibração, cobre fraco, médio e KO', () {
    final dificuldade = dificuldadeDaCalibracao(_mediana(batidas));
    expect(_faixas(batidas, dificuldade), FaixaIntensidade.values.toSet());
    // O que a faixa antiga (36° a 52°) não fazia: chegar ao teto.
    final teto = tetoDaSessao(decimos(dificuldade)) / 10;
    expect(batidas.any((a) => a >= teto), isTrue, reason: 'teto $teto°');
  });

  test('sem calibrar (dificuldade 0, "Usar simulador"), também cobre as três', () {
    expect(_faixas(batidas, 0), FaixaIntensidade.values.toSet());
  });

  test('a faixa antiga, de 36° a 52°, não tinha KO (o motivo da troca)', () {
    const antiga = [36.0, 44.0, 52.0, 40.0, 48.0];
    final dificuldade = dificuldadeDaCalibracao(_mediana(antiga));
    expect(dificuldade, 6.0);
    expect(_faixas(antiga, dificuldade), isNot(contains(FaixaIntensidade.ko)));
  });

  test('uma sessão simulada de ponta a ponta tem fracos, médios e KO', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    const treino = Drill(
      id: 'sim',
      titulo: 'Simulado',
      descricao: '',
      tipo: DrillType.catalogo,
      lances: 5,
      intervaloS: 3,
      nivel: Nivel.medio,
      versaoId: 1,
    );
    final fila = FilaSessoes(donoAtual: () async => null);
    final gravador = GravadorSessao(
      // A dificuldade que a calibração no simulador deixaria.
      sessao: SessaoAtiva.iniciar(
        treino,
        dificuldade: dificuldadeDaCalibracao(_mediana(batidas)),
      ),
      fila: fila,
      // Picos padrão do simulador (Mock.calibracaoBatidas), em ritmo rápido.
      transport: MockTransport(
        primeira: const Duration(milliseconds: 5),
        seguintes: const Duration(milliseconds: 5),
      ),
      usuarioAtual: () async => null,
    );
    await gravador.iniciar();
    while (gravador.lancesGravados.value < treino.lances) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await gravador.encerrar();

    final r = ResumoSessao.de((await fila.todas()).single);
    expect((r.acertos, r.fracos, r.medios, r.kos), (5, 2, 2, 1));
  });
}
