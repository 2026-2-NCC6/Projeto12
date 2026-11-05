import 'fila_sessoes.dart';
import 'models.dart';
import 'pontuacao.dart';

/// Os lances de uma sessão como a tela de detalhe mostra, na ordem da bola.
///
/// - Faixa pelo ÂNGULO ([faixaDoAcerto]), a mesma do resumo, para as duas
///   telas nunca discordarem: Fraco, Médio ou KO (o KO é a faixa forte).
///   Erro é "Sem impacto", sem ângulo.
/// - Pontos de cada lance pela regra local ([SessaoLocal.pontuar]). A
///   pontuação do cabeçalho é a exibida (a do servidor, se houver); as duas
///   concordam por construção (golden fixtures).
///
/// A ordem é a mesma em que [calcularPontuacao] percorre os lances: por
/// `bola`, e empates na ordem de chegada. É isso que casa cada lance com o
/// seu item de `pontosPorLance`.
List<Shot> lancesDoDetalhe(SessaoLocal sessao) {
  final pontos = sessao.pontuar().pontosPorLance;
  final dificuldade = decimos(sessao.dificuldade);
  final lances = sessao.lances;
  final ordem = List<int>.generate(lances.length, (i) => i)
    ..sort((a, b) {
      final porBola = lances[a].bola.compareTo(lances[b].bola);
      return porBola != 0 ? porBola : a.compareTo(b);
    });

  return [
    for (final (i, indice) in ordem.indexed)
      _shot(lances[indice], pontos[i], dificuldade),
  ];
}

Shot _shot(LanceLocal l, int pontos, int dificuldade) {
  if (l.resultado != ResultadoLance.acerto.name) {
    return Shot(
      n: l.bola,
      faixa: 'Sem impacto',
      pontos: pontos,
      resultado: ShotResult.erro,
    );
  }
  final faixa = faixaDoAcerto(decimos(l.angulo), dificuldade);
  return Shot(
    n: l.bola,
    faixa: switch (faixa) {
      FaixaIntensidade.fraco => 'Fraco',
      FaixaIntensidade.medio => 'Médio',
      FaixaIntensidade.ko => 'KO',
    },
    angulo: l.angulo,
    pontos: pontos,
    resultado: faixa == FaixaIntensidade.ko ? ShotResult.ko : ShotResult.acerto,
  );
}

/// Filtros da lista de lances.
enum FiltroLances { todos, erros, kos }

List<Shot> filtrarLances(List<Shot> lances, FiltroLances filtro) =>
    switch (filtro) {
      FiltroLances.todos => lances,
      FiltroLances.erros => [
        for (final l in lances)
          if (l.resultado == ShotResult.erro) l,
      ],
      FiltroLances.kos => [
        for (final l in lances)
          if (l.resultado == ShotResult.ko) l,
      ],
    };

const _meses = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

/// "Sessão de 19 set", na data local de início.
String tituloDoDetalhe(SessaoLocal sessao) {
  final inicio = DateTime.parse(sessao.iniciadaEm).toLocal();
  return 'Sessão de ${inicio.day} ${_meses[inicio.month - 1]}';
}
