import '../data/models.dart';

/// A sessão que está sendo treinada, congelada no momento em que começou.
///
/// "Congelada": tudo é COPIADO do treino uma única vez, em [SessaoAtiva.iniciar],
/// e nada aqui é relido depois. Se o treino for editado (e ganhar uma versão
/// nova) durante a sessão, ela continua pertencendo à versão treinada — que
/// é a que vai em `treino_versao_id` no envio (US-704).
///
/// Por enquanto vive só em memória; a persistência é da etapa 3.
class SessaoAtiva {
  const SessaoAtiva._({
    required this.titulo,
    required this.treinoVersaoId,
    required this.lances,
    required this.intervaloMs,
    required this.dificuldade,
  });

  /// Congela o treino escolhido e a dificuldade da calibração atual.
  ///
  /// Exige um treino vindo da API (com `versaoId`): sem a versão, a sessão
  /// não teria a que pertencer no servidor.
  factory SessaoAtiva.iniciar(Drill treino, {required double dificuldade}) {
    final versaoId = treino.versaoId;
    if (versaoId == null) {
      throw ArgumentError.value(
        treino.titulo,
        'treino',
        'treino sem versão da API; a sessão não teria a que pertencer',
      );
    }
    return SessaoAtiva._(
      titulo: treino.titulo,
      treinoVersaoId: versaoId,
      lances: treino.lances,
      intervaloMs: treino.intervaloExatoMs,
      // Com 1 casa, exatamente o que o comando TREINO leva ao firmware
      // (toStringAsFixed(1)). É a dificuldade efetivamente usada, e a API
      // recusa mais de uma casa. A calibração do servidor pode ter mais.
      dificuldade: double.parse(dificuldade.toStringAsFixed(1)),
    );
  }

  final String titulo;

  /// `versao_atual.id` do treino no início da sessão.
  final int treinoVersaoId;

  /// Quantidade de lances e intervalo, em ms, da versão treinada.
  final int lances;
  final int intervaloMs;

  /// Graus somados ao limiar de KO (o `calib` do comando TREINO). Também
  /// congelada: é parâmetro da sessão, e o servidor a usa para pontuar.
  final double dificuldade;
}
