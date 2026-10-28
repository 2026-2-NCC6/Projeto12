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
  });

  final String id;
  final String titulo;
  final String descricao;
  final DrillType tipo;

  /// Título do treino do catálogo em que este foi baseado (só "Meus treinos").
  final String? origem;
  final int lances;

  /// Intervalo entre os lances, em segundos.
  final int intervaloS;
  final Nivel nivel;

  /// Tempo da sessão = lances × intervalo entre os lances, em segundos.
  int get duracaoS => lances * intervaloS;
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
}

enum ShotResult { acerto, erro, ko }

class Shot {
  const Shot({
    required this.n,
    required this.forca,
    required this.pontos,
    required this.resultado,
    this.g,
    this.reacaoMs,
  });

  final int n;

  /// Rótulo de força: "Médio", "Forte", "KO", "Sem impacto".
  final String forca;

  /// Pico de aceleração em g (nulo quando não houve impacto).
  final double? g;

  /// Tempo de reação medido no firmware. Guardado para a pontuação, mas não
  /// aparece em nenhuma tela.
  final int? reacaoMs;
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

class UserProfile {
  const UserProfile({
    required this.nome,
    required this.apelido,
    required this.email,
  });

  final String nome;
  final String apelido;
  final String email;
}
