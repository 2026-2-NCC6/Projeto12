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

  // -------------------------------------------------------------- Calibração
  /// Picos das 5 batidas de referência que o simulador envia, em g
  /// (mediana = 8,9 g).
  static const calibracaoBatidas = [8.4, 8.9, 9.2, 8.7, 9.0];

  // ------------------------------------------------------------------ Perfil
  static const perfilSessoes = 24;
  static const perfilRecorde = 2146;
  static const perfilSequenciaDias = 5;
}
