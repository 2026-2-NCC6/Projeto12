/// Dados de exemplo (fictícios) usados pelas telas. Nada de número solto nas
/// telas: tudo o que é "conteúdo" vem daqui.
library;

import 'models.dart';

abstract final class Mock {
  // ---------------------------------------------------------------- Usuária
  static const user = UserProfile(
    nome: 'Maria Silva',
    apelido: 'MariaSaque',
    email: 'maria@email.com',
  );
  static const senha = 'tobias2026'; // exibida como ••••••••••

  // ------------------------------------------------------------ Dispositivo
  static const deviceName = 'TOBIAS-01';
  static const deviceRefG = 8.9;
  static const deviceBateria = 82;

  /// Bateria informada na tela "Bluetooth conectado" (2.3).
  static const deviceBateriaAoConectar = 87;
  static const deviceCalibradoEm = '19 set';

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

  // ---------------------------------------------------------------- Sessões
  /// Chip "Todas" (5.1).
  static const sessoesTodas = [
    Session(
      id: 's-19set',
      dia: 19,
      mes: 'SET',
      drillTitulo: 'Reação rápida',
      lances: 20,
      precisao: 85,
      pontos: 2146,
      sincronizada: false,
    ),
    Session(
      id: 's-17set',
      dia: 17,
      mes: 'SET',
      drillTitulo: 'Sequência dupla',
      lances: 15,
      precisao: 80,
      pontos: 1512,
      sincronizada: true,
    ),
    Session(
      id: 's-14set',
      dia: 14,
      mes: 'SET',
      drillTitulo: 'Reação turbo',
      lances: 20,
      precisao: 90,
      pontos: 2034,
      sincronizada: true,
    ),
    Session(
      id: 's-11set',
      dia: 11,
      mes: 'SET',
      drillTitulo: 'Reação rápida',
      lances: 20,
      precisao: 75,
      pontos: 1284,
      sincronizada: true,
    ),
    Session(
      id: 's-09set',
      dia: 9,
      mes: 'SET',
      drillTitulo: 'Sequência dupla',
      lances: 15,
      precisao: 73,
      pontos: 1108,
      sincronizada: true,
    ),
  ];

  /// Chip "Pendentes" (5.4).
  static const sessoesPendentes = [
    Session(
      id: 's-19set',
      dia: 19,
      mes: 'SET',
      drillTitulo: 'Reação rápida',
      lances: 20,
      precisao: 85,
      pontos: 2146,
      sincronizada: false,
    ),
    Session(
      id: 's-18set',
      dia: 18,
      mes: 'SET',
      drillTitulo: 'Reação turbo',
      lances: 20,
      precisao: 88,
      pontos: 1842,
      sincronizada: false,
    ),
  ];

  /// Chip "Este mês" (5.5).
  static const mesTitulo = 'Outubro 2026';
  static const mesSessoes = 4;
  static const mesPontos = 7920;
  static const mesPrecisao = 86;
  static const sessoesMes = [
    Session(
      id: 's-15out',
      dia: 15,
      mes: 'OUT',
      drillTitulo: 'Reação rápida',
      lances: 20,
      precisao: 87,
      pontos: 2280,
      sincronizada: true,
    ),
    Session(
      id: 's-13out',
      dia: 13,
      mes: 'OUT',
      drillTitulo: 'Sequência dupla',
      lances: 15,
      precisao: 84,
      pontos: 1640,
      sincronizada: true,
    ),
    Session(
      id: 's-10out',
      dia: 10,
      mes: 'OUT',
      drillTitulo: 'Reação turbo',
      lances: 20,
      precisao: 90,
      pontos: 2104,
      sincronizada: true,
    ),
    Session(
      id: 's-06out',
      dia: 6,
      mes: 'OUT',
      drillTitulo: 'Reação rápida',
      lances: 20,
      precisao: 82,
      pontos: 1896,
      sincronizada: true,
    ),
  ];

  // ------------------------------------------------- Última sessão (resumo)
  static const ultimaSessao = Session(
    id: 's-19set',
    dia: 19,
    mes: 'SET',
    drillTitulo: 'Reação rápida',
    lances: 20,
    precisao: 85,
    pontos: 2146,
    sincronizada: false,
  );
  static const ultimaSessaoMelhorSequencia = 9;

