import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:smart_tennis_arena_mobile/app.dart';
import 'package:smart_tennis_arena_mobile/router.dart';
import 'package:smart_tennis_arena_mobile/state/app_settings.dart';
import 'package:smart_tennis_arena_mobile/state/profile_state.dart';
import 'package:smart_tennis_arena_mobile/widgets/buttons.dart';
import 'package:smart_tennis_arena_mobile/widgets/field.dart';
import 'package:smart_tennis_arena_mobile/widgets/layout.dart';

/// Todas as rotas do app. Os estados da Calibração, o diálogo de exclusão
/// e o Novo treino · Personalizado são testados nos fluxos.
const _rotas = [
  Routes.login,
  '${Routes.cadastro}?perfil=casual',
  '${Routes.cadastro}?perfil=iniciante',
  '${Routes.cadastro}?perfil=infantil',
  Routes.pareamento,
  '${Routes.pareamento}?estado=conectando',
  '${Routes.pareamento}?estado=conectado',
  '${Routes.pareamento}?estado=falha',
  '${Routes.pareamento}?estado=simulador',
  Routes.calibracao,
  Routes.treinos,
  Routes.treinosCatalogo,
  Routes.treinosMeus,
  Routes.treinosNovo,
  '${Routes.treinosEditar}?id=reacao-rapida',
  Routes.sessao,
  Routes.sessaoAndamento,
  Routes.sessaoResumo,
  Routes.historico,
  Routes.historicoDetalhe,
  Routes.historicoDashboard,
  Routes.historicoPendentes,
  Routes.historicoMes,
  Routes.perfil,
  Routes.perfilRecalibrar,
  Routes.perfilNotificacoes,
  Routes.perfilAcessibilidade,
  Routes.perfilConfig,
  Routes.contaExcluida,
  Routes.ranking,
  Routes.rankingEvolucao,
  Routes.rankingFrequencia,
];

/// Tamanhos exigidos pelo checklist da spec (seção 7).
const _tamanhos = [Size(360, 800), Size(412, 915), Size(390, 844)];

Future<void> _carregarRoboto() async {
  final loader = FontLoader('Roboto');
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/Roboto-$peso.ttf'));
  }
  await loader.load();
}

