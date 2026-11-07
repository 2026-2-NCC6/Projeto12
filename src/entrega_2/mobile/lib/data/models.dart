/// Modelos mínimos do app (somente front-end, dados de exemplo).
library;

enum DrillType { catalogo, pessoal }

enum Nivel {
  facil('Fácil'),
  medio('Médio'),
  dificil('Difícil'),
  infantil('Infantil'),

  /// Parâmetros mudados em relação ao padrão de outro nível.
  personalizado('Personalizado');

  const Nivel(this.label);
  final String label;
}

class Drill {
  const Drill({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.tipo,
    required this.lances,
    required this.intervaloS,
    required this.nivel,
    this.origem,
    this.intervaloMs,
    this.falasTobias,
    this.versaoId,
  });

  /// `versao_atual.id` da API: a versão exata dos parâmetros acima. É ela
  /// que a sessão guarda (e envia em `treino_versao_id`), para continuar
  /// presa à versão treinada mesmo que o treino seja editado depois.
  /// Nulo nos dados de exemplo, que não vêm da API.
  final int? versaoId;

  final String id;
  final String titulo;
  final String descricao;
  final DrillType tipo;

  /// Título do treino do catálogo em que este foi baseado (só "Meus treinos").
  final String? origem;
  final int lances;

  /// Intervalo entre os lances, em segundos.
  final int intervaloS;

  /// Intervalo exato em milissegundos, quando o treino vem da API. Os dados
  /// de exemplo não preenchem e usam só [intervaloS].
  final int? intervaloMs;

  /// "Falas do TOBIAS" ligadas, quando o treino vem da API.
  final bool? falasTobias;
  final Nivel nivel;

  /// Intervalo exato em ms: o da API ou, nos dados de exemplo, [intervaloS].
  int get intervaloExatoMs => intervaloMs ?? intervaloS * 1000;

  /// Tempo da sessão = lances × intervalo entre os lances, em milissegundos.
  int get duracaoMs => lances * intervaloExatoMs;
}

class Session {
  const Session({
    required this.id,
    required this.dia,
    required this.mes,
    required this.drillTitulo,
    required this.lances,
    required this.precisao,
    required this.pontos,
    required this.sincronizada,
    this.separada = false,
  });

  final String id;
  final int dia;

  /// Mês abreviado, 3 letras maiúsculas (ex.: "SET").
  final String mes;
  final String drillTitulo;
  final int lances;

  /// Precisão em % (0–100).
  final int precisao;
  final int pontos;
  final bool sincronizada;

  /// Recusada pela API por erro do app (422): guardada, mas não vai subir.
  final bool separada;
}

/// Tratamento visual do lance: acerto (fraco ou médio), KO ou erro.
enum ShotResult { acerto, erro, ko }

/// Um lance como a tela de detalhe mostra.
class Shot {
  const Shot({
    required this.n,
    required this.faixa,
    required this.pontos,
    required this.resultado,
    this.angulo,
  });

  /// Número da bola (contador do app, de 1 a N).
  final int n;

  /// "Fraco", "Médio", "KO" ou "Sem impacto". Não existe "Forte": o KO é a
  /// faixa forte.
  final String faixa;

  /// Ângulo de inclinação em graus, como o firmware mede (nulo no erro).
  final num? angulo;

  /// Pela regra local de pontuação.
  final int pontos;
  final ShotResult resultado;
}

class RankEntry {
  const RankEntry({
    required this.apelido,
    required this.valor,
    this.detalhe,
    this.voce = false,
    String? inicial,
  }) : _inicial = inicial;

  final String apelido;
  final String valor;
  final String? detalhe;
  final bool voce;
  final String? _inicial;

  /// Letra do avatar (por padrão, a inicial do apelido).
  String get inicial => _inicial ?? apelido[0].toUpperCase();
}