  /// Os 20 lances da sessão de 19 set (5.2). 15 acertos + 2 KO + 3 erros =
  /// 85% de precisão; melhor sequência = 9 (lances 10–18).
  static const lances = [
    Shot(
      n: 1,
      forca: 'Médio',
      g: 7.8,
      reacaoMs: 710,
      pontos: 96,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 2,
      forca: 'Forte',
      g: 9.1,
      reacaoMs: 640,
      pontos: 118,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 3,
      forca: 'KO',
      g: 14.2,
      reacaoMs: 580,
      pontos: 198,
      resultado: ShotResult.ko,
    ),
    Shot(n: 4, forca: 'Sem impacto', pontos: -20, resultado: ShotResult.erro),
    Shot(
      n: 5,
      forca: 'Forte',
      g: 9.6,
      reacaoMs: 620,
      pontos: 142,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 6,
      forca: 'Médio',
      g: 8.2,
      reacaoMs: 690,
      pontos: 104,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 7,
      forca: 'Forte',
      g: 9.4,
      reacaoMs: 630,
      pontos: 136,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 8,
      forca: 'Médio',
      g: 8.0,
      reacaoMs: 700,
      pontos: 100,
      resultado: ShotResult.acerto,
    ),
    Shot(n: 9, forca: 'Sem impacto', pontos: -20, resultado: ShotResult.erro),
    Shot(
      n: 10,
      forca: 'Forte',
      g: 9.8,
      reacaoMs: 600,
      pontos: 148,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 11,
      forca: 'Médio',
      g: 7.9,
      reacaoMs: 720,
      pontos: 94,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 12,
      forca: 'KO',
      g: 13.8,
      reacaoMs: 590,
      pontos: 190,
      resultado: ShotResult.ko,
    ),
    Shot(
      n: 13,
      forca: 'Forte',
      g: 9.3,
      reacaoMs: 610,
      pontos: 138,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 14,
      forca: 'Médio',
      g: 8.4,
      reacaoMs: 680,
      pontos: 106,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 15,
      forca: 'Forte',
      g: 9.0,
      reacaoMs: 650,
      pontos: 122,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 16,
      forca: 'Médio',
      g: 8.3,
      reacaoMs: 690,
      pontos: 104,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 17,
      forca: 'Médio',
      g: 8.1,
      reacaoMs: 700,
      pontos: 102,
      resultado: ShotResult.acerto,
    ),
    Shot(
      n: 18,
      forca: 'Forte',
      g: 9.5,
      reacaoMs: 620,
      pontos: 140,
      resultado: ShotResult.acerto,
    ),
    Shot(n: 19, forca: 'Sem impacto', pontos: -20, resultado: ShotResult.erro),
    Shot(
      n: 20,
      forca: 'Forte',
      g: 9.2,
      reacaoMs: 640,
      pontos: 124,
      resultado: ShotResult.acerto,
    ),
  ];

  // -------------------------------------------------------------- Calibração
  /// Picos das 5 batidas de referência que o simulador envia, em g
  /// (mediana = 8,9 g).
  static const calibracaoBatidas = [8.4, 8.9, 9.2, 8.7, 9.0];

  // --------------------------------------------------------------- Dashboard
  static const dashSessoes = 24;
  static const dashPontos = 24380;
  static const dashVariacao = '▲ 18%';
  static const dashMiniBarras = <double>[
    11,
    14,
    13,
    18,
    16,
    21,
    19,
    25,
    22,
    27,
    24,
    31,
  ];
  static const dashPrecisao = 84;
  static const dashPrecisaoVariacao = '▲ 6 pts no mês';
  static const dashMelhorSequencia = 9;
  static const dashTotalLances = 480;
  static const dashAcertos = 78;
  static const dashKo = 6;
  static const dashErros = 16;
  static const dashDiasTreinados = 5;

  /// Frequência semanal: D S T Q Q S S.
  static const dashSemana = [false, true, true, false, true, true, true];

  // ------------------------------------------------------------------ Perfil
  static const perfilSessoes = 24;
  static const perfilRecorde = 2146;
  static const perfilSequenciaDias = 5;

  // ------------------------------------------------------------------ Ranking
  /// Pódio na ordem [1º, 2º, 3º] e linhas 4º–7º (a 5ª é "Você").
  static const rankingConsistencia = (
    podio: [
      RankEntry(apelido: 'CaioAce', valor: '91%'),
      RankEntry(apelido: 'LeoAce', valor: '88%'),
      RankEntry(apelido: 'TeteDrop', valor: '86%'),
    ],
    linhas: [
      RankEntry(
        apelido: 'LuaSmash',
        detalhe: '11 sessões na semana',
        valor: '85%',
      ),
      RankEntry(
        apelido: 'Você (MariaSaque)',
        detalhe: '12 sessões na semana',
        valor: '84%',
        voce: true,
        inicial: 'M',
      ),
      RankEntry(
        apelido: 'PedroBackhand',
        detalhe: '9 sessões na semana',
        valor: '82%',
      ),
      RankEntry(
        apelido: 'AnaVolley',
        detalhe: '8 sessões na semana',
        valor: '80%',
      ),
    ],
  );

  static const rankingEvolucao = (
    podio: [
      RankEntry(apelido: 'TeteDrop', valor: '+31%'),
      RankEntry(apelido: 'LeoAce', valor: '+26%'),
      RankEntry(apelido: 'AnaVolley', valor: '+22%'),
    ],
    linhas: [
      RankEntry(
        apelido: 'LuaSmash',
        detalhe: 'vs. mês anterior',
        valor: '+20%',
      ),
      RankEntry(
        apelido: 'Você (MariaSaque)',
        detalhe: 'vs. mês anterior',
        valor: '+18%',
        voce: true,
        inicial: 'M',
      ),
      RankEntry(
        apelido: 'PedroBackhand',
        detalhe: 'vs. mês anterior',
        valor: '+15%',
      ),
      RankEntry(apelido: 'CaioAce', detalhe: 'vs. mês anterior', valor: '+12%'),
    ],
  );

  static const rankingFrequencia = (
    podio: [
      RankEntry(apelido: 'LuaSmash', valor: '6 dias'),
      RankEntry(apelido: 'TeteDrop', valor: '6 dias'),
      RankEntry(apelido: 'LeoAce', valor: '5 dias'),
    ],
    linhas: [
      RankEntry(
        apelido: 'PedroBackhand',
        detalhe: '10 sessões na semana',
        valor: '5 dias',
      ),
      RankEntry(
        apelido: 'Você (MariaSaque)',
        detalhe: '12 sessões na semana',
        valor: '5 dias',
        voce: true,
        inicial: 'M',
      ),
      RankEntry(
        apelido: 'AnaVolley',
        detalhe: '7 sessões na semana',
        valor: '4 dias',
      ),
      RankEntry(
        apelido: 'CaioAce',
        detalhe: '5 sessões na semana',
        valor: '3 dias',
      ),
    ],
  );
}
