> Readme destinado a descrição do módulo do projeto e documentar os passos de execução e desenvolvimento

# Mobile

App Android (só Android — ver ADR na skill do projeto; sem build iOS).

**TOBIAS** — front-end das 29 telas do Figma (`TOBIAS_UI_SPEC.md`), com dados de exemplo e navegação completa. Sem backend e sem BLE real: tudo vem de [lib/data/mock_data.dart](lib/data/mock_data.dart).

## Estrutura

```
lib/
  main.dart, app.dart     # entrada do app e MaterialApp.router
  router.dart             # rotas (go_router): abas no ShellRoute + telas empilhadas
  theme/                  # tokens: cores, tipografia, raios/sombras, ícones
  widgets/                # componentes reutilizáveis (AppBarX, botões, chips, cards…)
  screens/                # telas por fluxo: auth, connect, treinos, sessao, historico, ranking, perfil
  data/                   # modelos, mocks e formatação pt-BR
  state/                  # preferências globais (tamanho do texto)
assets/fonts/             # Roboto empacotada (licença OFL)
test/widget_test.dart     # abre todas as telas em 360×800, 412×915 e 390×844 + fluxos de navegação
```

## Instruções de Desenvolvimento

Requer o [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.32+; testado no 3.47) e o [Android SDK command-line tools](https://developer.android.com/studio#command-tools) (não precisa do Android Studio inteiro) instalados e no `PATH`, com `flutter doctor` sem erros na seção "Android toolchain".

No Windows, o jeito mais simples é instalar o Android Studio (ele traz o JDK e o SDK) e depois rodar `flutter doctor --android-licenses`.

### Rodar em aparelho físico via USB

1. No celular: ative as Opções do desenvolvedor (toque 7x em "Número da versão" em Sobre o telefone) e ligue a Depuração USB.
2. No Linux, garanta que as regras udev do Android estão instaladas (`/etc/udev/rules.d/51-android.rules` — ver [android-udev-rules](https://github.com/M0Rf30/android-udev-rules)), senão o `adb` não enxerga o aparelho sem root. No Windows, instale o driver USB do fabricante do celular (ou o Google USB Driver, pelo SDK Manager).
3. Conecte o cabo e aceite o prompt de autorização de depuração USB que aparece na tela do celular.
4. Confirme com `adb devices` que o aparelho aparece como `device` (não `unauthorized`).

```bash
# Instalar dependências
flutter pub get

# Rodar no aparelho conectado
flutter run

# Analisar e rodar os testes
flutter analyze
flutter test
```

### Dicas para testar o front-end

- O app abre no **Login**. Fluxo principal: Entrar → Pareamento → Calibração → Treinos → aba Sessão → Iniciar → Finalizar → Resumo → Ver lances.
- **Atalho sem boneco:** no Pareamento, "Usar simulador (sem dispositivo)" vai direto para a Sessão · Seleção.
- **Calibração:** toque no anel para simular uma batida; com 5/5 o botão "Concluir calibração" fica ativo (no protótipo ele navega mesmo antes).
- **Acessibilidade → Tamanho do texto → Grande** aumenta o texto do app inteiro.
- Para abrir direto numa tela durante o desenvolvimento, troque `initialLocation` em [lib/app.dart](lib/app.dart) por uma rota de [lib/router.dart](lib/router.dart) (ex.: `Routes.historicoDashboard`).

## Stacks

- Flutter
