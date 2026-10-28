import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Perfil do usuário no app (somente em memória; ainda não há endpoint para
/// foto de perfil).
abstract final class ProfileState {
  /// Foto de perfil salva (bytes da imagem) ou nula = avatar com a inicial.
  /// Bytes em vez de caminho de arquivo para manter o build web possível.
  static final foto = ValueNotifier<Uint8List?>(null);

  /// Abre a câmera ou a galeria. Trocável nos testes.
  static ImagePicker picker = ImagePicker();
}
