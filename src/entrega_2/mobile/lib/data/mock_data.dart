/// Dados de exemplo (fictícios) usados pelas telas. Nada de número solto nas
/// telas: tudo o que é "conteúdo" vem daqui.
library;

import 'models.dart';

abstract final class Mock {
  // ------------------------------------------------------------ Dispositivo
  static const deviceName = 'TOBIAS-01';
  /// Mediana de [calibracaoBatidas], em graus.
  static const deviceRefAngulo = 42.0;
  static const deviceBateria = 82;

  /// Bateria informada na tela "Bluetooth conectado" (2.3).
  static const deviceBateriaAoConectar = 87;

  // ---------------------------------------------------------------- Treinos
  static const reacaoRapida = Drill(
    id: 'reacao-rapida',
    titulo: 'Reação rápida',
    descricao: 'Responda ao sinal de luz o mais rápido possível.',
    tipo: DrillType.catalogo,
    lances: 20,
    intervaloS: 3,
    nivel: Nivel.facil,
  );
  static const sequenciaDupla = Drill(
    id: 'sequencia-dupla',
    titulo: 'Sequência dupla',
    descricao: 'Dois sinais seguidos, um de cada lado.',
    tipo: DrillType.catalogo,
    lances: 15,
    intervaloS: 4,
    nivel: Nivel.medio,
  );
  static const reacaoTurbo = Drill(
    id: 'reacao-turbo',
    titulo: 'Reação turbo',
    descricao: 'Minha versão do treino de reação.',
    tipo: DrillType.pessoal,
    origem: 'Reação rápida',
    lances: 20,
    intervaloS: 2,
    nivel: Nivel.dificil,
  );

  /// Chip "Todos" (3.1) e Sessão · Seleção (4.1).
  static const treinosTodos = [reacaoRapida, sequenciaDupla, reacaoTurbo];

  /// Chip "Catálogo" (3.2).
  static const treinosCatalogo = [
    reacaoRapida,
    sequenciaDupla,
    Drill(
      id: 'precisao-alvo',
      titulo: 'Precisão no alvo',
      descricao: 'Acerte a região marcada do boneco.',
      tipo: DrillType.catalogo,
      lances: 20,
      intervaloS: 4,
      nivel: Nivel.medio,
    ),
    Drill(
      id: 'resistencia',
      titulo: 'Resistência',
      descricao: 'Sessão longa para manter o ritmo.',
      tipo: DrillType.catalogo,
      lances: 30,
      intervaloS: 4,
      nivel: Nivel.dificil,
    ),
  ];

  /// Chip "Meus treinos" (3.3).
  static const treinosMeus = [
    Drill(
      id: 'reacao-turbo-meu',
      titulo: 'Reação turbo',
      descricao: 'Baseado em: Reação rápida',
      tipo: DrillType.pessoal,
      origem: 'Reação rápida',
      lances: 20,
      intervaloS: 2,
      nivel: Nivel.dificil,
    ),
    Drill(
      id: 'reacao-rapida-minha',
      titulo: 'Reação rápida (minha)',
      descricao: 'Baseado em: Reação rápida',
      tipo: DrillType.pessoal,
      origem: 'Reação rápida',
      lances: 15,
      intervaloS: 3,
      nivel: Nivel.facil,
    ),
    Drill(
      id: 'minha-sequencia',
      titulo: 'Minha sequência',
      descricao: 'Criado por você, do zero.',
      tipo: DrillType.pessoal,
      lances: 12,
      intervaloS: 5,
      nivel: Nivel.medio,
    ),
  ];

  // -------------------------------------------------------------- Calibração
  /// Picos das 5 batidas que o simulador envia, em GRAUS de inclinação, de
  /// 25° a 70°, como a realidade (sessão medida no protótipo: média 42,8°,
  /// máximo 66,6°). Também viram o ângulo dos lances das sessões simuladas,
  /// que precisam cobrir as TRÊS faixas.
  ///
  /// Mediana 42,0° → dificuldade +4,0° (mediana − 38) → médio a partir de
  /// 42°, KO a partir de 62°: 25 e 34 fracos, 42 e 52 médios, 70 KO. Com a
  /// faixa antiga (36° a 52°, dificuldade +6,0°) o teto ia a 64° e nenhuma
  /// sessão simulada tinha KO. Medianas parciais exatas (25; 33,5; 42; 38;
  /// 42) para os testes não dependerem de arredondamento.
  static const calibracaoBatidas = [25.0, 42.0, 70.0, 34.0, 52.0];
}