void _tamanhoTela(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  // Barra de status (24) e barra de navegação por gestos (16) simuladas.
  tester.view.padding = const FakeViewPadding(top: 24 * 3, bottom: 16 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _abrir(WidgetTester tester, String rota) async {
  await tester.pumpWidget(
    SmartTennisArenaApp(key: UniqueKey(), initialLocation: rota),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Desmonta o app para cancelar timers e animações em loop.
Future<void> _fechar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
}

Future<void> _tocar(
  WidgetTester tester,
  String texto, {
  bool botao = false,
}) async {
  final alvo =
      (botao ? find.widgetWithText(AppButton, texto) : find.text(texto)).first;
  await tester.ensureVisible(alvo);
  await tester.pump();
  await tester.tap(alvo);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Avança o relógio de 100 em 100 ms até [finder] aparecer (máx. [max]).
Future<void> _esperar(
  WidgetTester tester,
  Finder finder, {
  Duration max = const Duration(seconds: 4),
}) async {
  for (var t = Duration.zero; t < max; t += const Duration(milliseconds: 100)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsOneWidget);
}

/// Número de batidas no centro do anel da Calibração ("n" de "n/5").
Finder _contador(int n) => find.byKey(ValueKey(n));

/// Espera as 5 batidas do simulador, o cálculo e confere cada estado.
Future<void> _calibrar(WidgetTester tester) async {
  expect(find.text('Dê 5 batidas de referência'), findsOneWidget);
  expect(_contador(0), findsOneWidget);
  const medianas = ['8,4 g', '8,7 g', '8,9 g', '8,8 g'];
  for (var n = 1; n <= 4; n++) {
    await _esperar(tester, _contador(n));
    expect(
      find.text('Referência provisória (mediana): ${medianas[n - 1]}'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  }
  await _esperar(tester, find.text('Calculando a mediana…'));
  expect(find.text('Calculando…'), findsOneWidget);
  expect(find.text('Recomeçar'), findsNothing);
  await _esperar(tester, find.text('Calibração concluída'));
  await tester.pump(const Duration(milliseconds: 700));
  expect(find.text('Referência final (mediana): 8,9 g'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

/// PNG 1×1 (foto de perfil falsa).
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGOQjZT+DwACuQGRxBpnmwAAAABJRU5ErkJggg==',
);

/// Câmera e galeria falsas: devolve [resposta] e guarda a origem pedida.
class _FakePicker extends ImagePicker {
  _FakePicker(this.resposta);

  final Future<XFile?> Function() resposta;
  final origens = <ImageSource>[];

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) {
    origens.add(source);
    return resposta();
  }
}

/// O avatar de [tamanho] tem foto?
bool _avatarComFoto(WidgetTester tester, double tamanho) => tester
    .widgetList<Avatar>(find.byType(Avatar))
    .any((a) => a.size == tamanho && a.image != null);

void main() {
  setUpAll(_carregarRoboto);

  for (final size in _tamanhos) {
    for (final grande in [false, true]) {
      final nome =
          '${size.width.toInt()}x${size.height.toInt()}'
          '${grande ? ' · texto grande' : ''}';
      testWidgets('todas as telas abrem sem overflow em $nome', (tester) async {
        _tamanhoTela(tester, size);
        AppSettings.textoGrande.value = grande;
        addTearDown(() => AppSettings.textoGrande.value = false);
        for (final rota in _rotas) {
          await _abrir(tester, rota);
          expect(tester.takeException(), isNull, reason: rota);
          // Garante que a rota realmente abriu (e não ficou no Login).
          if (rota != Routes.login) {
            expect(find.text('TOBIAS'), findsNothing, reason: rota);
          }
        }
        await _fechar(tester);
      });
    }
  }

  testWidgets('fluxo principal: Login → … → Resumo → Detalhe', (tester) async {
    _tamanhoTela(tester, const Size(390, 844));
    await _abrir(tester, Routes.login);
    expect(find.text('TOBIAS'), findsOneWidget);

    await _tocar(tester, 'Entrar', botao: true);
    expect(find.text('Procurando o TOBIAS…'), findsOneWidget);

    await _tocar(tester, 'Conectar ao TOBIAS-01');
    expect(find.text('Conectando ao TOBIAS-01…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Bluetooth conectado'), findsOneWidget);

    await _tocar(tester, 'Continuar para a calibração');
    await _calibrar(tester);

    await _tocar(tester, 'Ir para os treinos');
    expect(find.text('Buscar treino…'), findsOneWidget);

    await _tocar(tester, 'Sessão');
    expect(find.text('Escolha o treino'), findsOneWidget);

    await _tocar(tester, 'Iniciar sessão');
    expect(find.text('Sessão em andamento'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:02'), findsOneWidget);
    // Durante a sessão não há pontuação.
    expect(find.textContaining('pontos'), findsNothing);

    await _tocar(tester, 'Finalizar sessão');
    expect(find.text('Sessão concluída!'), findsOneWidget);

    await _tocar(tester, 'Ver lances da sessão');
    expect(find.text('Sessão de 19 set'), findsOneWidget);
    expect(find.text('Lances (20)'), findsOneWidget);

    // Voltar do Detalhe = pop para o Resumo.
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Sessão concluída!'), findsOneWidget);

    await _tocar(tester, 'Concluir');
    expect(find.text('Histórico'), findsWidgets);
    await _fechar(tester);
  });

  testWidgets('cadastro alterna as 3 variações pelos chips', (tester) async {
    _tamanhoTela(tester, const Size(390, 844));
    await _abrir(tester, Routes.login);
    await _tocar(tester, 'Criar conta');
    expect(find.text('Crie sua conta'), findsOneWidget);
    expect(find.text('Nome completo'), findsOneWidget);

    await _tocar(tester, 'Iniciante');
    expect(find.text('Modo iniciante'), findsOneWidget);

    await _tocar(tester, 'Modo infantil');
    expect(find.text('Nome do jogador'), findsOneWidget);
    expect(
      find.text('Um responsável precisa criar a conta do jogador.'),
      findsOneWidget,
    );
    await _fechar(tester);
  });

  testWidgets('excluir conta pede confirmação e volta ao Login', (
    tester,
  ) async {
    _tamanhoTela(tester, const Size(390, 844));
    await _abrir(tester, Routes.perfil);
    await _tocar(tester, 'Configurações do perfil');
    await _tocar(tester, 'Excluir minha conta');
    expect(find.text('Excluir sua conta?'), findsOneWidget);

    await _tocar(tester, 'Não, manter minha conta');
    expect(find.text('Excluir sua conta?'), findsNothing);

    await _tocar(tester, 'Excluir minha conta');
    await _tocar(tester, 'Sim, excluir');
    expect(find.text('Conta excluída'), findsOneWidget);

    await _tocar(tester, 'Voltar ao início');
    expect(find.text('TOBIAS'), findsOneWidget);
    await _fechar(tester);
  });

  testWidgets('chips das abas trocam de tela', (tester) async {
    _tamanhoTela(tester, const Size(390, 844));
    await _abrir(tester, Routes.treinos);
    await _tocar(tester, 'Catálogo');
    expect(find.text('Resistência'), findsOneWidget);
    await _tocar(tester, 'Meus treinos');
    expect(find.text('Minha sequência'), findsOneWidget);

    await _tocar(tester, 'Histórico');
    await _tocar(tester, 'Pendentes');
    expect(find.text('2 sessões aguardando envio'), findsOneWidget);
    await _tocar(tester, 'Dashboard');
    expect(find.text('Distribuição dos lances'), findsOneWidget);

    await _tocar(tester, 'Ranking');
    expect(find.text('CaioAce'), findsWidgets);
    await _tocar(tester, 'Frequência');
    expect(find.text('Quem mais treinou nesta semana.'), findsOneWidget);
    await _fechar(tester);
  });

  for (final size in [const Size(360, 800), const Size(412, 915)]) {
    testWidgets(
      'calibração passa pelos 7 estados em ${size.width.toInt()}x${size.height.toInt()} · texto grande',
      (tester) async {
        _tamanhoTela(tester, size);
        AppSettings.textoGrande.value = true;
        addTearDown(() => AppSettings.textoGrande.value = false);
        await _abrir(tester, Routes.calibracao);
        await _calibrar(tester);
        await _tocar(tester, 'Recalibrar');
        expect(_contador(0), findsOneWidget);
        await _fechar(tester);
      },
    );
  }

  testWidgets('pareamento: falha, tentar de novo e simulador', (tester) async {
    _tamanhoTela(tester, const Size(390, 844));
    await _abrir(tester, Routes.pareamento);
    await _tocar(tester, 'TOBIAS-02');
    expect(find.text('Não foi possível conectar ao boneco'), findsOneWidget);
    expect(find.text('Como conectar'), findsOneWidget);

    await _tocar(tester, 'Tentar novamente');
    expect(find.text('Conectando ao TOBIAS-01…'), findsOneWidget);
    await _tocar(tester, 'Cancelar');
    expect(find.text('Procurando o TOBIAS…'), findsOneWidget);

    await _tocar(tester, 'Usar simulador (sem calibração)');
    expect(find.text('Simulador pronto'), findsOneWidget);
    await _tocar(tester, 'Começar a treinar');
    expect(find.text('Escolha o treino'), findsOneWidget);
    await _fechar(tester);
  });

  testWidgets(
    'novo treino: slider vira Personalizado e tempo = lances × intervalo',
    (tester) async {
      _tamanhoTela(tester, const Size(390, 844));
      await _abrir(tester, Routes.treinosNovo);
      expect(find.text('20 lances × 3 s'), findsOneWidget);
      expect(find.text('1 min'), findsOneWidget);
      expect(find.text('Treino personalizado'), findsNothing);

      await _tocar(tester, 'Personalizado');
      expect(find.text('Treino personalizado'), findsOneWidget);
      expect(
        find.text(
          'Você mudou os valores do nível Médio. Este treino será salvo como Personalizado.',
        ),
        findsOneWidget,
      );

      await _tocar(tester, 'Fácil');
      expect(find.text('Treino personalizado'), findsNothing);
      expect(find.text('15 lances × 4 s'), findsOneWidget);
      await _fechar(tester);
    },
  );

  testWidgets('nenhuma tela mostra reação nem consistência no resumo', (
    tester,
  ) async {
    _tamanhoTela(tester, const Size(390, 844));
    for (final rota in [
      Routes.treinos,
      Routes.treinosNovo,
      Routes.sessao,
      Routes.sessaoResumo,
      Routes.historicoDetalhe,
      Routes.historicoDashboard,
    ]) {
      await _abrir(tester, rota);
      expect(find.textContaining('Janela'), findsNothing, reason: rota);
      expect(find.textContaining('Reação média'), findsNothing, reason: rota);
      expect(
        find.textContaining(RegExp(r'reação \d')),
        findsNothing,
        reason: rota,
      );
    }
    await _abrir(tester, Routes.sessaoResumo);
    expect(find.text('Consistência'), findsNothing);
    expect(find.text('KO'), findsOneWidget);
    expect(find.text('Erros'), findsOneWidget);
    await _fechar(tester);
  });

  testWidgets('cadastro valida o CPF', (tester) async {
    _tamanhoTela(tester, const Size(390, 844));
    await _abrir(tester, Routes.cadastro);
    expect(find.text('Modo casual'), findsOneWidget);
    final cpf = find.widgetWithText(AppField, 'CPF');
    await tester.ensureVisible(cpf);
    await tester.enterText(
      find.descendant(of: cpf, matching: find.byType(EditableText)),
      '11111111111',
    );
    await tester.pump();
    expect(find.text('111.111.111-11'), findsOneWidget);
    expect(find.text('CPF inválido. Confira os números.'), findsOneWidget);
    await _fechar(tester);
  });

  group('foto de perfil', () {
    setUp(() => ProfileState.foto.value = null);
    tearDown(() {
      ProfileState.foto.value = null;
      ProfileState.picker = ImagePicker();
    });

    testWidgets('galeria escolhe a foto e salvar leva ao Perfil', (
      tester,
    ) async {
      _tamanhoTela(tester, const Size(390, 844));
      final picker = _FakePicker(
        () async => XFile.fromData(_png, mimeType: 'image/png'),
      );
      ProfileState.picker = picker;
      await _abrir(tester, Routes.perfil);
      await _tocar(tester, 'Configurações do perfil');
      expect(_avatarComFoto(tester, 96), isFalse);

      await _tocar(tester, 'Galeria');
      expect(picker.origens, [ImageSource.gallery]);
      expect(_avatarComFoto(tester, 96), isTrue);
      // Ainda não salvou: o Perfil continua com a inicial.
      expect(ProfileState.foto.value, isNull);

      await _tocar(tester, 'Salvar alterações');
      expect(find.text('Recalibrar o TOBIAS'), findsOneWidget);
      expect(_avatarComFoto(tester, 64), isTrue);
      expect(tester.takeException(), isNull);
      await _fechar(tester);
    });

    testWidgets('tirar foto abre a câmera; cancelar mantém a inicial', (
      tester,
    ) async {
      _tamanhoTela(tester, const Size(390, 844));
      final picker = _FakePicker(() async => null);
      ProfileState.picker = picker;
      await _abrir(tester, Routes.perfilConfig);
      await _tocar(tester, 'Tirar foto');
      expect(picker.origens, [ImageSource.camera]);
      expect(_avatarComFoto(tester, 96), isFalse);
      await _fechar(tester);
    });

    testWidgets('câmera indisponível mostra aviso', (tester) async {
      _tamanhoTela(tester, const Size(390, 844));
      ProfileState.picker = _FakePicker(
        () async => throw PlatformException(code: 'camera_access_denied'),
      );
      await _abrir(tester, Routes.perfilConfig);
      await _tocar(tester, 'Tirar foto');
      expect(
        find.textContaining('Não foi possível abrir a câmera'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await _fechar(tester);
    });
  });
}
