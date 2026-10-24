import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/mock_data.dart';
import '../../router.dart';
import '../../state/profile_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_text.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/field.dart';
import '../../widgets/layout.dart';

/// 6.5 Perfil · Configurações do perfil (69:2209).
///
/// "Tirar foto" abre a câmera e "Galeria" abre o seletor de fotos do
/// Android. A foto escolhida aparece no avatar na hora e só vale para o
/// perfil depois de "Salvar alterações".
class ConfigPerfilScreen extends StatefulWidget {
  const ConfigPerfilScreen({super.key});

  @override
  State<ConfigPerfilScreen> createState() => _ConfigPerfilScreenState();
}

class _ConfigPerfilScreenState extends State<ConfigPerfilScreen> {
  var _foto = ProfileState.foto.value;

  Future<void> _escolherFoto(ImageSource origem) async {
    try {
      final arquivo = await ProfileState.picker.pickImage(
        source: origem,
        // Avatar pequeno: limita o tamanho para não pesar na memória.
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.front,
      );
      if (arquivo == null) return; // Cancelou.
      final bytes = await arquivo.readAsBytes();
      if (mounted) setState(() => _foto = bytes);
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            origem == ImageSource.camera
                ? 'Não foi possível abrir a câmera. Verifique a permissão nas configurações do celular.'
                : 'Não foi possível abrir a galeria.',
          ),
        ),
      );
    }
  }

  void _salvar() {
    ProfileState.foto.value = _foto;
    goBack(context, Routes.perfil);
  }

  @override
  Widget build(BuildContext context) {
    void voltar() => goBack(context, Routes.perfil);
    const u = Mock.user;
    return StackedScreen(
      title: 'Configurações do perfil',
      onBack: voltar,
      children: [
        SectionCard(
          title: 'Foto de perfil',
          gap: 14,
          children: [
            Center(
              child: SizedBox.square(
                dimension: 96,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Avatar(
                      letter: u.nome[0],
                      size: 96,
                      style: AppText.displayLarge.c(AppColors.textOnBrand),
                      image: _foto == null ? null : MemoryImage(_foto!),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.bgAccent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.bgSurface,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          AppIcons.camera,
                          size: 16,
                          color: AppColors.iconOnAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              spacing: 10,
              children: [
                Expanded(
                  child: AppButton.outline(
                    'Tirar foto',
                    icon: AppIcons.camera,
                    compact: true,
                    onPressed: () => _escolherFoto(ImageSource.camera),
                  ),
                ),
                Expanded(
                  child: AppButton.outline(
                    'Galeria',
                    icon: AppIcons.image,
                    compact: true,
                    onPressed: () => _escolherFoto(ImageSource.gallery),
                  ),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: 'Apelido no ranking',
          children: [
            AppField(
              label: 'Apelido',
              initialValue: u.apelido,
              helper:
                  'É o nome que aparece no ranking. Use um apelido, não seu nome real.',
            ),
          ],
        ),
        SectionCard(
          title: 'Excluir conta',
          titleStyle: AppText.titleM.c(AppColors.textError),
          border: Border.all(color: AppColors.borderError, width: 1.5),
          children: [
            Text(
              'Remove sua conta, seu histórico e suas pontuações. Essa ação não pode ser desfeita.',
              style: AppText.bodyM.c(AppColors.textSecondary),
            ),
            AppButton.danger(
              'Excluir minha conta',
              icon: AppIcons.trash,
              onPressed: () => showConfirmarExclusao(context),
            ),
          ],
        ),
        const Spacer(),
        AppButton('Salvar alterações', onPressed: _salvar),
      ],
    );
  }
}

/// 6.6 Perfil · Confirmar exclusão (73:2347).
Future<void> showConfirmarExclusao(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: AppColors.overlay,
    builder: (dialogContext) => Dialog(
      backgroundColor: AppColors.bgSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.r28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.bgErrorSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                AppIcons.alertOctagon,
                size: 32,
                color: AppColors.iconError,
              ),
            ),
            Text(
              'Excluir sua conta?',
              textAlign: TextAlign.center,
              style: AppText.headlineM,
            ),
            Text(
              'Todo o seu histórico, suas pontuações e as sessões salvas serão apagados para sempre. Você não poderá recuperar nada depois.',
              textAlign: TextAlign.center,
              style: AppText.bodyM.c(AppColors.textSecondary),
            ),
            AppButton(
              'Não, manter minha conta',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            AppButton.danger(
              'Sim, excluir',
              onPressed: () {
                Navigator.of(dialogContext).pop();
                context.go(Routes.contaExcluida);
              },
            ),
          ],
        ),
      ),
    ),
  );
}
