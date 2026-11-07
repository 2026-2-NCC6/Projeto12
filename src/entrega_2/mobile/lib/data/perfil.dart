/// Perfil: as três estatísticas e os textos da calibração.
///
/// Tudo aqui é função pura, para os testes: o "agora" e a conversão para o
/// fuso local entram por parâmetro (como em dashboard.dart).
library;

import 'dashboard.dart';
import 'format.dart';

/// As três estatísticas do Perfil, de todo o período.
class EstatisticasPerfil {
  const EstatisticasPerfil({
    required this.sessoes,
    required this.recorde,
    required this.diasSeguidos,
  });

  /// O `total` do envelope de `GET /v1/sessions`.
  final int sessoes;

  /// Maior `pontuacao_total`; nulo sem nenhuma sessão pontuada.
  final int? recorde;

  /// Dias de calendário seguidos com ao menos uma sessão ([diasSeguidos]).
  final int diasSeguidos;
}

EstatisticasPerfil estatisticasPerfil(
  List<SessaoApi> sessoes,
  int total,
  DateTime agora, {
  DateTime Function(DateTime)? paraLocal,
}) {
  int? recorde;
  for (final s in sessoes) {
    final p = s.pontuacaoTotal;
    if (p != null && (recorde == null || p > recorde)) recorde = p;
  }
  return EstatisticasPerfil(
    sessoes: total,
    recorde: recorde,
    diasSeguidos: diasSeguidos(
      [for (final s in sessoes) s.iniciadaEm],
      agora,
      paraLocal: paraLocal,
    ),
  );
}

/// Dias de calendário consecutivos, terminando hoje ou ontem, com ao menos
/// uma sessão.
///
/// NÃO é a `melhor_sequencia` da API: aquela conta acertos seguidos dentro de
/// UMA sessão. Nomes parecidos, números diferentes, e trocar um pelo outro
/// mostraria um valor errado e plausível.
///
/// - Os dias são do fuso do APARELHO ([paraLocal]; padrão `toLocal()`), não
///   de UTC: uma sessão às 22h em São Paulo já é o dia seguinte em UTC.
/// - Viva se o último dia treinado for hoje OU ontem: exigir hoje zeraria o
///   número toda madrugada, antes de a pessoa ter chance de treinar.
/// - Nem hoje nem ontem: 0.
int diasSeguidos(
  Iterable<DateTime> inicios,
  DateTime agora, {
  DateTime Function(DateTime)? paraLocal,
}) {
  final local = paraLocal ?? (DateTime d) => d.toLocal();
  DateTime dia(DateTime d) => DateTime(d.year, d.month, d.day);
  final dias = {for (final i in inicios) dia(local(i))};

  final hoje = dia(local(agora));
  // DateTime(ano, mes, dia - n), e não subtract(Duration): atravessa o
  // horário de verão sem pular nem repetir dia.
  DateTime antes(DateTime d, int n) => DateTime(d.year, d.month, d.day - n);

  var cursor = dias.contains(hoje) ? hoje : antes(hoje, 1);
  if (!dias.contains(cursor)) return 0;
  var n = 0;
  while (dias.contains(cursor)) {
    n++;
    cursor = antes(cursor, 1);
  }
  return n;
}

const _meses = [
  'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
  'jul', 'ago', 'set', 'out', 'nov', 'dez',
];

/// "19 nov"; com o ano quando não for o ano corrente: "19 nov 2025".
String fmtDiaMes(DateTime local, {required DateTime hoje}) {
  final base = '${local.day} ${_meses[local.month - 1]}';
  return local.year == hoje.year ? base : '$base ${local.year}';
}

/// Linha do cartão do TOBIAS: "Calibrado em 19 nov · dificuldade +12,5°".
///
/// Com dificuldade 0, só a data: "+0,0°" confunde mais do que informa.
/// A unidade é grau (a dificuldade soma graus aos limiares de ângulo), não g
/// como no Figma, que era da versão antiga do firmware. Nulo = nunca calibrou.
String? textoCalibracao(
  DateTime? calibradoEm,
  double dificuldade, {
  required DateTime agora,
  DateTime Function(DateTime)? paraLocal,
}) {
  if (calibradoEm == null) return null;
  final local = paraLocal ?? (DateTime d) => d.toLocal();
  final data = fmtDiaMes(local(calibradoEm), hoje: local(agora));
  if (dificuldade <= 0) return 'Calibrado em $data';
  return 'Calibrado em $data · dificuldade +${fmtDec(dificuldade)}°';
}

/// Rótulo do selo do perfil, como a API devolve. Desconhecido: sem selo.
String? rotuloPerfil(String? perfil) => switch (perfil) {
  'casual' => 'Casual',
  'iniciante' => 'Iniciante',
  'infantil' => 'Infantil',
  _ => null,
};
