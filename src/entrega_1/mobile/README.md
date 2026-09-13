> Readme destinado a descrição do módulo do projeto e documentar os passos de execução e desenvolvimento

# Mobile

App Android (só Android — ver ADR na skill do projeto; sem build iOS).

## Instruções de Desenvolvimento

Requer o [Flutter SDK](https://docs.flutter.dev/get-started/install) e o [Android SDK command-line tools](https://developer.android.com/studio#command-tools) (não precisa do Android Studio inteiro) instalados e no `PATH`, com `flutter doctor` sem erros na seção "Android toolchain".

### Rodar em aparelho físico via USB

1. No celular: ative as Opções do desenvolvedor (toque 7x em "Número da versão" em Sobre o telefone) e ligue a Depuração USB.
2. No Linux, garanta que as regras udev do Android estão instaladas (`/etc/udev/rules.d/51-android.rules` — ver [android-udev-rules](https://github.com/M0Rf30/android-udev-rules)), senão o `adb` não enxerga o aparelho sem root.
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

## Stacks

- Flutter
