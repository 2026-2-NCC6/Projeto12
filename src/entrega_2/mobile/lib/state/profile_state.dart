import 'package:flutter/foundation.dart';

/// Perfil do usuário no app (somente em memória).
///
/// A foto de perfil está fora do escopo (não há endpoint): a tela não oferece
/// mais câmera nem galeria, e o avatar usa a inicial do apelido. O campo fica
/// porque a exclusão de conta o zera junto com o resto do estado local.
abstract final class ProfileState {
  /// Foto de perfil (bytes) ou nula = avatar com a inicial.
  static final foto = ValueNotifier<Uint8List?>(null);
}
